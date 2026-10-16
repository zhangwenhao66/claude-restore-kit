# 05 — What actually goes wrong

The outbound kit's pitfalls are at
[`claude-migration-kit/docs/04-pitfalls.md`](https://github.com/zhangwenhao66/claude-migration-kit/blob/main/docs/04-pitfalls.md).
This file repeats only the ones that also bite on the way back, and adds the ones that are
specific to coming home.

---

## Specific to restoring into a real account

### "The restore finished, but the sidebar is still empty"

**Almost always:** the app is still running in gateway mode, so it is reading `Claude-3p` while
you wrote into `Claude`. Nothing you restored can appear.

```bash
ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*'
```

Must end in `Application Support/Claude`. If it says `Claude-3p`, stop and finish
`docs/03-leaving-gateway.md` — do not start re-copying files, and do not start rolling back.
The files are fine; the app is looking somewhere else.

### The gateway is still in your environment

A logout does not clear `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` from your shell profiles.
Every new terminal and every scheduled task inherits them, so Claude Code keeps calling the
gateway while you believe you are on your account. **Nothing errors.**

```bash
bash scripts/check-gateway.sh
```

Run it before enabling anything. On the machine this kit was written on, the gateway URL was
still sitting in a config file weeks after the switch.

### Same-named sessions are the normal case, not an edge case

On the machine this kit was written on, **all 2847** of the account's sessions also existed in the
gateway partition; 33 differed and the gateway's copy was the newer one (median 11 days). An
earlier version skipped any same-named file and said nothing but `skipped=33` — a silent loss of
the newer state of 33 conversations.

Now the rule is per file, and it is in `docs/02-restore.md` step 4: identical → leave alone;
gateway newer → replace, parking the account's copy in `replaced-sessions/`; account newer or
unparseable → keep the account's and write it to `conflicts-<stamp>.txt`. **If neither list is
empty, read it before you conclude the restore is done.**

### Cowork is copied only partially — do not read "Cowork ✅" as "everything"

`restore.sh` copies `local_*` sessions and `spaces`/`spaces.json`. It does **not** copy anything
else in the Cowork partition: `memory/`, `usage-ledger/`, workspace directories, or
`cowork_account_settings.json`. On a real machine those existed only on the gateway side, so they
simply do not come across.

Worse, if `spaces.json` already exists on the account side it is **not merged**, even when the two
differ. The script now says so out loud rather than reporting success —— copy it by hand if you
need it.

### `--only` used to enable nothing and exit 0

The old `--only a,b,c` intersected the selection with the source's enabled list before applying
it, so any id that was not in that list — which is every id you would need after a merge — was
filtered out. It printed `will enable: 0` and exited 0, under a header that read *"enable exactly
these task ids"*.

`--only` now means exactly what it says. The related trap is the default: with no arguments the
script reads `source-enabled-tasks-*.txt`, which after a merge of two identical task sets is
**empty** (nothing was running on the gateway). Pass `--from target-was-enabled-<stamp>.txt` to
get the account's own routines back.

### `TASK_MODE=skip` on the command line used to be ignored

`config.sh` assigned `TASK_MODE="merge"` unconditionally, so `TASK_MODE=skip bash restore.sh all`
silently ran a merge. The example config now uses `${TASK_MODE:-merge}`. If you copied an older
`config.sh`, fix that line.

### "Claude is still running" when it is not

The app guard matched on the **full command line**, which meant two false positives: Squirrel's
auto-updater (`.../Squirrel.framework/Resources/ShipIt`) counts as part of the bundle and can
outlive a ⌘Q, and any process whose *arguments* merely contain `Applications/Claude.app` — a shell
running `ps aux | grep Applications/Claude.app` matches itself. The guard now matches the
executable path (`ps -o comm=`) and names ShipIt explicitly. See `scripts/lib-appguard.sh`.

### A task with an unknown model id

Routines written during gateway mode may name models the real account does not expose
(`deepseek-v4.1-flash`, `doubao-seed-2.1-lite`, …). These fail **at run time**, not at import
time, so nothing warns you until a task fires and dies. Scan the model field of every task you
are about to re-enable.

### `TASK_MODE=replace` on an account that was not empty

`replace` throws away the account's own routines and, with them, the record of which of them
were enabled. That record is the only thing that tells you what the user actually wanted
running. Merge unless the account genuinely has nothing.

### Clearing `recordedSkips` during a merge

`restore.sh` deliberately leaves the account's `recordedSkips` ledger alone. Zeroing it — which
is what the outbound kit does, correctly, for an empty target — can make the account's **own**
tasks replay windows they already missed. A restore that was supposed to be about the gateway's
tasks would then also set the account's tasks running.

### Two browser channels

Coming back, you may re-pair the official extension while the free bridge is still registered.
With two browser MCP servers, the agent may call the raw one and every default is bypassed.
Keep exactly one. `scripts/check-gateway.sh` flags this.

### Cowork directory names, reversed

In gateway mode the Cowork partition uses **truncated 8-character** directory names; the account
side uses full uuids. That is the same asymmetry as the outbound kit, with source and target
swapped — it is the single most common config mistake in this kit. Read the real names with
`ls`, never construct them.

### Restoring the transcripts "just in case"

They do not need restoring. `~/.claude/projects/` was never account-scoped; the text of every
conversation has been on disk the whole time. Copying it again only creates duplicates.

### Going back and forth repeatedly

Every switch leaves a second copy of your session metadata that then keeps drifting. Pick a
home, restore once, and keep the other directory as a read-only archive. If you find yourself
migrating monthly, that is the signal to decide rather than to script.

---

## Shared with the outbound kit

### A backup you did not verify is not a backup

`restore.sh` compares file counts between the source and the backup and refuses to write
anything if they differ. Do not "save time" by skipping it — a partial backup of a 26 GB
partition looks exactly like a good one until you need it.

### Scheduled tasks must be imported disabled, with the missed-run window stamped

Claude Desktop replays windows a task missed while stopped. Some tasks publish, post or send
email. `restore.sh` stamps `lastScheduledFor` and `missedRunScanFloor` on every task it imports;
that is why every imported task arrives `enabled: false`. Do not hand-edit a task to `enabled:
true` before this has happened.

### Never enable a task the user had disabled

The authoritative "what was paused" list is the **source** partition's
`scheduledTasks[].enabled` — captured before the import, by `find-partitions.sh` and again by
`restore.sh`. A migration that forces everything to `false` and then restores from its own
guess destroys that information. Restore exactly the saved set.

### The app must be fully quit

It caches scheduling state in memory and writes it back on exit, which will undo the import.
`restore.sh` and `rollback.sh` both check and refuse. They correctly ignore
`chrome-native-host` and `chrome_crashpad_handler` processes, which belong to Chrome.

### Copy only, never move

The source partition stays byte-for-byte intact. This is what makes rollback always available,
and it is why a failed restore is never a data-loss event.

### "Files are present" is not "it works"

Sessions on disk and the App rendering them are different facts. Verify in the UI:
sessions in the sidebar, a transcript that opens with full history, the routine count, Cowork
present. Say what you checked and what you did not.
