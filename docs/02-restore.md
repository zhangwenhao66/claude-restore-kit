# 02 — The restore, step by step

> Do `docs/03-leaving-gateway.md` **first**. Restoring files into an account the app is not
> actually using looks exactly like a failed restore.

## What is actually being moved

Copying, always. The gateway partition is never modified, moved or deleted, so the whole thing
is reversible at every step.

| Item | Where it lives | Notes |
|---|---|---|
| Conversation transcripts | `~/.claude/projects/` | **not** account-scoped — already shared, nothing to copy |
| Session list metadata | `<app-data>/claude-code-sessions/<acc>/<org>/local_*.json` | **is** account-scoped — this is what makes the sidebar empty |
| Scheduled tasks | same directory, `scheduled-tasks.json` | merged, not overwritten (see below) |
| Cowork sessions | `<app-data>/local-agent-mode-sessions/<acc8>/<org8>/` | separate partition, truncated names |
| Skills / memory / `CLAUDE.md` | `~/.claude/` | not account-scoped — nothing to do |

## Step 0 — recon, read-only

```bash
bash scripts/find-partitions.sh
```

Prints both app directories, which one the running app uses, and every partition with its
session count and enabled task ids. Save that enabled-task list — it is the authoritative
"what was running" record, and `restore.sh` will write its own copy too.

**Source** is the `Claude-3p` partition holding your work. **Target** is the `Claude` partition
for the account you are logged into now. This is the mirror image of the outbound kit.

## Step 1 — configure

```bash
cp scripts/config.example.sh scripts/config.sh
$EDITOR scripts/config.sh
```

Fill in the source (gateway) and target (account) account/org uuids. Watch the Cowork block:
in gateway mode those directory names are **truncated to 8 characters**, while the account side
uses full uuids. Read the real names with `ls`, do not construct them.

Then pick `TASK_MODE`.

## Step 2 — preflight

```bash
bash scripts/restore.sh check
```

Read-only, safe while Claude is running. It refuses on: missing source or target partition,
source and target being the same, an empty source, less than 60 GB free, or Claude still
running (the app caches scheduling state in memory and writes it back on exit, which would
undo the import).

Unlike the outbound kit, a **non-empty target is expected here and is not an error** — see the
next step.

## Step 3 — the merge question

This is the substantive difference from the outbound direction. When you migrate *toward* a
gateway, the target partition is usually fresh and empty. When you migrate *back*, the target
is an account you are actively using, and it may already contain:

- sessions you created since logging in,
- its own `scheduled-tasks.json`, possibly with routines of its own,
- its own Cowork partition.

So `restore.sh` merges instead of refusing, and `TASK_MODE` decides how:

| `TASK_MODE` | Behaviour | Use when |
|---|---|---|
| `merge` (default) | ids present on both sides are updated from the gateway; ids that exist only in the account are left completely alone | almost always |
| `replace` | the account's task list is replaced by the gateway's (old file backed up to `scheduled-tasks.json.pre-import-backup-*`) | the account is brand new and has nothing of its own |
| `skip` | the account's task list is untouched; only sessions and Cowork are restored | you intend to rebuild routines by hand |

Two deliberate choices inside `merge`:

- **Every imported task comes in `enabled: false`, with `lastScheduledFor` and
  `missedRunScanFloor` stamped to now.** Without the stamp, Claude Desktop replays every window
  the task missed while it sat stopped in the other deployment. Some of those tasks publish,
  post or send email. That replay cannot be taken back.
- **The account's `recordedSkips` ledger is left alone.** Clearing it could make the account's
  *own* tasks replay missed windows — a side effect of a restore that was supposed to be about
  the gateway's tasks.

After the run, read `task-merge-report-*.txt`. It lists exactly four things: what was added,
what was updated, what was left alone, and what is enabled right now. If the "left enabled"
list is not what you expect, stop and fix it before doing anything else.

## Step 4 — copy

```bash
# quit Claude Desktop completely (⌘Q), then:
bash scripts/restore.sh test    # 20 most recent sessions — verify the mechanism
bash scripts/restore.sh all     # the rest + tasks + Cowork
```

`test` exists because "does the App accept these session files?" cannot be proven from disk.
It costs nothing to check with 20 files, and it deliberately picks the 20 most recent
**non-routine** sessions — routine-spawned sessions only appear after their task is imported,
so including them would make a working test look broken.

After `test`, reopen Claude, confirm the sessions appear and a transcript opens with full
history. Only then run `all`.

## Step 5 — check for gateway residue

```bash
bash scripts/check-gateway.sh
```

Do this **before** enabling anything. See `docs/03-leaving-gateway.md`.

## Step 6 — re-enable, in batches

```bash
bash scripts/restore-enabled.sh --dry-run
bash scripts/restore-enabled.sh --limit 5     # watch one actually run
bash scripts/restore-enabled.sh --limit 20
bash scripts/restore-enabled.sh
```

It restores the set saved in step 0/step 3 — **not** a set the script guessed. Staging matters:
a broken dependency (auth, browser bridge, model id, quota) shows up as dozens of failures at
once if you enable everything together, and then you have no signal about which one broke.

`--limit N` takes the first N of the source list, which is deliberately neutral. Do not reorder
by task name to put "safe-looking" tasks first.

## Step 7 — if something went wrong

```bash
bash scripts/rollback.sh
```

Deletes exactly the files `restore.sh` copied, from its manifests, and restores the task file
from the pre-import backup. It never touches the source partition, and it will not delete a
session you have since used. Because the restore is copy-only, rollback is always available.

## Then

`docs/06-verification.md` is the checklist. `docs/05-pitfalls.md` is what actually goes wrong.
