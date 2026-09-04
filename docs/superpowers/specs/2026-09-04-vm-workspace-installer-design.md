# VM Workspace Installer — Design

Date: 2026-09-04
Status: approved (design), pending spec review

## 1. Purpose

A re-runnable installer that turns a fresh VM into a machine that can build,
run and test `skoolscout-com`, `skoolscout-com-tenants` and `jefelabs-com`. It installs
Homebrew first, then every tool the project needs, then wires up local dev
(shell config, GitHub auth, repo clones, `/etc/hosts`, mkcert).

It replaces the dead `install-dependencies` Makefile target and the 687-line
`.scripts-tools/install-dev-dependencies.sh` in `skoolscout-com` with something
declarative and idempotent that lives in its own repo.

## 2. Targets

| Target | Notes |
|---|---|
| macOS 14+ on Apple Silicon (primary) | Parallels / Tart VMs. Docker via Colima needs nested virtualization, which Apple supports only on M3+ hosts running macOS 15+. The installer detects this and warns rather than fails. |
| macOS on Intel | Same path; no special handling. |
| Ubuntu 22.04 / 24.04 (x86_64, arm64) | Homebrew on Linux for CLI tools; Docker Engine from Docker's apt repo; no casks. |

Shell: zsh on macOS, bash or zsh on Ubuntu. The installer writes to the rc file
of the user's login shell (`$SHELL`).

## 3. Repository layout

```
bootstrap.sh                 curl-pipeable entry point (see §4.1)
install.sh                   orchestrator (see §4.2)
doctor.sh                    verification (see §4.3)
Brewfile.common              formulae for both OSes
Brewfile.macos               macOS-only formulae + casks
Brewfile.linux               Linux-only formulae (may be empty)
config/
  versions.env               tool version pins (see §8)
  repos.txt                  repos to clone
  npm-globals.txt            global npm packages
  claude-plugins.txt         Claude Code marketplaces + plugins
  apt-packages.txt           Ubuntu apt prerequisites
  dev-hosts.txt              /etc/hosts entries for local dev
  secrets.env.example        documented secret names, no values
lib/
  common.sh                  logging, OS/arch detect, sudo keep-alive, run/dry-run
  managed-block.sh           idempotent marked-block writer for rc files
  versions.sh                version parsing/comparison helpers
steps/
  10-homebrew.sh
  20-brew-bundle.sh
  30-shell-config.sh
  40-sdkman.sh
  41-node.sh
  42-python.sh
  43-terraform.sh
  44-rust.sh
  45-claude-code.sh
  50-docker.sh
  51-postgres.sh
  60-github-auth.sh
  70-clone-repos.sh
  80-local-dev-wiring.sh
  90-project-deps.sh
tests/
  *.bats                     unit tests for lib/
  Dockerfile.ubuntu          Linux smoke test image
  smoke-linux.sh             runs bootstrap inside the image, then doctor
Makefile                     lint, test, smoke-linux
README.md
```

## 4. Entry points

### 4.1 `bootstrap.sh`

Minimal, dependency-free bash. Intended for
`curl -fsSL <raw-url>/bootstrap.sh | bash` on a brand-new VM, and also runnable
from a local checkout (shared folder, USB, etc.).

1. Detect OS. Abort with a clear message on anything but macOS or Ubuntu.
2. macOS: `xcode-select --install` if Command Line Tools are missing, then wait
   for it to finish. Ubuntu: `apt-get install` the packages in
   `config/apt-packages.txt` (build-essential, procps, curl, file, git,
   ca-certificates, unzip, zip, libnss3-tools, musl-tools).
3. Install Homebrew with the official script, `NONINTERACTIVE=1`, and `eval
   "$(brew shellenv)"` for the current process.
4. If `install.sh` exists next to `bootstrap.sh`, use that checkout. Otherwise
   `git clone` `$INSTALLER_REPO` (default
   `https://github.com/ecruz165/macos-workspace-installer.git`, ref
   `$INSTALLER_REF`, default `main`) into
   `~/Development/Workspaces/ecruz165/macos-workspace-installer`.
5. `exec ./install.sh "$@"`, forwarding any flags.

HTTPS is used for the clone because no SSH key exists yet at this point. The
installer repo must be public or reachable with `GIT_ASKPASS`; this is a
documented prerequisite, not something bootstrap solves.

### 4.2 `install.sh`

```
install.sh [--only STEP[,STEP...]] [--skip STEP[,STEP...]] [--list]
           [--dry-run] [--yes] [--fail-fast] [--help]
```

- Sources `lib/*.sh` and `config/versions.env`.
- Discovers `steps/*.sh` in lexical order. A step is addressed by its file
  name without number and extension (`sdkman`, `docker`, ...).
- `--list` prints the steps with their OS applicability and exits.
- `--only` runs just those steps; `--skip` removes steps from the default set.
- `--dry-run` prints every command that would change the system without
  running it (via `run` in `lib/common.sh`).
- `--yes` answers every prompt with its default and never blocks on stdin.
  Missing secrets are warned about and skipped.
- `--fail-fast` stops at the first failed step; default is to continue and
  summarize.
- Requests sudo once up front and keeps it alive in the background for the run
  (same pattern as the Homebrew installer). Steps that need sudo declare it.
- Every run is logged with `tee` to
  `~/.local/state/workspace-installer/install-<timestamp>.log`.
- Exit code: 0 if every selected step passed or was skipped, 1 otherwise.

### 4.3 `doctor.sh`

Prints a table of checks and exits 0 only if nothing FAILed. Checks:

- Each tool in §7 is on `PATH` (after loading the managed shell block).
- Versions match `config/versions.env` for Java, Gradle, Node, Python,
  Terraform. The verdict policy (exact match, same major, newer allowed) is
  implemented in `doctor_verdict()` — see §15.
- `docker info` succeeds (socket reachable, daemon running).
- `psql --version` works.
- `brew doctor` has no errors (warnings are reported, not failed).
- `gh auth status` succeeds; `ssh -T git@github.com` authenticates.
- Each repo in `config/repos.txt` exists in the workspace with submodules
  initialised.
- Secrets file exists and each name in `secrets.env.example` is non-empty
  (values are never printed).
- Every host in `config/dev-hosts.txt` resolves to 127.0.0.1.
- mkcert root CA is installed (`mkcert -CAROOT` contains `rootCA.pem`).

## 5. Step contract

Each `steps/NN-name.sh` is sourced by the orchestrator and defines:

```bash
STEP_DESC="one line shown in --list and logs"
STEP_OS="all|macos|linux"
STEP_SUDO="yes|no|linux"   # linux = sudo only on Ubuntu

step_check() { ... }   # return 0 if already satisfied → step is skipped
step_run()   { ... }   # do the work; runs under set -euo pipefail
```

`step_check` makes every step idempotent: re-running the installer is safe and
fast. `step_run` must itself be safe to re-run (use `run` for mutations, check
before creating files, never append without the managed-block helper).

Steps must not depend on the interactive shell having been reloaded. Each step
that needs a tool installed by an earlier step sources the tool's own init
script (e.g. `sdkman-init.sh`, `nvm.sh`, `brew shellenv`) inside `step_run`.

## 6. Steps

| # | Step | OS | sudo | What it does | `step_check` |
|---|---|---|---|---|---|
| 10 | homebrew | all | macOS: no, Linux: yes | Ensures Homebrew is installed (bootstrap normally did this); runs `brew update`. | `brew --version` works |
| 20 | brew-bundle | all | no | `brew bundle --file Brewfile.common`, then the OS-specific Brewfile. Taps: `stripe/stripe-cli`. | `brew bundle check` passes for both files |
| 30 | shell-config | all | no | Writes the managed block (§10) to the login shell's rc file. | block present and identical |
| 40 | sdkman | all | no | Installs SDKMAN (curl script, `rcupdate=false`), then `sdk install java` for each of `JAVA_VERSIONS`, `sdk install gradle $GRADLE_VERSION`. Sets the first Java as default. `sdkman_auto_env=true` in `~/.sdkman/etc/config` so `.sdkmanrc` is honoured on `cd`. | all candidates present in `~/.sdkman/candidates` |
| 41 | node | all | no | Sources nvm (installed by brew), `nvm install $NODE_VERSION`, `nvm alias default`, then `npm i -g` each package in `config/npm-globals.txt`. | node version + every global present |
| 42 | python | all | no | `pyenv install -s $PYTHON_VERSION`, `pyenv global $PYTHON_VERSION`. awscli-local / terraform-local / localstack come from brew, not pip. | `pyenv versions` lists it |
| 43 | terraform | all | no | `tfenv install $TERRAFORM_VERSION`, `tfenv use`. | `terraform version` matches |
| 44 | rust | all | no | `rustup-init -y --no-modify-path`, `rustup target add $RUST_TARGET`. macOS additionally taps `filosottile/musl-cross` and installs `musl-cross` for the Lambda scraper. | target listed in `rustup target list --installed` |
| 45 | claude-code | all | no | Installs Claude Code with the native installer if `claude` is missing, then for each line in `config/claude-plugins.txt`: `claude plugin marketplace add <repo>` / `claude plugin install <name@marketplace>`. | `claude --version` works and `claude plugin list` shows every plugin |
| 50 | docker | all | Linux: yes | macOS: `colima start --cpu 4 --memory 8 --vm-type vz` and `brew services start colima` for auto-start; symlinks the socket to `/var/run/docker.sock` is NOT done (Testcontainers reads `DOCKER_HOST`, which the managed block exports). If virtualization is unavailable, prints the nested-virt explanation and returns 0 with a warning. Linux: adds Docker's apt repo, installs `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`, adds the user to the `docker` group, enables the service. | `docker info` succeeds |
| 51 | postgres | all | no | Ensures `postgresql@15` and `libpq` are installed (via brew-bundle) and `psql` is on PATH. Does NOT start the service: the project's Docker Compose runs its own Postgres on 5432 and a host service would collide. Prints the `brew services start postgresql@15` hint. | `psql --version` works |
| 60 | github-auth | all | no | `gh auth login` (interactive; skipped under `--yes` if not already logged in), generates an ed25519 SSH key if none exists, `gh ssh-key add`. Prompts for each secret in `secrets.env.example` (or reads it from the environment), writes `~/.config/skoolscout/secrets.env` (mode 600). Writes `~/.m2/settings.xml` with `<server><id>github</id>` using `${env.GITHUB_TOKEN}` so the token lives in one place. | gh logged in, key uploaded, secrets file complete, settings.xml present |
| 70 | clone-repos | all | no | For each line `url branch` in `config/repos.txt`: clone with `--recurse-submodules` into `$WORKSPACE_DIR` if absent, else `git fetch` and `git submodule update --init --recursive`. | every repo present with submodules initialised |
| 80 | local-dev-wiring | all | yes | Appends any missing `127.0.0.1 <host>` lines from `config/dev-hosts.txt` to `/etc/hosts`. Runs `mkcert -install`. | all hosts present, CA installed |
| 90 | project-deps | all | Linux: yes (Playwright deps) | In `skoolscout-com`: `direnv allow`, `npm i --no-workspaces`, `cd app-ui && npm i`, `cd app-test-e2e-runner && npm i && npx playwright install --with-deps chromium`. In `skoolscout-com-tenants`: `npm i`. In `jefelabs-com`: `pnpm install` (its `packageManager` pins pnpm 11). Sources the secrets file first so private registries authenticate. Skipped with a warning if secrets are missing. | `node_modules` present in each package and Playwright's chromium cached |

Default step set = all steps. `bootstrap.sh` passes flags through, so
`curl ... | bash -s -- --skip rust,postgres` works.

## 7. Package manifests

### Brewfile.common

```
tap "stripe/stripe-cli"
brew "git"
brew "gh"
brew "jq"
brew "direnv"
brew "tmux"
brew "neovim"
brew "herdr"
brew "mkcert"
brew "awscli"
brew "awscli-local"
brew "terraform-local"
brew "localstack"
brew "tfenv"
brew "libpq"
brew "postgresql@15"
brew "nvm"
brew "pnpm"
brew "pyenv"
brew "xz"
brew "rustup"
brew "libxml2"
brew "zip"
brew "unzip"
brew "coreutils"
brew "stripe/stripe-cli/stripe"
```

### Brewfile.macos

```
brew "colima"
brew "docker"
brew "docker-compose"
brew "docker-buildx"
cask "ghostty"
cask "visual-studio-code"
cask "google-chrome"
cask "postman"
cask "figma"
```

### Brewfile.linux

Empty placeholder. Docker comes from apt (§6 step 50); GUI apps are out of
scope on Linux.

### config/npm-globals.txt

```
task-master-ai
dotenv-cli
npm-check-updates
```

Claude Code is NOT an npm global: it is installed by its native installer
(`curl -fsSL https://claude.ai/install.sh | bash`, lands in `~/.local/bin`)
in step 45, which also installs plugins from `config/claude-plugins.txt`:

```
marketplace obra/superpowers-marketplace
plugin superpowers@superpowers-marketplace
plugin mattpocock-skills@claude-plugins-official
```

`@skoolscout/gen-dotenv` is deliberately not global: it is a devDependency of
`app-ui` and needs the private registry token, so it arrives with step 90.

### config/apt-packages.txt (Ubuntu only, installed by bootstrap)

```
build-essential procps curl file git ca-certificates gnupg unzip zip
libnss3-tools musl-tools
```

## 8. Configuration

`config/versions.env` (sourced by install.sh and doctor.sh):

```
JAVA_VERSIONS="25.0.3-amzn 21.0.9-amzn"   # root .sdkmanrc and app-service/.sdkmanrc
GRADLE_VERSION="9.6.1"                     # .sdkmanrc + gradle-wrapper.properties
NODE_VERSION="24.18.0"                     # .nvmrc
PYTHON_VERSION="3.10.11"                   # .python-version
TERRAFORM_VERSION="1.15.8"                 # CI workflows (README's 1.7.5 is stale)
RUST_TARGET="x86_64-unknown-linux-musl"    # app-functions/schoolScraper
WORKSPACE_DIR="$HOME/Development/Workspaces/skoolscout"
```

`config/repos.txt`:

```
git@github.com:skoolscout/skoolscout-com.git develop
git@github.com:skoolscout/skoolscout-com-tenants.git develop
git@github.com:skoolscout/jefelabs-com.git develop
git@github.com:skoolscout/jefelabs-scripts.git develop
git@github.com:skoolscout/jefelabs-docs.git develop
```

`jefelabs-com` is the source of the Maven packages `app-service` pulls from
GitHub Packages. `jefelabs-scripts` and `jefelabs-docs` are also the `.scripts`
and `.docs` submodules of the app repos; cloning them standalone gives a place
to edit and push them directly.

`config/dev-hosts.txt` (copied from the `DEV_HOSTS` list in the project
Makefile):

```
skoolscout.com.local
iym.skoolscout.com.local
demo-org.skoolscout.com.local
demo-com.skoolscout.com.local
demo-school.skoolscout.com.local
```

`config/secrets.env.example`:

```
GITHUB_TOKEN=            # PAT with read:packages — npm + Maven GitHub Packages
FONTAWESOME_PACKAGE_TOKEN=   # Font Awesome Pro npm registry
LOCALSTACK_AUTH_TOKEN=   # LocalStack Pro
```

## 9. Secrets

- Never stored in this repo. `secrets.env.example` holds names only.
- Written once to `~/.config/skoolscout/secrets.env`, mode 600, and exported by
  the managed shell block so `npm`, `docker compose` and `mvnw` pick them up
  from the environment. The project's own `.npmrc` already references
  `${GITHUB_TOKEN}` and `${FONTAWESOME_PACKAGE_TOKEN}`.
- `~/.m2/settings.xml` references `${env.GITHUB_TOKEN}` rather than embedding
  the value.
- Prompts use `read -s`; values are never echoed or logged. The log redacts
  anything matching `*_TOKEN=`.
- Under `--yes`, a secret already present in the environment is used; a
  missing one produces a warning and the dependent step (90) is skipped.

## 10. Shell configuration

`lib/managed-block.sh` writes exactly one block between markers, replacing it
on every run:

```
# >>> workspace-installer >>>
eval "$(/opt/homebrew/bin/brew shellenv)"         # or /home/linuxbrew/... on Linux
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix nvm)/nvm.sh" ] && source "$(brew --prefix nvm)/nvm.sh"
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null && eval "$(pyenv init -)"
eval "$(direnv hook zsh)"                         # or bash
export PATH="$HOME/.cargo/bin:$(brew --prefix libpq)/bin:$PATH"
[ -f "$HOME/.config/skoolscout/secrets.env" ] && set -a && source "$HOME/.config/skoolscout/secrets.env" && set +a
# macOS only:
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
# <<< workspace-installer <<<
```

Target file: `~/.zprofile` for zsh (login shells, matching the host Mac's
current layout), `~/.bashrc` for bash. The block is generated from a template
so OS/shell differences are substitutions, not separate copies.

## 11. Error handling and logging

- Every step runs under `set -euo pipefail` inside a subshell so a failure
  cannot leak variables or `cd` into the orchestrator.
- The orchestrator records PASS / SKIP / FAIL per step, prints a summary table
  at the end, and exits non-zero if any step FAILed.
- Default is continue-on-failure so one broken cask does not block the rest;
  `--fail-fast` flips that.
- `run()` in `lib/common.sh` prints the command, honours `--dry-run`, and is
  the only way steps execute mutating commands.
- Network failures are not retried; the user re-runs the installer, and
  `step_check` skips what already succeeded.
- All output is teed to the log file in §4.2.

## 12. Linux differences (summary)

| Concern | macOS | Ubuntu |
|---|---|---|
| Prerequisites | Xcode CLT | apt packages (§7) |
| Homebrew prefix | `/opt/homebrew` (`/usr/local` on Intel) | `/home/linuxbrew/.linuxbrew` |
| Docker | Colima + brew docker CLI | Docker Engine from Docker apt repo |
| GUI apps | casks | none |
| mkcert trust | system keychain | `libnss3-tools` for Chrome/Firefox |
| `/etc/resolver` | n/a (dnsmasq excluded) | n/a |
| Login shell rc | `~/.zprofile` | `~/.bashrc` (or `~/.zshrc` if zsh) |
| Nested virt warning | checked | not needed |

## 13. Explicitly excluded, and why

| Item | Reason |
|---|---|
| dnsmasq + `/etc/resolver` | Only in README; no script uses it. `make hosts` + mkcert cover local hostnames. |
| Docker Desktop | User chose Colima. |
| IntelliJ IDEA | Not requested. |
| yarn / bun | Mentioned in a README; skoolscout-com uses npm and jefelabs-com uses pnpm. |
| k6, ngrok, uv, git-lfs, yq, Flyway CLI | Zero or commented-out references. |
| Qodana CLI | JetBrains installer, CI uses the Action. Documented as manual in README. |
| `mtauth-install` | Private tool with no known distribution channel. Installer prints a reminder at the end. |
| Starting Postgres as a service | Would collide with the compose Postgres on 5432. |
| Cloning the standalone e2e runner repo | It lives inside `skoolscout-com/app-test-e2e-runner`. |

## 14. Testing

- `make lint`: `shellcheck -x` on every `.sh` and `.bats` helper. Zero
  warnings.
- `make test`: bats tests for `lib/managed-block.sh` (creates block, replaces
  block, leaves surrounding content untouched, no duplicate on re-run),
  `lib/versions.sh` (parsing `java -version`, `node --version`, `terraform
  version` output; comparison), and `doctor_verdict()`.
- `make smoke-linux`: builds `tests/Dockerfile.ubuntu` (ubuntu:24.04 with a
  non-root sudo user), runs `bootstrap.sh --yes --skip docker,github-auth,
  clone-repos,project-deps,local-dev-wiring` inside it, then `doctor.sh` with
  the same skips. Docker-in-Docker and GitHub auth are out of reach in the
  container, hence the skips. This is the automated proof of the Linux path.
- macOS path: run in a fresh Parallels VM, then `doctor.sh`. Manual, because
  macOS VMs cannot be spun up from CI on this setup.
- `--dry-run` on the host Mac as a cheap sanity check that every step parses
  and sequences correctly.

## 15. Learning-mode contribution point

`doctor_verdict expected actual` in `doctor.sh` decides PASS / WARN / FAIL when
an installed version differs from the pin. Options: exact match only, same
major = WARN, newer = PASS, older = FAIL. This shapes how noisy the doctor is
after a `brew upgrade`. The function will be stubbed with a signature, a
comment and a TODO for the user to implement (5-10 lines).

## 16. Future (not in scope)

- GitHub Actions running lint + bats + smoke-linux on push.
- A `--profile minimal` that skips GUI apps and Rust.
- Uninstall / reset script.
