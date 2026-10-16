# 04 — Browser automation after coming back

Going back to a real account changes the browser situation in a way that is easy to get wrong
in both directions.

## What changes

In gateway mode the official browser extension is unusable: it requires **signing in with an
account that has a paid plan**, and a gateway deployment has no Anthropic account at all. That
is why the outbound kit replaces it with the free [`mcp-chrome-bridge`](https://www.npmjs.com/package/mcp-chrome-bridge).

Once you are back on a real account **with a plan**, the official extension works again. So you
now have a choice, and the one thing you must not do is keep both.

## The rule: exactly one browser channel

Two browser MCP servers registered at once is worse than either one alone. The agent picks
whichever it finds, and with two servers it will often call the raw one — the one **without**
your defaults. Every fix below then stops applying: focus stealing comes back, windows start
multiplying, clicks lose their `mousemove`.

This was observed for real in the other direction: after a wrapper was installed, task runs
still showed 27 calls to the raw `chrome_javascript`, 9 to the raw `chrome_navigate` and 7 to
the raw `chrome_click_element`.

Verify by looking at **what a task actually called**, not at your config:

```bash
grep -oE 'mcp__[a-zA-Z0-9_-]+__[a-zA-Z0-9_]+' <session>.jsonl | sort | uniq -c | sort -rn | head
```

Every browser call must be under one server name.

## Option A — go back to the official extension (only with a paid plan)

1. In the app's browser/connection settings, pair the extension again. Pairing is
   **account-scoped**, so the old pairing did not survive: expect to redo it.
2. Sign in to the extension with the account that has the plan.
3. **Remove the bridge.** Delete the `mcp-chrome-bridge` MCP server entry from your Claude
   config and unload the extension. Leaving both installed is the failure described above.

> Run `bash scripts/check-gateway.sh` afterwards — it lists the registered browser MCP servers
> and flags the case where there is more than one.

## Option B — keep the bridge

Perfectly valid, and it is the only option if your account has no paid plan. The bridge drives
your own Chrome with your own logins and needs no Anthropic account, so it keeps working
regardless of which account the app is signed into.

If you keep it, apply the five fixes below — the bridge is not usable out of the box, and each
of these makes it look "broken" in a different way.

### 1. It only serves one session at a time

The bridge's HTTP server calls `getMcpServer().connect(transport)` on a **singleton** `Server`,
and an MCP `Server` can only be connected once. The second client — or any client after an
unclean disconnect — gets:

```
Streamable HTTP error: 500 {"message":"Already connected to a transport.
Call close() before connecting to a new transport, or use a separate Protocol instance per connection."}
```

**Fix:** patch `node_modules/mcp-chrome-bridge/dist/mcp/mcp-server.js` so `getMcpServer()`
returns a **new** `Server` on every call instead of caching one. See
`scripts/patch-chrome-bridge.md` — it is three lines. An `npm update` will overwrite it;
re-apply after upgrades.

### 2. One tool hangs forever

`chrome_read_page` never returns on some setups. Because it is also the source of the `ref`
values that `chrome_click_element` and `chrome_computer` accept, its failure removes the whole
ref-based workflow.

**Fix:** remove it from the tool list and short-circuit calls to it, then locate elements with
**CSS selectors** instead. `chrome_click_element` and `chrome_fill_or_select` both accept a
`selector`.

Two gotchas when you do that:

- `chrome_javascript` requires an **explicit `return`** — a bare expression yields `undefined`.
  Its result is wrapped: `{"success":true,"tabId":…,"result":"…"}`.
- `chrome_computer` with `action:"left_click"` **and a `selector`** frequently fails with
  *"Element not found"*. For selector-based clicking use `chrome_click_element`.

### 3. Every operation steals focus

By default the bridge activates the tab and brings the window forward, so the user cannot keep
using their browser while automation runs.

**Fix:** pass `background: true`. Supported by `chrome_navigate`, `chrome_computer`,
`chrome_screenshot`, `chrome_get_web_content` and `chrome_console`. Also **never call
`chrome_switch_tab`** — activating a tab is its entire job.

### 4. Clicks are trivially detectable as bots

A bare click dispatches only `mousedown, mouseup, click`. A real user always moves the mouse
first, so the absence of `mousemove` / `mouseover` is a bot fingerprint, and sites with
anti-bot defences notice.

**Fix:** **hover before clicking.** `chrome_computer` with `action:"hover"` dispatches
`mouseover, pointerenter/pointermove, mousemove`, giving the sequence

```
mouseover, pointermove, mousemove, mousedown, mouseup, click
```

Hover before filling forms too.

### 5. It opens a new window every time

`chrome_navigate` accepts `newWindow`, and also `width`/`height` — **all three create a new
window**. Automation that navigates repeatedly buries the user's desktop.

**Fix:** never pass them. Without a `tabId`, `chrome_navigate` opens a **tab in the existing
window**; with a `tabId`, it navigates that tab. Remember the tab id you were given and reuse
it.

## Two more small traps

- `chrome_navigate` prepends `www.` to hostnames, mangling IP addresses (`127.0.0.1` →
  `www.127.0.0.1`). Use `localhost` or a real domain. `file://` URLs are not supported at all.
- The extension popup must show **Service running** and a Connect control. Tools exposed but
  every call failing means the extension is not connected to the local host.

## Verify it end-to-end

Ask the user to open a new session and try:

> Use the browser tools to open `https://example.com` and read me its title.

Then check that **their active tab did not change**. That single observation proves the
background default is actually in effect — reading the config does not.
