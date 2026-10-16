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
LOG="$ROOT/restore-$MODE-$STAMP.log"
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
TASK_SRC_N="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['scheduledTasks']))" "${TASK_SRC}")"
TASK_DST_N="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['scheduledTasks']))" "${TASK_DST}")"
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
if pgrep -f "Applications/Claude.app" >/dev/null 2>&1; then
  LIVE=0
  for p in $(pgrep -f "Applications/Claude.app" 2>/dev/null || true); do
    cmd="$(ps -o command= -p "$p" 2>/dev/null || true)"
    [ -n "$cmd" ] || continue
    case "$cmd" in
      *chrome-native-host*)       continue ;;  # started by Chrome, holds no Claude data
      *chrome_crashpad_handler*)  continue ;;  # crash reporter
    esac
    LIVE=$((LIVE+1))
  done
  [ "${LIVE}" -eq 0 ] || die "Claude Desktop is still running (${LIVE} processes). Quit it with ⌘Q and retry."
fi
echo "OK Claude is not running"

# ------------------------------------------------------------- backup
if [ -f "$ROOT/.backup-done" ]; then
  BK="$(cat "$ROOT/.backup-done")"
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

for b in ${LIST}; do
  if [ -e "${CODE_DST}/${b}" ]; then SKIPPED=$((SKIPPED+1)); continue; fi
  if cp -p "${CODE_SRC}/${b}" "${CODE_DST}/${b}"; then
    echo "${CODE_DST}/${b}" >> "$MAN_S"; COPIED=$((COPIED+1))
  else
    FAILED=$((FAILED+1))
  fi
done
echo "    copied=${COPIED} skipped=${SKIPPED} failed=${FAILED}"
[ "${FAILED}" -eq 0 ] || die "some copies failed; do not continue"
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

# bring along archive/backlog state if present and not already there
for extra in archived-sessions.idx backlog; do
  if [ -e "${CODE_SRC}/${extra}" ] && [ ! -e "${CODE_DST}/${extra}" ]; then
    cp -Rp "${CODE_SRC}/${extra}" "${CODE_DST}/${extra}"
    echo "    carried over ${extra}"
  fi
done

# ------------------------------------------------------------- tasks
echo "--- scheduled tasks (mode=${TASK_MODE}, imported DISABLED)"
cp -p "${TASK_DST}" "${TASK_DST}.pre-import-backup-${STAMP}"
cp -p "${TASK_SRC}" "$ROOT/source-tasks-${STAMP}.json"

set +e
python3 - "${TASK_SRC}" "${TASK_DST}" "$ROOT/source-enabled-tasks-${STAMP}.txt" "${TASK_MODE}" "$ROOT/task-merge-report-${STAMP}.txt" <<'PY'
import copy, datetime, json, os, sys

src_path, dst_path, enabled_report, mode, merge_report = sys.argv[1:6]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

src_tasks = json.load(open(src_path))["scheduledTasks"]
dst_doc = json.load(open(dst_path))
dst_tasks = dst_doc.get("scheduledTasks", [])
src_ids = [x["id"] for x in src_tasks]
src_was_enabled = [x["id"] for x in src_tasks if x.get("enabled")]


def stamp(task):
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
    out, added, updated, kept, dropped = dst_doc, [], [], [x["id"] for x in dst_tasks], []
elif mode == "replace":
    dropped = [x["id"] for x in dst_tasks]
    out = copy.deepcopy(dst_doc)
    out["scheduledTasks"] = [stamp(x) for x in src_tasks]
    added, updated, kept = src_ids, [], []
else:  # merge
    src_set = set(src_ids)
    index = {x["id"]: i for i, x in enumerate(dst_tasks) if "id" in x}
    merged = copy.deepcopy(dst_tasks)
    added, updated = [], []
    for x in src_tasks:
        if x["id"] in index:
            merged[index[x["id"]]] = stamp(x)
            updated.append(x["id"])
        else:
            merged.append(stamp(x))
            added.append(x["id"])
    kept = [x["id"] for x in dst_tasks if x.get("id") not in src_set]
    dropped = []
    out = copy.deepcopy(dst_doc)
    out["scheduledTasks"] = merged
    # Deliberately NOT touching out["recordedSkips"]: the target is a live account with its
    # own routines, and clearing its skip ledger could make those replay missed windows.

tmp = dst_path + ".tmp"
json.dump(out, open(tmp, "w"), ensure_ascii=False, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, dst_path)

final = json.load(open(dst_path))["scheduledTasks"]
still_enabled = [x["id"] for x in final if x.get("enabled")]
imported = set(src_ids) if mode != "skip" else set()
bad = [i for i in still_enabled if i in imported]

print(f"    added={len(added)}  updated={len(updated)}  kept(target-only)={len(kept)}  "
      f"dropped={len(dropped)}  total now={len(final)}")
if still_enabled:
    print(f"    note: {len(still_enabled)} task(s) are ENABLED — those were the account's own, left alone")

def block(title, ids):
    return f"{title} ({len(ids)}):\n" + "\n".join("  " + i for i in ids) + "\n"

open(merge_report, "w").write(
    block("added from the gateway", added)
    + "\n" + block("updated from the gateway (target had the same id)", updated)
    + "\n" + block("kept, existed only in the account", kept)
    + "\n" + block("dropped (TASK_MODE=replace only)", dropped)
    + "\n" + block("left ENABLED after this run", still_enabled)
)
open(enabled_report, "w").write(
    "Tasks that were ENABLED in the SOURCE (the gateway deployment). Restore exactly this set, "
    "in batches, and only after the user confirms:\n" + "\n".join(src_was_enabled) + "\n")

sys.exit(0 if not bad else 1)
PY
RC=$?
set -e
[ "${RC}" -eq 0 ] || die "task import verification failed. Roll back with: bash rollback.sh"
echo "    enabled list   -> source-enabled-tasks-${STAMP}.txt"
echo "    what changed   -> task-merge-report-${STAMP}.txt   (read this before enabling anything)"

# ------------------------------------------------------------- cowork
if [ "${MIGRATE_COWORK:-0}" = "1" ]; then
  echo "--- Cowork"
  touch "$MAN_C"; n=0
  CL="$(find "${COW_SRC}" -maxdepth 1 -name 'local_*.json' -exec basename {} \;)"
  for b in ${CL}; do
    stem="${b%.json}"
    [ -f "${COW_DST}/${b}" ] && continue
    cp -c "${COW_SRC}/${b}" "${COW_DST}/${b}" 2>/dev/null || cp "${COW_SRC}/${b}" "${COW_DST}/${b}"
    if [ -d "${COW_SRC}/${stem}" ] && [ ! -d "${COW_DST}/${stem}" ]; then
      cp -Rc "${COW_SRC}/${stem}" "${COW_DST}/${stem}" 2>/dev/null || cp -R "${COW_SRC}/${stem}" "${COW_DST}/${stem}"
    fi
    echo "${COW_DST}/${b}" >> "$MAN_C"; echo "${COW_DST}/${stem}" >> "$MAN_C"
    n=$((n+1))
  done
  for e in spaces spaces.json; do
    if [ -e "${COW_SRC}/${e}" ] && [ ! -e "${COW_DST}/${e}" ]; then
      cp -Rc "${COW_SRC}/${e}" "${COW_DST}/${e}" 2>/dev/null || cp -R "${COW_SRC}/${e}" "${COW_DST}/${e}"
      echo "${COW_DST}/${e}" >> "$MAN_C"
    fi
  done
  echo "    copied ${n} Cowork sessions"
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
