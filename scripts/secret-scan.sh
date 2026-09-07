#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pattern='(client_secret[[:space:]]*[:=][[:space:]]*["'"'][^"'"']+["'"']|client secret[[:space:]]*[:=][[:space:]]*[^[:space:]]+|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~-]{16,}|-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,})'
status=0

scan_current() {
  local matches
  matches=$(git grep -IlE "$pattern" -- . ':!security/secret-scan-*' 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "Potential credential pattern in tracked files:"
    sed 's#^#  #' <<<"$matches"
    status=1
  fi
}

scan_history() {
  while IFS= read -r commit; do
    if git grep -IlE "$pattern" "$commit" -- . ':!security/secret-scan-*' 2>/dev/null | sed "s#^#$commit #" | grep -q .; then
      echo "Potential credential pattern in commit $commit"
      status=1
    fi
  done < <(git rev-list --all)
}

for path in .env .env.local .env.production; do
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    echo "Tracked environment file: $path"
    status=1
  fi
done

scan_current
scan_history

if [[ "$status" -ne 0 ]]; then
  echo "Secret scan failed. Remove the material from the repository and rotate it."
  exit "$status"
fi

echo "secret scan: no credential patterns in tracked files or reachable history"
