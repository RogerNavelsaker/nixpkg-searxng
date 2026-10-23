#!/usr/bin/env bash
set -euo pipefail

entrypoint=${1:?usage: entrypoint-test <entrypoint>}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

setup_case() {
  local dir=$1
  mkdir -p "$dir/config" "$dir/data" "$dir/bin"
  printf '#!%s\n' "$BASH" >"$dir/bin/granian"
  cat >>"$dir/bin/granian" <<'EOF'
printf '%s\n' "${GRANIAN_PORT-unset}" >"$RUNNER_PORT_FILE"
printf '%s\n' "$*" >"$RUNNER_ARGS_FILE"
EOF
  chmod +x "$dir/bin/granian"
}

run_entrypoint() {
  local dir=$1
  shift
  env \
    PATH="$dir/bin:$PATH" \
    __SEARXNG_CONFIG_PATH="$dir/config" \
    __SEARXNG_DATA_PATH="$dir/data" \
    __SEARXNG_SETTINGS_PATH="$dir/config/settings.yml" \
    __SEARXNG_VERSION=test \
    FORCE_OWNERSHIP=false \
    GRANIAN_PORT=8080 \
    RUNNER_PORT_FILE="$dir/port" \
    RUNNER_ARGS_FILE="$dir/args" \
    "$@" \
    "$entrypoint"
}

created="$tmp/created"
setup_case "$created"
run_entrypoint "$created" SEARXNG_PORT=9090 || fail 'entrypoint failed on first start'
settings="$created/config/settings.yml"
[[ -f "$settings" ]] || fail 'first start did not create settings.yml'
grep -q '^use_default_settings: true$' "$settings" || fail 'template defaults were not copied'
if grep -q 'ultrasecretkey' "$settings"; then fail 'template secret placeholder was not replaced'; fi
secret=$(sed -n 's/^[[:space:]]*secret_key: "\([A-Za-z0-9]*\)"$/\1/p' "$settings")
[[ $secret =~ ^[0-9a-f]{48}$ ]] || fail 'generated secret is not 48 lowercase hexadecimal characters'
[[ $(stat -c '%a' "$settings") == 600 ]] || fail 'generated settings permissions are not 0600'
[[ -f "$created/port" ]] || fail 'entrypoint did not exec Granian'
[[ $(cat "$created/port") == 9090 ]] || fail 'SEARXNG_PORT did not map to GRANIAN_PORT'
[[ $(cat "$created/args") == 'searx.webapp:app' ]] || fail 'entrypoint did not target the SearXNG WSGI app'

random_failure="$tmp/random-failure"
setup_case "$random_failure"
empty_random="$tmp/empty-random"
: >"$empty_random"
failed_entrypoint="$tmp/entrypoint-empty-random"
sed "s|/dev/urandom|$empty_random|" "$entrypoint" >"$failed_entrypoint"
chmod +x "$failed_entrypoint"
original_entrypoint=$entrypoint
entrypoint=$failed_entrypoint
if run_entrypoint "$random_failure"; then fail 'empty random source was accepted'; fi
entrypoint=$original_entrypoint
[[ ! -e "$random_failure/config/settings.yml" ]] || fail 'failed secret generation left partial settings'
[[ ! -e "$random_failure/port" ]] || fail 'runner executed after secret generation failed'

existing="$tmp/existing"
setup_case "$existing"
cat >"$existing/config/settings.yml" <<'EOF'
use_default_settings: true
server:
  secret_key: "keep-this-secret"
EOF
cp "$existing/config/settings.yml" "$existing/expected.yml"
run_entrypoint "$existing" SEARXNG_PORT=invalid || fail 'entrypoint failed with existing settings'
cmp -s "$existing/expected.yml" "$existing/config/settings.yml" || fail 'existing settings were modified'
[[ $(cat "$existing/port") == 8080 ]] || fail 'invalid SEARXNG_PORT replaced the default GRANIAN_PORT'

missing_config="$tmp/missing-config"
setup_case "$missing_config"
rm -rf "$missing_config/config"
if run_entrypoint "$missing_config"; then fail 'missing config directory was accepted'; fi
[[ ! -e "$missing_config/port" ]] || fail 'runner executed with missing config directory'

missing_data="$tmp/missing-data"
setup_case "$missing_data"
rm -rf "$missing_data/data"
if run_entrypoint "$missing_data"; then fail 'missing data directory was accepted'; fi
[[ ! -e "$missing_data/port" ]] || fail 'runner executed with missing data directory'

printf '%s\n' 'entrypoint behavior tests passed'
