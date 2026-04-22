#!/bin/sh
# Install claude-statusline to ~/.claude/hooks/statusline.sh
# and configure settings.json to use it.
set -e

DEST="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
RAW="https://raw.githubusercontent.com/liyoungc/claude-statusline/main/statusline.sh"

mkdir -p "$DEST"

echo "Downloading statusline.sh..."
curl -sSfL "$RAW" -o "$DEST/statusline.sh"
chmod +x "$DEST/statusline.sh"

# Patch settings.json if statusLine not already configured
if [ -f "$SETTINGS" ]; then
  if grep -q '"statusLine"' "$SETTINGS"; then
    echo "statusLine already in settings.json — updating command..."
    # Use a temp file for portable sed
    sed 's|"command":.*statusline.*"|"command": "sh ~/.claude/hooks/statusline.sh"|' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  else
    # Insert statusLine before the last closing brace
    sed '$ s/}$/,\n  "statusLine": {\n    "type": "command",\n    "command": "sh ~\/.claude\/hooks\/statusline.sh"\n  }\n}/' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  fi
else
  mkdir -p "$(dirname "$SETTINGS")"
  cat > "$SETTINGS" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/hooks/statusline.sh"
  }
}
EOF
fi

echo "Done. Restart Claude Code to see the statusline."
echo "Requires: jq, git, gh (optional, for CI status)"
