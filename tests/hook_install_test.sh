#!/usr/bin/env bash
# hook_install_test.sh — verify install-claude-hook.sh is idempotent, chains
# onto an existing SessionStart hook without clobbering it, and cleanly
# uninstalls. Operates ONLY on a throwaway CLAUDE_CONFIG_DIR — never the real
# ~/.claude. Needs jq.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed\n'
    exit 0
fi

CFG="$(mktemp -d)"
trap 'rm -rf "$CFG"' EXIT
export CLAUDE_CONFIG_DIR="$CFG"

# seed a pre-existing, unrelated SessionStart hook + another top-level key
cat > "$CFG/settings.json" <<'EOF'
{ "model": "sonnet",
  "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo preexisting" } ] } ] } }
EOF

bash "$ROOT/hooks/install-claude-hook.sh" >/dev/null 2>&1
bash "$ROOT/hooks/install-claude-hook.sh" >/dev/null 2>&1   # idempotent second run

pre="$(jq -e '[.hooks.SessionStart[].hooks[].command] | index("echo preexisting") != null' "$CFG/settings.json")"
[ "$pre" = "true" ] && ok "pre-existing hook preserved" || bad "pre-existing hook lost"

cnt="$(jq '[.hooks.SessionStart[].hooks[].command | select(test("claude-session-map.sh"))] | length' "$CFG/settings.json")"
[ "$cnt" = "1" ] && ok "our hook present exactly once (idempotent)" || bad "our hook count=$cnt"

model="$(jq -r '.model' "$CFG/settings.json")"
[ "$model" = "sonnet" ] && ok "unrelated top-level key intact" || bad "top-level key mangled ($model)"

bash "$ROOT/hooks/install-claude-hook.sh" uninstall >/dev/null 2>&1
gone="$(jq '[.hooks.SessionStart[].hooks[].command | select(test("claude-session-map.sh"))] | length' "$CFG/settings.json")"
still="$(jq -e '[.hooks.SessionStart[].hooks[].command] | index("echo preexisting") != null' "$CFG/settings.json")"
if [ "$gone" = "0" ] && [ "$still" = "true" ]; then
    ok "uninstall removed only our hook"
else
    bad "uninstall wrong (ours=$gone preexisting=$still)"
fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
