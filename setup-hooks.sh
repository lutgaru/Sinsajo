#!/usr/bin/env bash
# Install the repository's Git hooks into .git/hooks.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

if [[ ! -d .githooks ]]; then
  echo "❌ .githooks directory not found."
  exit 1
fi

mkdir -p .git/hooks

for hook in .githooks/*; do
  [[ -f "$hook" ]] || continue
  name="$(basename "$hook")"
  cp "$hook" ".git/hooks/$name"
  chmod +x ".git/hooks/$name"
  echo "  installed $name"
done

chmod +x check.sh setup-hooks.sh

echo "✅ Git hooks installed!"
echo "   Run './check.sh' at any time to execute the same checks manually."
