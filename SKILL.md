---
name: claude-account-restore
description: >
  Move a complete Claude Desktop environment back from a third-party gateway ("3p")
  deployment into a normal, logged-in Anthropic account — without losing the sessions,
  scheduled tasks/routines, Cowork chats or memory accumulated while on the gateway.

  Use this skill when the user says any of: "I'm back on my Claude account but my sessions
  are gone", "migrate my gateway-mode Claude back", "I used CC Switch and now want to go back
  to Claude Official", "restore my routines from the 3p deployment", "the sidebar is empty
  after I logged back in", "I stopped using my own API key and went back to my account".
---

# Bringing Claude Desktop back from a gateway deployment

You are helping a user move their **entire** Claude Desktop environment out of a third-party
gateway ("3p") deployment and back into a normal, logged-in Anthropic account. The user's fear
is "everything from the last few months is gone". Usually **nothing is gone** — the App is
simply reading a different folder than the one the gateway deployment used.

This is the reverse of the `claude-migration-kit` skill. Read `docs/01-data-layout.md` for the
full picture; the short version:

- **Conversation transcripts** live in `~/.claude/projects/` and are **not** account-scoped.
- **Session list metadata** lives in `<app-data>/claude-code-sessions/<accountUUID>/<orgUUID>/`
  and **is** account-scoped. `<app-data>` is `.../Claude-3p` in gateway mode, `.../Claude`
  otherwise. Copying `local_*.json` into the account partition makes sessions reappear.
- **Skills, memory, `CLAUDE.md`** are **not** account-scoped — nothing to migrate.
- **Scheduled tasks** live in `scheduled-tasks.json` inside the partition.
- **Cowork** lives in a parallel partition; in gateway mode its directory names are
  **truncated to 8 characters**, while the account side uses full uuids.

## What is different from migrating the other way

Do not treat this as the outbound migration run in reverse. Two things genuinely differ, and
both cause silent failures.

1. **The target is a live account, not a fresh partition.** It may already hold its own sessions
   and its own routines. The outbound scripts refuse to import when the target has tasks; that
   would be wrong here. Tasks are **merged by id**.
   **Task ids are slugs (`daily-backlink-building`), not uuids**, so if both deployments run the
   same task set every id collides — that is the normal case. For a colliding id the gateway's
   definition wins and the task is imported **disabled**, which means an account-side routine
   that was running stops. Only ids that exist *solely* in the account are left untouched.
2. **The machine is still pointed at the gateway.** Logging out does not remove
   `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` from the shell profiles. Every new terminal and
   every routine keeps calling the gateway, and **nothing errors**. This must be checked before
   anything is enabled.

## Rules you must follow

These mirror the safety design of the scripts in `scripts/`. Do not skip them.

1. **Leave the gateway first, restore second.** If the app is still launching with
   `--user-data-dir=.../Claude-3p`, nothing you copy will appear, and the user will think the
   restore failed. Confirm the live directory with
   `ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*'`.
2. **Copy only. Never move, never delete.** The gateway partition stays byte-for-byte intact —
   it is the source of everything, and the fallback.
3. **Back up first, and verify the backup** (file counts must match). A backup you did not
   verify is not a backup.
4. **Import scheduled tasks with `enabled = false`, and stamp `lastScheduledFor` /
   `missedRunScanFloor` to the import time.** Claude Desktop replays missed windows; some tasks
   publish, post, or send email. That replay is irreversible.
5. **Never enable a task the user had disabled, in either deployment.** Two lists matter, and
   both are read **before** anything is written:
   - the *source* (gateway) partition's `scheduledTasks[].enabled` — written to
     `source-enabled-tasks-<stamp>.txt`;
   - the *target* (account) partition's `scheduledTasks[].enabled` — written to
     `target-was-enabled-<stamp>.txt`. This one is not optional here: because ids are slugs,
     colliding ids get imported disabled, and without this list there is no record of which of
     the account's own routines were running.
   A migration that forces everything to `false` and then restores from its own guess destroys
   both.
6. **Do not clear the target's `recordedSkips`.** For an empty target that is fine (the outbound
   kit does it); here it can make the account's *own* tasks replay missed windows.
7. **The App must be fully quit** before touching its data directory. The scripts check and
   refuse otherwise.
8. **Never claim success from files being present.** Verify in the UI.

## Procedure

> **Where the scripts live.** Everything below refers to `scripts/…` **relative to the
> claude-restore-kit repository**, not to this skill's own folder. If this skill was installed
> by copying only `SKILL.md` into `~/.claude/skills/`, ask the user for the path to the cloned
> repo and run the scripts from there. Verify with `ls <repo>/scripts/`.

### Step 0 — Reconnaissance (read-only, safe while Claude runs)

1. `bash scripts/find-partitions.sh` — enumerates both app data directories, which one the
   running app uses, every partition, its session count, and its enabled task ids.
2. Establish which side is which: **source** is the `Claude-3p` partition holding the work;
   **target** is the `Claude` partition for the account now signed in. This is the mirror image
   of the outbound kit.
3. **Record the source enabled-task list** and save it to a file. Do not keep it only in
   context.

### Step 1 — Configure

Copy `scripts/config.example.sh` to `scripts/config.sh`. Note the asymmetry: `SRC_*` is the
gateway side (truncated Cowork names), `DST_*` is the account side (full uuids). Read the real
names with `ls`; never construct them. Then choose `TASK_MODE` (`merge` is the default and
almost always correct).

### Step 2 — Leave the gateway

Read `docs/03-leaving-gateway.md` and walk the user through it:

- switch the provider back to the official one **and stop any routing service**,
- remove `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` from the shell profiles,
- confirm the app is on the plain `Claude` directory,
- complete the sign-in.

Then run `bash scripts/check-gateway.sh` and report each item as passed / failed / not checked.

### Step 3 — Restore

```bash
bash scripts/restore.sh check   # read-only preflight
# quit Claude Desktop completely (⌘Q), then:
bash scripts/restore.sh test    # 20 most recent sessions, so the user can verify the mechanism
bash scripts/restore.sh all     # remaining sessions + tasks (merged, disabled) + Cowork
```

`test` exists because "does the App accept foreign session files?" cannot be proven from disk.
After `test`, ask the user to reopen Claude and confirm sessions appear and a transcript opens.
Only then run `all`.

After `all`, read `task-merge-report-*.txt` and tell the user explicitly: what was added, what
was updated, what was kept (account-only), **what is enabled right now**, and — most important —
**which account routines this import switched off**. That last list is the one a user will be
angry to discover later, so say it out loud rather than letting them find it in a file.

### Step 4 — Verify (do not skip)

Ask the user to confirm, in the UI: sessions appear (note: **archived** and **routine-spawned**
sessions legitimately do not appear in the folder list — explain this before they panic),
opening one shows the full history, the routine count matches, Cowork is back.

Two lists were saved, and they answer different questions: `source-enabled-tasks-<stamp>.txt` is
what was running on the gateway (the usual case), and `target-was-enabled-<stamp>.txt` is what was
running in the account before the import, if the merge switched any of it off. Tell the user which
one you are applying, and read `task-merge-report-*.txt` before either.

Then re-enable **from the saved list**, in batches:

```bash
bash scripts/restore-enabled.sh --dry-run
bash scripts/restore-enabled.sh --limit 5     # watch one actually run
bash scripts/restore-enabled.sh               # the rest
```

Staging matters because a broken dependency (auth, browser bridge, model id, quota) shows up as
many failures at once if you enable everything together, and you lose the signal. `--limit N`
takes the first N of the source list, which is deliberately neutral: do **not** reorder by task
name to put "safe-looking" tasks first.

### Step 5 — Model ids

Routines written during gateway mode may name models the account does not expose
(`deepseek-v4.1-flash` and similar). These fail **at run time**, not at import time. Scan the
model field of every task before enabling it, and fix them.

### Step 6 — Browser

Read `docs/04-browser.md`. On a paid account the official extension works again; if the user
switches back to it, the free `mcp-chrome-bridge` must be **removed**, because two browser MCP
servers means the agent may call the raw one and every default is bypassed.

## If something goes wrong

`bash scripts/rollback.sh` deletes exactly the files the restore copied (from its manifests) and
restores the task file from the pre-import backup. It never touches the source partition. Because
the restore is copy-only, rollback is always available.

## Reporting

Report per item as **passed / failed / not checked**. "Files are present" is not "it works". A
config check is not a connection check. Say what you actually verified and how, and say what you
did not.
