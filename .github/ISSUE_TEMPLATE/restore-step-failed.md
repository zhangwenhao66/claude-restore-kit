---
name: A step in the restore failed
about: Something in docs/02-restore.md or a script did not do what it says
title: "[restore] "
labels: ["bug", "needs-triage"]
---

<!--
Please redact account UUIDs, gateway URLs, API tokens and personal paths before posting.
-->

## Which step

<!-- e.g. "restore.sh check", "step 3 TASK_MODE=merge", "check-gateway.sh item 2" -->

## What you expected

## What happened

```
paste the exact output / error here
```

## Environment

- macOS version:
- Claude Desktop version:
- Gateway side: `Claude-3p` present? <!-- yes/no -->
- Which account is the app currently signed into? <!-- account mode / still gateway -->
- `ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*'` output:

## Current state — this matters

- [ ] Claude Desktop is quit
- [ ] No restore has run yet
- [ ] `restore.sh test` has run, `restore.sh all` has not
- [ ] `restore.sh all` has run
- [ ] I have run `rollback.sh`

## Checklist

- [ ] I removed account UUIDs, gateway URLs, tokens and personal paths
- [ ] I ran `bash scripts/check-gateway.sh` and it reported no PROBLEM items
