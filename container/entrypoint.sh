#!@dash@/bin/dash
set -eu

export PATH="@coreutils@/bin:@gnused@/bin:${PATH:+$PATH:}@granian@/bin:@searxng@/bin"

config_path="${__SEARXNG_CONFIG_PATH:-/etc/searxng}"
data_path="${__SEARXNG_DATA_PATH:-/var/cache/searxng}"
settings_path="${SEARXNG_SETTINGS_PATH:-${__SEARXNG_SETTINGS_PATH:-$config_path/settings.yml}}"
template_settings="@settingsTemplate@/settings.template.yml"
temporary_settings=

cleanup() {
  if [ -n "$temporary_settings" ]; then
    rm -f -- "$temporary_settings"
  fi
}
trap cleanup EXIT

export __SEARXNG_CONFIG_PATH="$config_path"
export __SEARXNG_DATA_PATH="$data_path"
export __SEARXNG_SETTINGS_PATH="$settings_path"
export SEARXNG_SETTINGS_PATH="$settings_path"

check_directory() {
  if [ ! -d "$1" ]; then
    printf '!!! ERROR !!! "%s" is not a valid directory, exiting...\n' "$1" >&2
    exit 1
  fi
}

check_file() {
  if [ ! -f "$1" ]; then
    printf '!!! ERROR !!! "%s" is not a valid file, exiting...\n' "$1" >&2
    exit 1
  fi
}

setup_ownership() {
  target_ownership=$(stat -c '%u:%g' "$1")
  if [ "$target_ownership" != '10001:10001' ]; then
    if [ "${FORCE_OWNERSHIP:-true}" = true ] && [ "$(id -u)" -eq 0 ]; then
      chown -R 10001:10001 "$1"
    else
      printf '!!! WARNING !!! "%s" is not owned by 10001:10001 (got %s); this may cause issues.\n' "$1" "$target_ownership" >&2
    fi
  fi
}

volume_handler() {
  check_directory "$1"
  setup_ownership "$1"
}

setup() {
  if [ ! -f "$settings_path" ]; then
    printf '... INFORMATION ... "%s" does not exist, creating from template...\n' "$settings_path"
    check_file "$template_settings"
    secret=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
    if [ "${#secret}" -ne 48 ]; then
      printf '!!! ERROR !!! failed to generate a 48-character settings secret, exiting...\n' >&2
      exit 1
    fi
    temporary_settings=$(mktemp -- "${settings_path}.XXXXXX")
    cp -fT -- "$template_settings" "$temporary_settings"
    sed -i "s/ultrasecretkey/$secret/g" "$temporary_settings"
    chmod 0600 "$temporary_settings"
    mv -fT -- "$temporary_settings" "$settings_path"
    temporary_settings=
  fi
  check_file "$settings_path"
}

printf 'SearXNG %s\n' "${__SEARXNG_VERSION:-unknown}"
volume_handler "$config_path"
volume_handler "$data_path"
setup

case "${SEARXNG_PORT:-}" in
  '') ;;
  *[!0-9]*) unset SEARXNG_PORT ;;
  *) GRANIAN_PORT="$SEARXNG_PORT"; export GRANIAN_PORT ;;
esac

exec granian searx.webapp:app
