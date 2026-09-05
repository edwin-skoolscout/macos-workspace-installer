# macos-workspace-installer

One command turns a fresh **macOS** or **Ubuntu** VM into a machine that can build,
run and test `skoolscout-com`, `skoolscout-com-tenants` and `jefelabs-com`.

## Quick start (new VM)

```bash
curl -fsSL https://raw.githubusercontent.com/edwin-skoolscout/macos-workspace-installer/main/bootstrap.sh | bash
```

The repo is public, so that works on a brand-new VM with nothing but curl. You can also run
it from a local checkout (shared folder / USB stick) with `./bootstrap.sh`;
`INSTALLER_REPO=<url>` and `INSTALLER_REF=<branch>` override the clone source.

```bash
./bootstrap.sh
```

Have ready: your login password (the Homebrew installer and the `/etc/hosts` step need sudo,
so expect a prompt early on), your GitHub login (a browser opens for `gh auth login`), a
GitHub PAT with `read:packages`, the Font Awesome Pro token, and the LocalStack Pro token.
When it finishes, open a new terminal and run `./doctor.sh` from the installer directory
(`~/Development/Workspaces/ecruz165/macos-workspace-installer`).

The list of repos to clone is yours to define and is not tracked. An interactive run asks
for them (URL and branch, one at a time) and writes `config/repos.txt`; with `--yes` it says
what is missing and moves on. You can also copy `config/repos.txt.example` to
`config/repos.txt`, edit it, and run `./install.sh --only clone-repos,project-deps`.

## What it installs

| Area | Tools |
|---|---|
| Package manager | Homebrew (macOS) / Linuxbrew (Ubuntu) + `Brewfile.common`, `Brewfile.<os>` |
| Languages | Java 25.0.3 + 21.0.9 (Corretto, sdkman), Gradle 9.6.1, Node 24.18.0 (nvm), Python 3.10.11 (pyenv), Terraform 1.15.8 (tfenv), Rust stable + musl target |
| Data | PostgreSQL 15 + `psql` (installed, not started: the app runs Postgres in-process) |
| CLI | git, gh, jq, direnv, tmux, neovim, herdr, mkcert, awscli, awslocal, tflocal, localstack, libxml2, zip; macOS only: Stripe CLI (its brew tap does not build on Linux) and Antigravity CLI `agy` (cask) |
| npm globals | dotenv-cli, npm-check-updates |
| Claude Code | native install + plugins from `config/claude-plugins.txt` (superpowers, mattpocock-skills) |
| GUI (macOS) | Ghostty, VS Code, Google Chrome, Postman, Figma |
| Setup | shell rc block, `gh auth login`, SSH key, secrets file, `~/.m2/settings.xml`, repo clones with submodules, `/etc/hosts` dev entries, mkcert CA, `npm install` + Playwright chromium |

Pins live in `config/versions.env`; hosts in `config/dev-hosts.txt`; repos in
`config/repos.txt`, which is git-ignored so each machine or fork keeps its own list (start
from `config/repos.txt.example`).

## Running pieces

```bash
./install.sh --list                    # see the steps
./install.sh --only sdkman,postgres    # just those
./install.sh --skip rust               # everything else
./install.sh --dry-run --yes           # show what would change
./install.sh --only github-auth        # re-enter secrets
./doctor.sh                            # verify; exit 0 = healthy
```

Every step checks itself first, so re-running is safe and fast. Logs go to
`~/.local/state/workspace-installer/install-<timestamp>.log` with token values redacted.

## Secrets

Names are in `config/secrets.env.example`; values are prompted once and stored in
`~/.config/skoolscout/secrets.env` (mode 600), exported by the shell block. Maven reads
`${env.GITHUB_TOKEN}` from `~/.m2/settings.xml`. Nothing secret is ever in this repo.

## Development

```bash
brew install bats-core shellcheck
make lint          # shellcheck everything
make test          # bats unit tests
make list          # step list via macOS's stock bash 3.2
make dry-run       # full dry run on this machine
make smoke-linux   # Linux path in an Ubuntu 24.04 container; needs Docker on this machine (20–40 min)
```

`lib/verdict.sh` holds `doctor_verdict`, the policy for how loudly the doctor complains
when an installed version drifts from the pin.

## Not installed, on purpose

Docker in any form (Colima, Docker Desktop, Docker Engine): these VMs are isolated dev
boxes and the app runs Postgres in-process, so nothing needs a container runtime. A macOS
guest on an M1/M2 host could not run one anyway, since Colima and Docker Desktop both boot
a Linux VM and that needs nested virtualization (M3 or newer host on macOS 15+).

Also skipped: dnsmasq (unused by any script), IntelliJ, yarn/bun, k6, ngrok, the Qodana
CLI (JetBrains installer) and `mtauth-install` (private; install it by hand).
