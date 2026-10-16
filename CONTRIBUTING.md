# Contributing

The most valuable contribution here is **a problem this kit doesn't warn about yet**.

## The one rule

**Every problem found during a restore gets written down, in the right document — including
the ones that turn out not to be the restore's fault.**

Restores fail expensively in two ways:

1. something breaks and nobody warned you, and
2. something breaks, you blame the restore, and you "fix" the wrong thing.

A finding goes in **one of three places**, and saying which is part of the fix:

| Finding | Goes in |
|---|---|
| Specific to coming **back** from a gateway (merge semantics, gateway residue, browser swap) | `docs/05-pitfalls.md`, first section |
| Applies to **any** account/deployment change | `docs/05-pitfalls.md`, "shared" section — or the [sibling kit](https://github.com/zhangwenhao66/claude-migration-kit) if it bites in both directions |
| It changes **what you should check** | `docs/06-verification.md` |

If you are unsure which, file it and say so — deciding is part of the work.

## What makes a good entry

- **The symptom, verbatim.** The exact error text is what the next person will search for.
- **Why it is not obvious.** Intermittent? Did a config look correct while the behaviour was
  wrong? Did it look like a different problem? Several entries here exist precisely because a
  check *looked* like it passed while it was actually checking nothing.
- **The fix, and whether it is permanent.** If it needs re-applying after an upgrade, say so.
- **What you verified, and what you did not.** "Files are present" is not "it works".

## Code

- `scripts/` is plain `bash`, macOS-oriented, `set -euo pipefail`.
- Copy-only, never move or delete anything in a user's data directory.
- Any script that writes into the app's data directory must refuse to run while Claude Desktop
  is running.
- Run `bash -n` on changed scripts before committing.
- The task merge is the part most likely to damage someone's setup. If you change it, test all
  three `TASK_MODE` values against synthetic `scheduled-tasks.json` files first, and paste the
  result in the PR.

## Do not include

Account UUIDs, email addresses, gateway URLs, API tokens or keys, personal paths, or real
site/task names. Redact them in issues and in documentation examples alike.
