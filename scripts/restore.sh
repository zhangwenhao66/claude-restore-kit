#!/usr/bin/env bash
# ============================================================================
# Claude Desktop — bring your work BACK from a gateway ("3p") deployment into a
# normal, logged-in Anthropic account.
#
#   bash restore.sh check   read-only preflight (safe while Claude is running)
#   bash restore.sh test    backup + copy the 20 most recent non-routine sessions
#   bash restore.sh all     backup (reused) + remaining sessions + tasks + Cowork
#
# Safety design:
#   * copy only — the source partition is never modified, moved or deleted
#   * a verified backup before anything is written
#   * scheduled tasks MERGED by id, never blindly overwritten (the target is a
#     live account that may already have its own routines)
#   * a manifest per phase, so rollback.sh can undo precisely
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"   # generated artifacts (backups, manifests, logs) land here
if [ ! -f "$HERE/config.sh" ]; then
  echo "config.sh not found." >&2
  echo "  1. Run:  bash \"$HERE/find-partitions.sh\"" >&2
  echo "  2. Then: cp \"$HERE/config.example.sh\" \"$HERE/config.sh\"  and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HERE/config.sh"

MODE="${1:-check}"
STAMP="$(date +%Y%m%d-%H%M%S)"
MAN_S="$ROOT/manifest-sessions.txt"
MAN_C="$ROOT/manifest-cowork.txt"

die() { echo "ABORT: $*" >&2; exit 1; }
cnt() { find "$1" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' '; }

echo "=== Claude restore (gateway -> account) · mode=${MODE} · $(date)"
echo "    source (gateway): ${CODE_SRC}"
echo "    target (account): ${CODE_DST}"

case "${MODE}" in check|test|all) ;; *) die "usage: restore.sh check|test|all" ;; esac

# ---------------------------------------------------------------- preflight
[ -d "${CODE_SRC}" ] || die "source partition not found: ${CODE_SRC}"
[ -d "${CODE_DST}" ] || die "target partition not found: ${CODE_DST} (open Claude once with the new account)"
[ "${CODE_SRC}" != "${CODE_DST}" ] || die "source and target are the same"

SRC_N="$(cnt "${CODE_SRC}")"; DST_N="$(cnt "${CODE_DST}")"
echo "    sessions: source=${SRC_N} target=${DST_N}"
[ "${SRC_N}" -gt 0 ] || die "source has no sessions"

TASK_SRC="${CODE_SRC}/scheduled-tasks.json"
TASK_DST="${CODE_DST}/scheduled-tasks.json"
[ -f "${TASK_SRC}" ] || die "source has no scheduled-tasks.json"
# Never let a missing or corrupt target file escape as a bare traceback: `check` is step 3 of
# the README, and a Python stack trace there reads like the kit is broken.
task_count() {
  python3 - "$1" <<'PY'
import json, sys
try:
    print(len(json.load(open(sys.argv[1])).get("scheduledTasks", [])))
except Exception:
    print(0)
PY
}
TASK_SRC_N="$(task_count "${TASK_SRC}")"
TASK_DST_N="$(task_count "${TASK_DST}")"
if [ ! -f "${TASK_DST}" ]; then
  echo "    note    : the account has no scheduled-tasks.json yet; one will be created"
fi
echo "    tasks   : source=${TASK_SRC_N} target=${TASK_DST_N}"

# The target here is a LIVE account, not a fresh gateway partition, so it may already have
# its own routines. Refusing to continue would be wrong; blindly overwriting would be worse.
TASK_MODE="${TASK_MODE:-merge}"
case "${TASK_MODE}" in merge|replace|skip) ;; *) die "TASK_MODE must be merge|replace|skip" ;; esac
echo "    task mode: ${TASK_MODE}"
if [ "${TASK_DST_N}" -gt 0 ]; then
  case "${TASK_MODE}" in
    merge)   echo "              ids in both -> updated from the source; target-only ids kept untouched" ;;
    replace) echo "              target task list will be REPLACED by the source list (backed up first)" ;;
    skip)    echo "              target task list left alone; only sessions and Cowork are restored" ;;
  esac
fi

if [ "${MIGRATE_COWORK:-0}" = "1" ]; then
  [ -d "${COW_SRC}" ] || die "Cowork source not found: ${COW_SRC}"
  [ -d "${COW_DST}" ] || die "Cowork target not found: ${COW_DST}"
  echo "    cowork  : source=$(cnt "${COW_SRC}")"
fi

AVAIL_G="$(df -g "$HOME" | awk 'NR==2{print $4}')"
echo "    free    : ${AVAIL_G} GB"
[ "${AVAIL_G}" -ge 60 ] || die "need at least 60 GB free"

echo "OK preflight"
[ "${MODE}" = "check" ] && { echo "(read-only; nothing changed)"; exit 0; }

# ------------------------------------------------------------- app guard
# The app must be fully quit: it caches scheduling state in memory and writes it back on exit.
# claude_app_pids() ignores the helpers that are not the app — see scripts/lib-appguard.sh.
# shellcheck source=/dev/null
source "$HERE/lib-appguard.sh"
LIVE="$(claude_app_pids | wc -l | tr -d ' ')"
[ "${LIVE}" -eq 0 ] || die "Claude Desktop is still running (${LIVE} process(es)). Quit it with ⌘Q and retry."
echo "OK Claude is not running"

# ------------------------------------------------------------- backup
# A reused backup is only a backup if it is still there. Deleting backup-* to free space
# (a normal thing to do between `test` and `all`) or moving the repo would otherwise leave
# .backup-done pointing at a path that no longer exists — and the run would then write into
# a live account partition with no backup at all, while reporting success.
BK=""
if [ -f "$ROOT/.backup-done" ]; then
  CAND="$(cat "$ROOT/.backup-done" 2>/dev/null || true)"
  if [ -n "${CAND}" ] && [ -d "${CAND}/app-data" ] && [ -d "${CAND}/dot-claude" ]; then
    BK="${CAND}"
  else
    echo "--- backup: previous backup at '${CAND:-<empty>}' is gone or incomplete; making a new one"
    rm -f "$ROOT/.backup-done"
  fi
fi
if [ -n "${BK}" ]; then
  echo "--- backup: reusing ${BK}"
else
  BK="$ROOT/backup-$STAMP"; mkdir -p "$BK"
  echo "--- backup (APFS clone) -> ${BK}"
  # -c clones (instant, near-zero space) but only works on APFS; fall back to a real copy.
  cp -Rpc "$APP_NEW" "$BK/app-data" 2>"$BK/.err1" || cp -Rp "$APP_NEW" "$BK/app-data" 2>>"$BK/.err1" || true
  cp -Rpc "$HOME/.claude" "$BK/dot-claude" 2>"$BK/.err2" || cp -Rp "$HOME/.claude" "$BK/dot-claude" 2>>"$BK/.err2" || true
  FAIL=0
  for pair in "$APP_NEW|$BK/app-data" "$HOME/.claude|$BK/dot-claude"; do
    a="$(find "${pair%%|*}" 2>/dev/null | wc -l | tr -d ' ')"
    b="$(find "${pair##*|}" 2>/dev/null | wc -l | tr -d ' ')"
    echo "    ${pair%%|*}: source=$a backup=$b"
    [ "$a" = "$b" ] || FAIL=1
  done
  [ "${FAIL}" -eq 0 ] || die "backup file counts differ (source untouched, safe). Nothing was written."
  echo "$BK" > "$ROOT/.backup-done"
  echo "OK backup verified"
fi

# ------------------------------------------------------------- sessions
echo "--- sessions (mode=${MODE})"
touch "$MAN_S"
COPIED=0; SKIPPED=0; FAILED=0

if [ "${MODE}" = "test" ]; then
  # 20 most recent sessions that were NOT spawned by a routine (routine sessions only show up
  # after their task is imported, so they would make the test look like a failure).
  LIST="$(python3 - "${CODE_SRC}" <<'PY'
import json, os, glob, sys
d = sys.argv[1]; rows = []
for f in glob.glob(os.path.join(d, "local_*.json")):
    try:
        j = json.load(open(f))
    except Exception:
        continue
    if j.get("scheduledTaskId") or j.get("spawnedFrom") or j.get("agentDispatched"):
        continue
    t = j.get("lastActivityAt") or j.get("createdAt") or 0
    rows.append((t, os.path.basename(f)))
rows.sort(reverse=True)
for _, b in rows[:20]:
    print(b)
PY
)"
else
  LIST="$(find "${CODE_SRC}" -maxdepth 1 -name 'local_*.json' -exec basename {} \;)"
fi

# Same-named files are the norm here, not an edge case: on the machine this kit was written on
# all 2847 target sessions also existed in the source. Most are byte-identical, but a third of
# the differing ones had a NEWER source — the session had been used on the gateway since the
# account last saw it. Skipping those silently threw away the newer state (completedTurns, model,
# lastAssistantUuid, publishedArtifacts, lastActivityAt). Decide per file, and never lose either
# copy: the target's version is parked in replaced-sessions/<stamp>/ before it is overwritten.
DEC_FILE="$ROOT/.decisions-$STAMP"
NAMES_FILE="$ROOT/.names-$STAMP"
REPL_DIR="$ROOT/replaced-sessions/$STAMP"
CONF_FILE="$ROOT/conflicts-$STAMP.txt"
MAN_R="$ROOT/manifest-replaced.txt"

# The name list goes through a file, not a pipe: `python3 - <<'PY'` already consumes stdin with
# the heredoc, so anything piped in would be silently dropped.
printf '%s\n' ${LIST} > "$NAMES_FILE"
python3 - "${CODE_SRC}" "${CODE_DST}" "$NAMES_FILE" > "$DEC_FILE" <<'PY'
import json, os, sys

src, dst, names_file = sys.argv[1], sys.argv[2], sys.argv[3]


def activity(path):
    try:
        with open(path, "rb") as fh:
            j = json.load(fh)
    except Exception:
        return None
    v = j.get("lastActivityAt") or j.get("createdAt")
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


for name in open(names_file, encoding="utf-8").read().splitlines():
    name = name.strip()
    if not name:
        continue
    a, b = os.path.join(src, name), os.path.join(dst, name)
    if not os.path.exists(b):
        print(f"{name}\tADD")
        continue
    try:
        if open(a, "rb").read() == open(b, "rb").read():
            print(f"{name}\tSAME")
            continue
    except OSError:
        print(f"{name}\tKEEP_UNREADABLE")
        continue
    ta, tb = activity(a), activity(b)
    if ta is None or tb is None:
        # Cannot tell which is newer -> do not guess. Keep the target's, report it.
        print(f"{name}\tKEEP_UNREADABLE")
    elif ta > tb:
        print(f"{name}\tREPLACE")
    else:
        print(f"{name}\tKEEP_TARGET_NEWER")
PY

COPIED=0; SKIPPED=0; FAILED=0; REPLACED=0; KEPT=0
while IFS="$(printf '\t')" read -r b decision; do
  [ -n "${b}" ] || continue
  case "${decision}" in
    ADD)
      if cp -p "${CODE_SRC}/${b}" "${CODE_DST}/${b}"; then
        echo "${CODE_DST}/${b}" >> "$MAN_S"; COPIED=$((COPIED+1))
      else
        FAILED=$((FAILED+1))
      fi
      ;;
    SAME)
      SKIPPED=$((SKIPPED+1))
      ;;
    REPLACE)
      mkdir -p "$REPL_DIR"
      if ! cp -p "${CODE_DST}/${b}" "${REPL_DIR}/${b}"; then FAILED=$((FAILED+1)); continue; fi
      printf '%s\t%s\n' "${CODE_DST}/${b}" "${REPL_DIR}/${b}" >> "$MAN_R"
      if cp -p "${CODE_SRC}/${b}" "${CODE_DST}/${b}"; then
        REPLACED=$((REPLACED+1))
      else
        FAILED=$((FAILED+1))
      fi
      ;;
    KEEP_TARGET_NEWER|KEEP_UNREADABLE)
      KEPT=$((KEPT+1)); echo "${CODE_DST}/${b}  (${decision})" >> "$CONF_FILE"
      ;;
    *)
      SKIPPED=$((SKIPPED+1))
      ;;
  esac
done < "$DEC_FILE"

echo "    copied=${COPIED} identical=${SKIPPED} replaced=${REPLACED} kept-target=${KEPT} failed=${FAILED}"
if [ "${REPLACED}" -gt 0 ]; then
  echo "    ${REPLACED} session(s) were UPDATED from the gateway; the account's older copy of each is"
  echo "    parked in replaced-sessions/${STAMP}/ and listed in manifest-replaced.txt."
fi
if [ "${KEPT}" -gt 0 ]; then
  echo "    ${KEPT} session(s) differ and the ACCOUNT's copy was kept (it was newer, or the pair"
  echo "    could not be compared). Details: $(basename "$CONF_FILE")"
fi
[ "${FAILED}" -eq 0 ] || die "some copies failed; do not continue. Nothing else was written; sessions already copied can be undone with: bash rollback.sh"
echo "    target now $(cnt "${CODE_DST}") sessions; source still $(cnt "${CODE_SRC}")"
[ "$(cnt "${CODE_SRC}")" = "${SRC_N}" ] || die "source session count changed!"

if [ "${MODE}" = "test" ]; then
  cat <<EOF

Test copy done (${COPIED} sessions).
  1. Reopen Claude Desktop.
  2. Confirm the sessions appear in the sidebar and that opening one shows full history.
  3. If they do NOT appear, run: bash rollback.sh   — then stop and investigate.
  4. If they do, quit Claude and run: bash restore.sh all
EOF
  exit 0
fi

# bring along archive/backlog state if present and not already there.
# Recorded in the manifest, or rollback cannot undo the copy (it used to be untracked, so a
# rollback left archived-sessions.idx and backlog behind — see docs/05-pitfalls.md).
for extra in archived-sessions.idx backlog; do
  [ -e "${CODE_SRC}/${extra}" ] || continue
  if [ ! -e "${CODE_DST}/${extra}" ]; then
    cp -Rp "${CODE_SRC}/${extra}" "${CODE_DST}/${extra}"
    echo "${CODE_DST}/${extra}" >> "$MAN_S"
    echo "    carried over ${extra}"
  elif ! diff -rq "${CODE_SRC}/${extra}" "${CODE_DST}/${extra}" >/dev/null 2>&1; then
    echo "    NOTE: ${extra} exists on both sides and differs; the target's copy was kept."
    echo "          The gateway's archive state was NOT brought over."
  fi
done

# ------------------------------------------------------------- tasks
echo "--- scheduled tasks (mode=${TASK_MODE}, imported DISABLED)"
if [ -f "${TASK_DST}" ]; then
  cp -p "${TASK_DST}" "${TASK_DST}.pre-import-backup-${STAMP}"
else
  # Marked so rollback knows the correct undo is to DELETE this file, not restore one.
  echo "    (no target scheduled-tasks.json to back up; a new one will be created)"
  echo "${TASK_DST}" > "$ROOT/.tasks-created-by-restore"
fi
cp -p "${TASK_SRC}" "$ROOT/source-tasks-${STAMP}.json"

set +e
python3 - "${TASK_SRC}" "${TASK_DST}" "${TASK_MODE}" "$ROOT" "$STAMP" <<'PY'
import copy, datetime, json, os, sys

src_path, dst_path, mode, out_root, stamp = sys.argv[1:6]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

src_tasks = json.load(open(src_path)).get("scheduledTasks", [])
try:
    dst_doc = json.load(open(dst_path))
except FileNotFoundError:
    dst_doc = {}
    print("    note: the account had no scheduled-tasks.json; creating one")
except Exception as exc:
    print(f"    ABORT: the account's scheduled-tasks.json is not readable ({exc}).")
    print("           Nothing was written. Fix or move that file, then re-run.")
    sys.exit(1)
if not isinstance(dst_doc, dict):
    print("    ABORT: the account's scheduled-tasks.json is not a JSON object. Nothing was written.")
    sys.exit(1)
dst_tasks = dst_doc.get("scheduledTasks", [])


def dedupe(tasks, side):
    """Task ids here are human-readable slugs ("daily-backlink-building"), not uuids, so a
    duplicate is a real possibility. Keep the first occurrence and report the rest: writing a
    file in which two tasks share an id has undefined behaviour in the App, and silently
    dropping one would be worse."""
    seen, kept, dupes = set(), [], []
    for t in tasks:
        tid = t.get("id")
        if tid is None:
            dupes.append("<task with no id>")
            continue
        if tid in seen:
            dupes.append(str(tid))
            continue
        seen.add(tid)
        kept.append(t)
    if dupes:
        print(f"    WARNING: {len(dupes)} duplicate / untagged task(s) in the {side} list: "
              f"{', '.join(dupes[:10])}")
    return kept


src_tasks = dedupe(src_tasks, "source (gateway)")
dst_tasks = dedupe(dst_tasks, "target (account)")

src_ids = [x["id"] for x in src_tasks]
src_set = set(src_ids)
src_was_enabled = sorted(x["id"] for x in src_tasks if x.get("enabled"))

# Captured BEFORE anything is written. Task ids are slugs, so "both deployments have this id"
# is the normal case, not an edge case. When that happens the gateway's definition wins and the
# task is imported disabled — which means an account-side routine that was running gets turned
# off. Without this list there is no way to know which ones, and no way to turn them back on.
dst_was_enabled = sorted(x["id"] for x in dst_tasks if x.get("enabled"))


def stamp_task(task):
    """Import one task DISABLED, with its missed-run window pushed to now.

    Without the stamp, Claude Desktop replays every window the task missed while it sat
    stopped in the other deployment. Some of those tasks publish, post or send mail, and
    that replay cannot be taken back.
    """
    t = copy.deepcopy(task)
    t["enabled"] = False
    t["lastScheduledFor"] = now
    t["missedRunScanFloor"] = now
    return t


if mode == "skip":
    merged = dst_tasks
    added, updated, dropped = [], [], []
    kept = [x["id"] for x in dst_tasks]
    write = False
elif mode == "replace":
    merged = [stamp_task(x) for x in src_tasks]
    added, updated, kept = src_ids, [], []
    dropped = [x["id"] for x in dst_tasks]
    write = True
else:  # merge
    index = {x["id"]: i for i, x in enumerate(dst_tasks)}   # dst_tasks is already deduped
    merged = copy.deepcopy(dst_tasks)
    added, updated = [], []
    for x in src_tasks:
        if x["id"] in index:
            merged[index[x["id"]]] = stamp_task(x)
            updated.append(x["id"])
        else:
            index[x["id"]] = len(merged)     # keep the index in step, or a repeated source
            merged.append(stamp_task(x))     # id would be appended twice
            added.append(x["id"])
    kept = [x["id"] for x in dst_tasks if x["id"] not in src_set]
    dropped = []
    write = True

# ------------------------------------------------------------------ validate BEFORE writing
# Everything below used to run after os.replace, which meant a bad merge was already on disk
# by the time the script died — half-migrated, with an enabled task carrying a stale floor.
problems = []
out_ids = [t["id"] for t in merged]
if len(out_ids) != len(set(out_ids)):
    dupes = sorted({i for i in out_ids if out_ids.count(i) > 1})
    problems.append(f"the result would contain duplicate ids: {dupes[:10]}")
if write:
    leaked = [t["id"] for t in merged if t.get("enabled") and t["id"] in src_set]
    if leaked:
        problems.append(f"imported task(s) would be left ENABLED: {leaked[:10]}")
if problems:
    print("    VALIDATION FAILED — nothing was written:")
    for p in problems:
        print("      - " + p)
    sys.exit(1)

if write:
    out = copy.deepcopy(dst_doc)
    out["scheduledTasks"] = merged
    # Deliberately NOT touching out["recordedSkips"]: the target is a live account with its
    # own routines, and clearing its skip ledger could make those replay missed windows.
    tmp = dst_path + ".tmp"
    json.dump(out, open(tmp, "w"), ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, dst_path)
    final = json.load(open(dst_path))["scheduledTasks"]
else:
    final = dst_tasks
    print("    TASK_MODE=skip — the account's scheduled-tasks.json was not written")

still_enabled = [x["id"] for x in final if x.get("enabled")]
# "lost" = was running in the account, still present after the merge, now disabled because the
# gateway supplied a newer definition for the same id. In skip mode nothing is written, so
# nothing can have been lost — without this guard the report claimed simultaneously that N tasks
# were still enabled AND that the same N had just been disabled.
lost = [i for i in dst_was_enabled if i in src_set and i not in src_was_enabled] if write else []

print(f"    added={len(added)}  updated={len(updated)}  kept(account-only)={len(kept)}  "
      f"dropped={len(dropped)}  total now={len(final)}")
if still_enabled:
    print(f"    note: {len(still_enabled)} task(s) are still ENABLED — account-only ids, never touched")
if lost:
    print(f"    NOTE: {len(lost)} task(s) were RUNNING in the account and are now DISABLED")
    print(f"          (same id on the gateway side, so the gateway's definition replaced them).")
    print(f"          The list is in target-was-enabled-{stamp}.txt")


def block(title, ids):
    return f"{title} ({len(ids)}):\n" + "\n".join("  " + i for i in ids) + "\n"


with open(os.path.join(out_root, f"source-enabled-tasks-{stamp}.txt"), "w") as f:
    f.write("# Tasks that were ENABLED in the SOURCE (the gateway deployment).\n"
            "# Apply with:  bash scripts/restore-enabled.sh --from <this file>\n"
            "# (the '#' header is skipped by the parser; every other line is one task id)\n"
            + "\n".join(src_was_enabled) + "\n")

with open(os.path.join(out_root, f"target-was-enabled-{stamp}.txt"), "w") as f:
    f.write("# Tasks that were ENABLED in the TARGET (the account) BEFORE this restore.\n"
            "# Any of these whose id also exists on the gateway side was switched off by the\n"
            "# import: a colliding id takes the gateway's definition, and it is imported\n"
            "# disabled. If you want them running again, apply this file deliberately:\n"
            "#     bash scripts/restore-enabled.sh --from <this file>\n"
            "# ...and check the model id first, because the definition is now the gateway's.\n"
            + "\n".join(dst_was_enabled) + "\n")

with open(os.path.join(out_root, f"task-merge-report-{stamp}.txt"), "w") as f:
    f.write(block("added from the gateway", added)
            + "\n" + block("updated from the gateway (the account had the same id)", updated)
            + "\n" + block("kept — existed only in the account", kept)
            + "\n" + block("dropped (TASK_MODE=replace only)", dropped)
            + "\n" + block("still ENABLED after this run", still_enabled)
            + "\n" + block("WAS running in the account, now DISABLED "
                           "(the gateway's definition replaced it)", lost))

sys.exit(0)
PY
RC=$?
set -e
[ "${RC}" -eq 0 ] || die "task validation failed. Nothing was written. Roll back with: bash rollback.sh"
echo "    enabled in the gateway     -> source-enabled-tasks-${STAMP}.txt"
echo "    enabled in the account was -> target-was-enabled-${STAMP}.txt"
echo "    what changed               -> task-merge-report-${STAMP}.txt   (read this first)"

# ------------------------------------------------------------- cowork
if [ "${MIGRATE_COWORK:-0}" = "1" ]; then
  echo "--- Cowork"
  touch "$MAN_C"; n=0
  CL="$(find "${COW_SRC}" -maxdepth 1 -name 'local_*.json' -exec basename {} \; 2>/dev/null || true)"
  for b in ${CL}; do
    stem="${b%.json}"
    if [ -f "${COW_DST}/${b}" ]; then
      if ! cmp -s "${COW_SRC}/${b}" "${COW_DST}/${b}"; then
        echo "    NOTE: ${b} exists on both sides and differs; the target's copy was kept."
      fi
      continue
    fi
    cp -c "${COW_SRC}/${b}" "${COW_DST}/${b}" 2>/dev/null || cp "${COW_SRC}/${b}" "${COW_DST}/${b}"
    echo "${COW_DST}/${b}" >> "$MAN_C"
    # Only record the workspace directory if we actually created it. It used to be appended
    # unconditionally — even when the previous line decided the directory already existed — so
    # rollback would delete a directory the restore never touched. On a real machine there is a
    # session whose source, but not target, carries a workspace, so this path does get taken.
    if [ -d "${COW_SRC}/${stem}" ]; then
      if [ ! -e "${COW_DST}/${stem}" ]; then
        cp -Rc "${COW_SRC}/${stem}" "${COW_DST}/${stem}" 2>/dev/null || cp -R "${COW_SRC}/${stem}" "${COW_DST}/${stem}"
        echo "${COW_DST}/${stem}" >> "$MAN_C"
      else
        echo "    NOTE: ${stem}/ exists on both sides; the target's workspace was kept (not merged)."
      fi
    fi
    n=$((n+1))
  done
  for e in spaces spaces.json; do
    [ -e "${COW_SRC}/${e}" ] || continue
    if [ ! -e "${COW_DST}/${e}" ]; then
      cp -Rc "${COW_SRC}/${e}" "${COW_DST}/${e}" 2>/dev/null || cp -R "${COW_SRC}/${e}" "${COW_DST}/${e}"
      echo "${COW_DST}/${e}" >> "$MAN_C"
    elif [ -f "${COW_SRC}/${e}" ] && ! cmp -s "${COW_SRC}/${e}" "${COW_DST}/${e}"; then
      echo "    NOTE: ${e} exists on both sides and differs; the gateway's copy was NOT merged."
      echo "          Copy it by hand if you need it: ${COW_SRC}/${e}  ->  ${COW_DST}/${e}"
    elif [ -d "${COW_SRC}/${e}" ] && ! diff -rq "${COW_SRC}/${e}" "${COW_DST}/${e}" >/dev/null 2>&1; then
      echo "    NOTE: ${e}/ exists on both sides and differs; the gateway's copy was NOT merged."
      echo "          Source: ${COW_SRC}/${e}"
    fi
  done
  echo "    copied ${n} Cowork sessions"
  echo "    note: only local_* sessions and spaces/spaces.json are handled. Anything else in the"
  echo "          Cowork partition (memory/, usage-ledger/, workspace dirs, settings) is NOT copied."
fi

echo
echo "=== done. Reopen Claude Desktop and verify in the UI:"
echo "    - sessions visible; a transcript opens with full history"
echo "    - routines listed; the merged set matches task-merge-report-*.txt"
echo "    - Cowork chats present"
echo
echo "    Before enabling anything, run:  bash \"$HERE/check-gateway.sh\""
echo "    Then restore the enabled set — IN BATCHES:"
echo "      bash \"$HERE/restore-enabled.sh\" --dry-run"
echo "      bash \"$HERE/restore-enabled.sh\" --limit 5"
echo "      bash \"$HERE/restore-enabled.sh\""
echo "    Full checklist: docs/06-verification.md"
