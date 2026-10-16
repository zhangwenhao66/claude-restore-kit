# Copy this file to config.sh and fill in the values printed by scripts/find-partitions.sh.
#
#   cp scripts/config.example.sh scripts/config.sh
#   $EDITOR scripts/config.sh
#
# Paths are macOS. On Linux, APP_* are typically under ~/.config/.

# ---- Source: the gateway ("3p") deployment that HAS your work ----
# Find it with: ls "$HOME/Library/Application Support/Claude-3p/claude-code-sessions/"
SRC_ACC="00000000-0000-0000-0000-000000000000"
SRC_ORG="00000000-0000-0000-0000-000000000000"

# ---- Target: the real account the app is logged into NOW ----
# Find it with: ls "$HOME/Library/Application Support/Claude/claude-code-sessions/"
DST_ACC="00000000-0000-0000-0000-000000000000"
DST_ORG="00000000-0000-0000-0000-000000000000"

# ---- Cowork (Chat/Cowork tab) uses its own account/org directory names ----
# NOTE the asymmetry, it is the mirror image of the outbound kit:
#   * the gateway ("3p") side TRUNCATES the names to 8 characters, e.g. "a1b2c3d4" / "00000000"
#   * the normal account side uses the FULL uuids
# So SRC_*_COW is the truncated pair and DST_*_COW is the full pair.
# Read the real names with:
#   ls "$HOME/Library/Application Support/Claude-3p/local-agent-mode-sessions/"
#   ls "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/"
# If you do not want to migrate Cowork, set MIGRATE_COWORK=0.
MIGRATE_COWORK=1
SRC_ACC_COW=""
SRC_ORG_COW=""
DST_ACC_COW=""
DST_ORG_COW=""

# ---- How to treat the account's existing scheduled tasks ----
#   merge   (default) ids present on both sides are updated from the gateway; ids that
#           exist only in the account are left untouched, enabled state and all
#   replace the account's task list is replaced by the gateway's (the old file is backed up)
#   skip    leave the account's task list alone; restore sessions and Cowork only
TASK_MODE="merge"

# ---- App data directories ----
# Normal account mode uses "Claude"; third-party/gateway ("3p") mode uses "Claude-3p".
# Here the GATEWAY side is the source and the ACCOUNT side is the target.
APP_OLD="$HOME/Library/Application Support/Claude-3p"   # source: gateway deployment
APP_NEW="$HOME/Library/Application Support/Claude"      # target: logged-in account

CODE_SRC="$APP_OLD/claude-code-sessions/$SRC_ACC/$SRC_ORG"
CODE_DST="$APP_NEW/claude-code-sessions/$DST_ACC/$DST_ORG"
COW_SRC="$APP_OLD/local-agent-mode-sessions/$SRC_ACC_COW/$SRC_ORG_COW"
COW_DST="$APP_NEW/local-agent-mode-sessions/$DST_ACC_COW/$DST_ORG_COW"
