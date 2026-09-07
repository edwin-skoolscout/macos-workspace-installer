#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/60-github-auth.sh — secrets file, gh login, git over HTTPS, Maven settings.xml.
#
# One classic PAT (GITHUB_TOKEN: repo + read:packages, SSO-authorised for the org) is the only
# GitHub credential a machine needs. gh treats an exported GITHUB_TOKEN as its login, gh becomes
# git's credential helper, and git@github.com: URLs are rewritten to HTTPS so the SSH URLs in
# repos.txt (and in submodules) clone with the same token. No SSH key: under SAML SSO every key
# would need its own browser-side authorisation per machine.
STEP_DESC="GitHub: secrets file, gh login, git over HTTPS with the token, Maven settings.xml"
STEP_OS="all"
STEP_SUDO="no"

# shellcheck source=lib/secrets.sh
source "$WI_ROOT/lib/secrets.sh"

SECRETS_EXAMPLE="$WI_ROOT/config/secrets.env.example"
MAVEN_SETTINGS="$HOME/.m2/settings.xml"
REPOS_FILE="${WI_REPOS_FILE:-$WI_ROOT/config/repos.txt}"
SSO_HINT="Open https://github.com/settings/tokens, pick the token, 'Configure SSO' → Authorize the organisation, then rerun: ./install.sh --only github-auth,clone-repos"

gh_logged_in() { command_exists gh && gh auth status -h github.com >/dev/null 2>&1; }

# git_https_ready — gh answers git's credential prompts for github.com and git@github.com: URLs
# are rewritten to HTTPS (what `gh auth setup-git` + the insteadOf rewrite leave behind).
git_https_ready() {
  git config --global --get-all credential.https://github.com.helper 2>/dev/null | grep -q 'gh auth git-credential' || return 1
  [[ "$(git config --global --get url.https://github.com/.insteadof 2>/dev/null)" == "git@github.com:" ]]
}

step_check() {
  load_brew || return 1
  gh_logged_in || return 1
  git_https_ready || return 1
  [[ -z "$(secrets_missing "$WI_SECRETS_FILE" "$SECRETS_EXAMPLE")" ]] || return 1
  grep -q '<id>github</id>' "$MAVEN_SETTINGS" 2>/dev/null
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

# ensure_gh_login — an exported GITHUB_TOKEN already counts as logged in; otherwise the browser
# flow, over HTTPS so the resulting OAuth token also serves git. A token GitHub rejects has to
# be replaced, not worked around: gh refuses the browser login while the variable is set, and
# the value in the secrets file would be reused on the next run.
ensure_gh_login() {
  gh_logged_in && return 0
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log_error "GitHub rejects GITHUB_TOKEN from $WI_SECRETS_FILE (bad credentials)."
    log_error "Classic PAT values show only once, at creation: regenerate it on https://github.com/settings/tokens, Configure SSO → Authorize the org, then: GITHUB_TOKEN=<new token> ./install.sh --only github-auth"
    return 1
  fi
  if [[ "$WI_YES" == 1 ]]; then
    log_warn "gh is not logged in and --yes was given; set GITHUB_TOKEN in $WI_SECRETS_FILE or run: gh auth login --git-protocol https"
    return 0
  fi
  if wi_dry "gh auth login --git-protocol https --web (interactive)"; then return 0; fi
  gh auth login --hostname github.com --git-protocol https --web
}

ensure_git_https() {
  git_https_ready && return 0
  wi_run gh auth setup-git
  wi_run git config --global url."https://github.com/".insteadOf "git@github.com:"
}

# check_org_access — read the first repo in repos.txt with the token. Under SAML SSO GitHub
# answers 403 "organization SAML enforcement" until the token is authorised for the org; that
# needs a browser, so stop here with the link rather than fail five clones later.
check_org_access() {
  local url _ slug out
  [[ -f "$REPOS_FILE" ]] || return 0
  read -r url _ < <(grep -vE '^[[:space:]]*(#|$)' "$REPOS_FILE") || return 0
  [[ -n "$url" ]] || return 0
  slug="$(repo_dir_for_url "$url")" || return 0
  slug="${slug#"$WORKSPACE_DIR"/}"
  if wi_dry "gh api repos/$slug (checks the token is authorised for the org)"; then return 0; fi
  gh_logged_in || return 0
  if out="$(gh api "repos/$slug" -q .full_name 2>&1)"; then log_ok "token reads $slug"; return 0; fi
  if [[ "$out" == *SAML* ]]; then
    log_error "GitHub blocks $slug: the token is not authorised for the organisation's SAML SSO."
    log_error "$SSO_HINT"
    return 1
  fi
  log_warn "could not read $slug with the token: $out"
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
  collect_secrets
  load_secrets 2>/dev/null || true   # GITHUB_TOKEN into this process: gh's login from here on
  ensure_gh_login || return 1
  ensure_git_https
  check_org_access || return 1
  ensure_maven_settings
}
