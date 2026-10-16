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
