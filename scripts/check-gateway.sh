#!/usr/bin/env bash
# ============================================================================
# Read-only gateway residue check.
#
#   bash check-gateway.sh
#
# Restoring the data is only half the job. If the machine is still pointed at the
# gateway, Claude Desktop / Claude Code keeps talking to it no matter which account
# you logged into — and it fails in a way that looks like "the migration didn't work".
#
# This script changes nothing. It reports OK / PROBLEM / NOT CHECKED per item.
# ============================================================================
set -uo pipefail

OK=0; BAD=0; UNK=0
ok()   { printf '  [OK]        %s\n' "$*"; OK=$((OK+1)); }
bad()  { printf '  [PROBLEM]   %s\n' "$*"; BAD=$((BAD+1)); }
unk()  { printf '  [NOT CHECKED] %s\n' "$*"; UNK=$((UNK+1)); }

echo "=== Gateway residue check · $(date)"
echo

# ---------------------------------------------------------------- 1. which data dir is live
echo "1. Which Claude Desktop data directory is the app using?"
DIRS="$(ps aux 2>/dev/null | grep 'Applications/Claude.app' | grep -v grep \
        | grep -o -- '--user-data-dir=.*' | sed -E 's/--user-data-dir=//; s/ --.*//' | sort -u || true)"
if [ -z "${DIRS}" ]; then
  unk "app not running — open Claude Desktop once, then re-run"
else
  while IFS= read -r d; do
    case "$d" in
      *Claude-3p*) bad "app is using the GATEWAY data dir: $d" ;;
      *Application\ Support/Claude) ok "app is using the normal account dir: $d" ;;
      *) unk "unrecognised data dir: $d" ;;
    esac
  done <<< "${DIRS}"
fi
echo

# ---------------------------------------------------------------- 2. shell env
echo "2. Anthropic/gateway environment variables in your shell profiles"
# ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN are how a gateway is injected into Claude Code.
# If they survive, every new terminal keeps pointing at the gateway.
FOUND_ENV=0
for f in "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bashrc"; do
  [ -f "$f" ] || continue
  hits="$(grep -nE '^[[:space:]]*(export[[:space:]]+)?(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY)=' "$f" 2>/dev/null || true)"
  if [ -n "${hits}" ]; then
    FOUND_ENV=1
    bad "${f} still sets a gateway variable:"
    printf '%s\n' "${hits}" | sed 's/^/                /'
  fi
done
[ "${FOUND_ENV}" -eq 0 ] && ok "no gateway variables in the usual shell profiles"
# A value set in the live environment is invisible to the file check above.
for v in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN; do
  if [ -n "${!v:-}" ]; then
    bad "${v} is set in THIS shell — value: ${!v}"
  fi
done
echo

# ---------------------------------------------------------------- 3. CC Switch
echo "3. CC Switch"
if [ -d "/Applications/CC Switch.app" ] || [ -d "$HOME/Applications/CC Switch.app" ]; then
  ok "CC Switch is installed (that is fine — it just must not be routing to the gateway)"
  if pgrep -f "CC Switch" >/dev/null 2>&1; then
    unk "CC Switch is RUNNING — open it and confirm: provider set to the official one, and routing stopped"
  else
    ok "CC Switch is not running"
  fi
else
  ok "CC Switch not installed"
fi
echo

# ---------------------------------------------------------------- 4. MCP servers
echo "4. Browser MCP servers registered with Claude"
CFG="$HOME/.claude.json"
if [ -f "${CFG}" ]; then
  python3 - "${CFG}" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"  [NOT CHECKED] could not parse {sys.argv[1]}: {e}"); raise SystemExit
servers = d.get("mcpServers") or {}
if not servers:
    print("  [OK]        no MCP servers registered")
    raise SystemExit
browserish = [k for k in servers if any(t in k.lower() for t in
              ("chrome", "browser", "playwright", "puppeteer"))]
print(f"  [OK]        {len(servers)} MCP server(s): {', '.join(sorted(servers))}")
if len(browserish) > 1:
    print(f"  [PROBLEM]   {len(browserish)} browser MCP servers registered: {', '.join(sorted(browserish))}")
    print("              keep exactly ONE — with two, the agent may call the raw one and any")
    print("              defaults (background mode, hover-before-click) are bypassed.")
elif browserish:
    print(f"  [OK]        one browser MCP server: {browserish[0]}")
PY
else
  unk "${CFG} not found"
fi
echo

# ---------------------------------------------------------------- summary
echo "=== summary"
printf '  OK=%d  PROBLEM=%d  NOT CHECKED=%d\n' "${OK}" "${BAD}" "${UNK}"
if [ "${BAD}" -gt 0 ]; then
  echo
  echo "  Fix the PROBLEM items before you enable any routine."
  echo "  See docs/03-leaving-gateway.md and docs/04-browser.md."
fi
exit 0
