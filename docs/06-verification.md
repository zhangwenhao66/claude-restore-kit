# 06 — Verification checklist

Report each line as **passed / failed / not checked**. "The files are present" is not "it
works", and a config check is not a connection check.

## Before you start

- [ ] The app is signed into a real account and the sign-in completed.
- [ ] `ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*'` ends in
      `Application Support/Claude`.
- [ ] The `Claude-3p` directory still exists, untouched, with your work in it.
- [ ] At least 60 GB free (`df -g ~`).
- [ ] You have the source enabled-task list saved somewhere outside this repo.

## Gateway residue (run `bash scripts/check-gateway.sh`)

The script exits **1** if it found any PROBLEM item, so it can be used as a gate — but it is a
report first: read the items, do not just look at the exit code.

- [ ] No `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` in `~/.zshenv`,
      `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`, `~/.profile`, `~/.bashrc`, or in the live
      environment.
- [ ] The switcher (CC Switch or equivalent) is not running, **or** is set to the official
      provider with routing stopped.
- [ ] The app's data directory is the plain `Claude` one.

## After `restore.sh test`

- [ ] Claude Desktop reopens without errors.
- [ ] The 20 test sessions appear in the sidebar.
- [ ] Opening one shows the **full** history, not just the title.
- [ ] If they do not appear: run `rollback.sh`, then re-read
      `docs/05-pitfalls.md` §"the sidebar is still empty". Do not run `restore.sh all`.

## After `restore.sh all`

- [ ] If the restore printed `replaced=`, the account's older copies are in
      `replaced-sessions/<stamp>/` — confirm they are there before you trust `rollback.sh`.
- [ ] If it printed `kept-target=`, read `conflicts-<stamp>.txt` and confirm that keeping the
      account's copy was right for each one.
- [ ] Source session count now matches the target count
      (`find <CODE_DST> -maxdepth 1 -name 'local_*.json' | wc -l`).
- [ ] The source count is **unchanged** — proof that nothing was moved.
- [ ] Routine count in the UI matches `total now=` in `task-merge-report-*.txt`.
- [ ] **Every task you imported is disabled.** Check in the UI, do not trust the script's print.
- [ ] Tasks that existed only in the account are still there, with their original enabled state.
- [ ] Anything listed under *"WAS running in the account, now DISABLED"* in
      `task-merge-report-*.txt` is a decision you have made on purpose, not something you
      discover later. `target-was-enabled-*.txt` is the full list of what the account had on.
- [ ] If any of those should be running, they were put back deliberately:
      `bash scripts/restore-enabled.sh --from target-was-enabled-<stamp>.txt --dry-run` first,
      then without `--dry-run`. Do not assume the default invocation did it — it reads the
      *gateway* list.
- [ ] `bash scripts/check-gateway.sh` exits 0 before you enable anything.
- [ ] Cowork chats are present (if `MIGRATE_COWORK=1`).
- [ ] Archived sessions and routine-spawned sessions legitimately do **not** appear in the
      folder list. Confirm the user understands this before they conclude something is missing.

## Before enabling anything

- [ ] Every task's model field names a model the account actually exposes.
- [ ] `task-merge-report-*.txt` read end to end; the "left enabled" list is what you expect.
- [ ] No task is scheduled to fire within the next few minutes.
- [ ] Browser: exactly **one** browser MCP server is registered.

## After re-enabling, in batches

- [ ] The first batch of 5 ran, and at least one task **actually completed** — not merely
      "appeared in the list".
- [ ] No burst of missed windows fired (that would mean the `lastScheduledFor` stamp did not
      take).
- [ ] Cowork still opens.
- [ ] The transcripts from gateway mode are still readable.

## Honest reporting

Write down, for the record:

- what you verified and **how**,
- what you did not verify, and why,
- anything you had to guess (model ids, uuid names, which partition was which).

A restore that reports "all good" without saying which items were never checked is not a
verification.
