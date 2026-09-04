#!/usr/bin/env bash
# lib/secrets.sh — secret names come from config/secrets.env.example; values live
# only in the user's secrets file (mode 600). Nothing here prints a value.

[[ -n "${_WI_SECRETS_LOADED:-}" ]] && return 0
_WI_SECRETS_LOADED=1

# secrets_names EXAMPLE_FILE → one KEY per line
secrets_names() { grep -oE '^[A-Z][A-Z0-9_]*=' "$1" | tr -d '='; }

# secrets_get FILE KEY → value (empty if unset or file missing)
secrets_get() {
  [[ -f "$1" ]] || return 0
  ( set +u; set -a
    # shellcheck source=/dev/null
    source "$1" >/dev/null 2>&1
    set +a
    printf '%s' "${!2:-}" )
}

# secrets_write FILE KEY=VALUE... → rewrite FILE (mode 600); values bash-quoted with %q
secrets_write() {
  local file="$1" tmp kv
  shift
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  for kv in "$@"; do
    printf '%s=%q\n' "${kv%%=*}" "${kv#*=}" >> "$tmp"
  done
  chmod 600 "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

# secrets_missing FILE EXAMPLE → names whose value is empty, one per line
secrets_missing() {
  local key
  while IFS= read -r key; do
    [[ -n "$(secrets_get "$1" "$key")" ]] || echo "$key"
  done < <(secrets_names "$2")
}

# maven_settings_render USERNAME → ~/.m2/settings.xml body; token read from env at build time
maven_settings_render() {
  cat <<EOT
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>github</id>
      <username>$1</username>
      <password>\${env.GITHUB_TOKEN}</password>
    </server>
  </servers>
</settings>
EOT
}
