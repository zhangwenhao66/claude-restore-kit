# 01 — Where Claude Desktop keeps things, and why it looks empty

Every migration question in this kit comes back to one table.

| Layer | Location | Scoped by account? |
|---|---|---|
| **Conversation transcripts** (the real content) | `~/.claude/projects/<path-encoded>/<sessionId>.jsonl` | **No** — only by working directory |
| **Session list metadata** (titles, pointers) | `<app-data>/claude-code-sessions/<accountUUID>/<orgUUID>/local_*.json` | **Yes** |
| **Scheduled tasks / routines** | same directory, `scheduled-tasks.json` | **Yes** |
| **Cowork sessions** | `<app-data>/local-agent-mode-sessions/<acc8>/<org8>/` | **Yes** |
| **Skills, memory, `CLAUDE.md`** | `~/.claude/` | **No** |
| **Project files** | wherever you keep them | **No** |

`<app-data>` is:

- `~/Library/Application Support/Claude` for a normal logged-in account,
- `~/Library/Application Support/Claude-3p` for a third-party / gateway ("3p") deployment.

## The illusion

The app builds its sidebar by scanning the folder belonging to the account it is signed into.
Switch deployments and that folder is a different one — empty, or containing only what the new
deployment has produced. So the sidebar looks wiped, and **gigabytes of transcripts sit
untouched**.

The session metadata JSON has **no account fields at all**. There is no database to patch and no
export format to convert: copy `local_*.json` files from the gateway partition into the account
partition and the sessions reappear.

## Which direction you are going

Both kits operate on the same table; only which side is the source changes.

| | Source | Target | Kit |
|---|---|---|---|
| Left a banned/replaced account | `Claude/<old account>` | `Claude-3p/<gateway>` | [`claude-migration-kit`](https://github.com/zhangwenhao66/claude-migration-kit) |
| Came back to a real account | `Claude-3p/<gateway>` | `Claude/<account>` | **this repo** |

## Two asymmetries worth memorising

1. **Cowork directory names.** In gateway mode they are **truncated to 8 characters**
   (`a1b2c3d4/00000000`); in account mode they are full uuids. Read them with `ls`; never build
   them by string-slicing.
2. **The account/org uuids are synthetic on the gateway side.** There is no real account, so the
   partition path uses a generated account uuid and a placeholder organisation such as
   `00000000-0000-4000-8000-000000000001`. Do not assume they mean anything.

## Confirm which directory is live, rather than assuming

```bash
ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*'
```

This one command resolves the most common "the restore didn't work" report, in either direction.
