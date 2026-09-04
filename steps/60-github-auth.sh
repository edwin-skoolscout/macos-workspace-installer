#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/60-github-auth.sh — gh login, SSH key, secrets file, Maven settings.xml.
STEP_DESC="GitHub: gh login, SSH key, secrets file, Maven settings.xml"
STEP_OS="all"
STEP_SUDO="no"

# shellcheck source=lib/secrets.sh
source "$WI_ROOT/lib/secrets.sh"

SECRETS_EXAMPLE="$WI_ROOT/config/secrets.env.example"
SSH_KEY="$HOME/.ssh/id_ed25519"
MAVEN_SETTINGS="$HOME/.m2/settings.xml"

gh_logged_in() { command_exists gh && gh auth status -h github.com >/dev/null 2>&1; }

step_check() {
  load_brew || return 1
  gh_logged_in || return 1
  [[ -f "$SSH_KEY.pub" ]] || return 1
  [[ -z "$(secrets_missing "$WI_SECRETS_FILE" "$SECRETS_EXAMPLE")" ]] || return 1
  grep -q '<id>github</id>' "$MAVEN_SETTINGS" 2>/dev/null
}

ensure_ssh_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    if ! wi_dry "generate SSH key $SSH_KEY"; then
      mkdir -p "$HOME/.ssh"
      chmod 700 "$HOME/.ssh"
      ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "$USER@$(hostname -s)"
    fi
  fi
  if ! grep -q '^github.com ' "$HOME/.ssh/known_hosts" 2>/dev/null; then
    if ! wi_dry "add github.com to ~/.ssh/known_hosts"; then
      ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
    fi
  fi
}

ensure_gh_login() {
  gh_logged_in && return 0
  if [[ "$WI_YES" == 1 ]]; then
    log_warn "gh is not logged in and --yes was given; skipping. Later: gh auth login --git-protocol ssh"
    return 0
  fi
  if wi_dry "gh auth login --git-protocol ssh --web (interactive)"; then return 0; fi
  gh auth login --hostname github.com --git-protocol ssh --web
  if [[ -f "$SSH_KEY.pub" ]] && ! gh ssh-key list 2>/dev/null | grep -qF "$(cut -d' ' -f2 "$SSH_KEY.pub")"; then
    gh ssh-key add "$SSH_KEY.pub" --title "$(hostname -s)" \
      || log_warn "could not upload the SSH key; run: gh ssh-key add $SSH_KEY.pub"
  fi
}

collect_secrets() {
  local key val missing=0
  local entries=()
  while IFS= read -r key; do
    val="${!key:-}"
    [[ -n "$val" ]] || val="$(secrets_get "$WI_SECRETS_FILE" "$key")"
    if [[ -z "$val" && "$WI_YES" != 1 && "$WI_DRY_RUN" != 1 ]]; then
      read -r -s -p "$key (leave empty to skip): " val
      echo
    fi
    [[ -n "$val" ]] || { log_warn "$key is not set"; missing=1; }
    entries+=("$key=$val")
  done < <(secrets_names "$SECRETS_EXAMPLE")
  if wi_dry "write $WI_SECRETS_FILE (mode 600)"; then return 0; fi
  secrets_write "$WI_SECRETS_FILE" ${entries[@]+"${entries[@]}"}
  log_ok "secrets written to $WI_SECRETS_FILE"
  [[ "$missing" == 0 ]] || log_warn "Some secrets are empty; project-deps stays skipped until they are set (re-run: ./install.sh --only github-auth)"
}

ensure_maven_settings() {
  local user
  if grep -q '<id>github</id>' "$MAVEN_SETTINGS" 2>/dev/null; then return 0; fi
  if [[ -f "$MAVEN_SETTINGS" ]]; then
    log_warn "$MAVEN_SETTINGS exists without a <server><id>github</id> entry; not overwriting. Add one that uses \${env.GITHUB_TOKEN}."
    return 0
  fi
  user="$(gh api user -q .login 2>/dev/null || echo "$USER")"
  if wi_dry "write $MAVEN_SETTINGS"; then return 0; fi
  mkdir -p "$HOME/.m2"
  maven_settings_render "$user" > "$MAVEN_SETTINGS"
  log_ok "wrote $MAVEN_SETTINGS"
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Homebrew missing"; }
  ensure_ssh_key
  ensure_gh_login
  collect_secrets
  ensure_maven_settings
}
