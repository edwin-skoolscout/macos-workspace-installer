#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/80-local-dev-wiring.sh — /etc/hosts entries for the dev tenants + mkcert CA.
STEP_DESC="/etc/hosts dev entries + mkcert local CA"
STEP_OS="all"
STEP_SUDO="yes"

HOSTS_FILE="${WI_HOSTS_FILE:-/etc/hosts}"

dev_hosts() { grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/dev-hosts.txt"; }

# host_present HOST — true if an uncommented line maps HOST
host_present() { grep -qE "^[^#]*[[:space:]]$1([[:space:]]|\$)" "$HOSTS_FILE"; }

mkcert_ca_present() {
  command_exists mkcert || return 1
  [[ -f "$(mkcert -CAROOT 2>/dev/null)/rootCA.pem" ]]
}

step_check() {
  load_brew || return 1
  local h
  while IFS= read -r h; do host_present "$h" || return 1; done < <(dev_hosts)
  mkcert_ca_present
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Homebrew missing"; }
  local h
  while IFS= read -r h; do
    if host_present "$h"; then log_ok "$h already in $HOSTS_FILE"; continue; fi
    if wi_dry "append 127.0.0.1 $h to $HOSTS_FILE"; then continue; fi
    printf '127.0.0.1\t%s\n' "$h" | sudo tee -a "$HOSTS_FILE" >/dev/null
    log_ok "added $h"
  done < <(dev_hosts)
  if mkcert_ca_present; then log_ok "mkcert CA already present"; else wi_run mkcert -install; fi
}
