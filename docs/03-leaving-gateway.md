# 03 — Leaving the gateway

The outbound kit's problem was "I got banned, how do I keep working". This kit's problem is
the reverse, and it has one step the outbound direction never had:

**Getting back into a real account is not just logging in.** A gateway deployment leaves
residue on the machine, and that residue keeps pointing Claude at the gateway even after you
sign in with an Anthropic account. Restoring your files first and enabling routines second is
the wrong order — `scripts/check-gateway.sh` exists so you find the residue before anything
starts running.

## What "gateway mode" actually changed

Three separate things, and they have to be undone separately.

1. **The app data directory.** The app launches with `--user-data-dir=.../Claude-3p` instead of
   `.../Claude`. Everything in `docs/01-data-layout.md` is now relative to `Claude-3p`.
2. **The API endpoint.** Requests went to the gateway's URL, not Anthropic's. Usually injected
   as `ANTHROPIC_BASE_URL` (+ `ANTHROPIC_AUTH_TOKEN`) in your shell profiles, or held by the
   gateway app itself.
3. **The login.** There is no Anthropic account in the loop at all — that is the whole point of
   the mode, and also why nothing can be banned.

## Step 1 — stop routing, then log back in

If you used [CC Switch](https://github.com/farion1231/cc-switch) or a similar switcher:

1. Open it, select the **official** provider for Claude Desktop (CC Switch ships one, usually
   named *Claude Official* / *官方*).
2. **Stop routing.** A switcher can run a local proxy ("Routing service: Running"). If it was
   on, turn it off — "back to direct" in CC Switch's own wording. Leaving it running means your
   next login still talks to the proxy.
3. Quit Claude Desktop completely (⌘Q), then reopen it and go through the normal
   sign-in / OAuth flow.

Do **not** delete the `Claude-3p` directory at any point in this process. It is the source of
everything you are about to restore, and there is no second copy.

## Step 2 — hunt the environment variables

This is the one that quietly breaks everything. A gateway is often injected like this:

```sh
export ANTHROPIC_BASE_URL="https://your-gateway.example.com/api"
export ANTHROPIC_AUTH_TOKEN="sk-..."
```

Those lines survive a logout. Every new terminal, every scheduled task, inherits them, and
Claude Code happily keeps calling the gateway while you believe you are on your account.

```bash
bash scripts/check-gateway.sh
```

It looks in `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`, `~/.profile`,
`~/.bashrc`, and in the live environment, and reports OK / PROBLEM / NOT CHECKED per item.
It changes nothing — remove the lines yourself once you have seen them.

Also grep anywhere else you may have put them:

```bash
grep -rl "ANTHROPIC_BASE_URL\|ANTHROPIC_AUTH_TOKEN" \
  ~/.zsh* ~/.bash* ~/.config 2>/dev/null
```

> **Why the check is not optional:** on the machine this kit was written on, the gateway URL
> was still sitting in a config file weeks after the switch, pointing at a third-party relay.
> Nothing errored. It just silently kept using the relay.

## Step 3 — confirm the app is on the plain directory

```bash
ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*'
```

It must end in `Application Support/Claude`, not `Claude-3p`. If it still says `Claude-3p`,
the app is still in gateway mode and nothing you restore will show up — see
`docs/05-pitfalls.md`, "the restore worked but the sidebar is still empty".

## Step 4 — restore the data

Only now run `scripts/restore.sh`. See `docs/02-restore.md`.

## Step 5 — check the model catalog

Routines and settings written during gateway mode may name model ids the real account does not
expose (`deepseek-v4.1-flash` and friends). A routine with an unknown model id fails **at run
time**, not at import time, so this will not show up until a task fires.

Open the task list, scan the model field of everything you are about to re-enable, and fix
them before enabling. The outbound kit hit the mirror-image version of this problem
(the outbound kit's `docs/06-gateway-mode.md`).

## What does not need undoing

- **Skills, memory, `CLAUDE.md`, project files.** `~/.claude/` and your working directories were
  never account-scoped. They look unchanged because they are unchanged.
- **Your transcripts.** They live in `~/.claude/projects/`, also not account-scoped. The text of
  every conversation was on disk the whole time.
