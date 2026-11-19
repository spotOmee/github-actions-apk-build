#!/usr/bin/env bash
set -e

SKILL_NAME="github-actions-apk-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing ${SKILL_NAME} globally..."

TARGET_DIRS=(
  "$HOME/.agents/skills/${SKILL_NAME}"
  "$HOME/.gemini/skills/${SKILL_NAME}"
  "$HOME/.gemini/config/skills/${SKILL_NAME}"
  "$HOME/.claude/skills/${SKILL_NAME}"
)

# Common aliases
ALIASES=(
  "github-actions-build-apk"
  "github_actions_build_apk"
)

mkdir -p "$HOME/.agents/skills"
ln -sfn "$SCRIPT_DIR" "$HOME/.agents/skills/${SKILL_NAME}"
echo "[✔] Installed to $HOME/.agents/skills/${SKILL_NAME}"

for TARGET in "${TARGET_DIRS[@]}"; do
  PARENT_DIR="$(dirname "$TARGET")"
  if [ -d "$PARENT_DIR" ]; then
    ln -sfn "$SCRIPT_DIR" "$TARGET"
    echo "[✔] Linked to $TARGET"
  fi
done

# Create convenient aliases
for ALIAS in "${ALIASES[@]}"; do
  ln -sfn "$SCRIPT_DIR" "$HOME/.agents/skills/${ALIAS}"
  [ -d "$HOME/.gemini/skills" ] && ln -sfn "$SCRIPT_DIR" "$HOME/.gemini/skills/${ALIAS}"
  [ -d "$HOME/.gemini/config/skills" ] && ln -sfn "$SCRIPT_DIR" "$HOME/.gemini/config/skills/${ALIAS}"
  [ -d "$HOME/.claude/skills" ] && ln -sfn "$SCRIPT_DIR" "$HOME/.claude/skills/${ALIAS}"
done

echo ""
echo "🎉 Skill '${SKILL_NAME}' successfully installed!"
echo "You can now trigger it using: /github actions, /github actions build apk, build apk, or asking your agent to compile an Android APK in GitHub Actions."
