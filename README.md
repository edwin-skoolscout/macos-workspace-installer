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
so expect a prompt early on), a GitHub classic PAT with `repo` + `read:packages` that you have
authorised for your organisation (token page → Configure SSO), the Font Awesome Pro token, and
the LocalStack Pro token. The PAT is the only GitHub credential: gh logs in with it, git clones
over HTTPS with it, and npm and Maven read packages with it. No SSH key, no browser login.
When it finishes, open a new terminal and run `./doctor.sh` from the installer directory
(`~/Development/Workspaces/ecruz165/macos-workspace-installer`).

Repos are cloned into `~/Development/Workspaces/<owner>/<repo>`. The list is yours to define
and is not tracked. The easiest way to build it is the picker: it lists a GitHub owner's
repos, lets you search and select, records the choice in `config/repos.txt` and clones.
Every cloned repo gets a shell alias named after it, so `skoolscout-com` from any directory is
`cd ~/Development/Workspaces/skoolscout/skoolscout-com`. The aliases are rebuilt from what is
on disk each time a shell starts; open a new terminal after cloning to pick up new ones.
`agent` is also defined: it runs `claude --dangerously-skip-permissions`.

```bash
./clone-repos.sh skoolscout                   # type to search, tab to select, enter to clone
./clone-repos.sh ecruz165 --filter agentx     # narrow the list first
./clone-repos.sh skoolscout --all --dry-run   # everything; only show what would happen
```

An interactive install run with no `config/repos.txt` asks for an owner and opens the same
picker, or takes URLs by hand if you leave the owner blank. With `--yes` it says what is
missing and moves on. You can also copy `config/repos.txt.example` to `config/repos.txt`,
edit it, and run `./install.sh --only clone-repos,project-deps`.

The repos are private. `repos.txt` keeps the `git@github.com:` URLs GitHub shows, and the
github-auth step rewrites them (and submodule URLs) to HTTPS at clone time, so the one PAT covers
everything. If a clone is refused, both paths stop and print the fix: a missing or unauthorised
token means `GITHUB_TOKEN` in `~/.config/skoolscout/secrets.env` and `./install.sh --only
github-auth`; a SAML SSO refusal means the token exists but is not authorised for the org yet
(token page → Configure SSO → Authorize). Then rerun the command.

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
| Setup | shell rc block, secrets file, gh login + git over HTTPS with the token, `~/.m2/settings.xml`, repo clones with submodules, local Postgres instances from `config/databases.txt`, `/etc/hosts` dev entries, mkcert CA, `npm install` + Playwright chromium |

Pins live in `config/versions.env`; hosts in `config/dev-hosts.txt`; repos in
`config/repos.txt`, which is git-ignored so each machine or fork keeps its own list (fill it
with `./clone-repos.sh <owner>` or start from `config/repos.txt.example`).

## Running pieces

```bash
./install.sh --list                    # see the steps
./install.sh --only sdkman,postgres    # just those
./install.sh --skip rust               # everything else
./install.sh --dry-run --yes           # show what would change
./install.sh --only github-auth        # re-enter secrets
./clone-repos.sh skoolscout            # pick and clone more repos
./create-database.sh create mydb       # local Postgres instance in ~/Development/Databases/mydb
./doctor.sh                            # verify; exit 0 = healthy
```

Every step checks itself first, so re-running is safe and fast. Logs go to
`~/.local/state/workspace-installer/install-<timestamp>.log` with token values redacted.

## Local Postgres instances

`create-database.sh` replaces `jefelabs-scripts/tools/setup-database.sh`: one data directory per
instance under `~/Development/Databases/<name>` (`DATABASES_DIR` in `config/versions.env`), trust
auth on the socket, scram on localhost, the first free port from 5433 saved in the instance's
`postgresql.conf`, a `postgres` superuser, and an application role that owns a database named
after the instance.

```bash
./create-database.sh create                 # named after the current directory; asks when run in a terminal
./create-database.sh create mydb --user app --password secret --port 5440
./create-database.sh status                 # every instance: version, port, running?
./create-database.sh stop mydb
./create-database.sh create mydb --dry-run  # print the plan
```

Instances made by the old script keep working: each is served by the Homebrew formula matching
its `PG_VERSION` (`postgresql@13` for the existing ones, `postgresql@15` for new ones), and
`PG_BIN` overrides the lookup.

The databases the repos depend on are declared in `config/databases.txt`, one line per repo
(`<repo> <database> <port> <user> <password> [init-sql-dir]`), with the values from the repo's
own docker-compose Postgres service so the app's config keeps working without Docker. Edit it
to suit. `./create-database.sh sync` creates every instance whose repo is cloned, runs the
repo's init scripts once, and keeps it running on reruns; `clone-repos.sh` runs it for the
repos you just picked (`--no-databases` to skip), and the `databases` install step runs it on
a full install. `./create-database.sh reset skoolscout_db` is the `make db-reset` equivalent:
stop, delete the data directory, recreate it and rerun the init scripts; boot the app with
the `ide` profile afterwards for Flyway, then `make db-reset-seed` if you need the demo tenant.
A pinned port that something else holds, such as the compose container still running on
5432, is refused up front.

## Secrets

Names are in `config/secrets.env.example`; values are prompted once and stored in
`~/.config/skoolscout/secrets.env` (mode 600), exported by the shell block. Maven reads
`${env.GITHUB_TOKEN}` from `~/.m2/settings.xml`. Nothing secret is ever in this repo.

## Development

```bash
brew install bats-core shellcheck
make lint          # shellcheck everything
make test          # bats for the shell + node --test for tools/*
make check         # tsc over tools/*
make list          # step list via macOS's stock bash 3.2
make dry-run       # full dry run on this machine
make smoke-linux   # Linux path in an Ubuntu 24.04 container; needs Docker on this machine (20–40 min)
```

`tools/*` are npm workspaces holding the TypeScript utilities (`clone-repos`, `create-database`,
and `lib` for what they share). Node 24
runs their `.mts` files directly, so there is no build; `make test` runs `npm ci` once. To add
a utility, create `tools/<name>` with its own `package.json` and a `src/main.mts` that uses
commander for arguments and inquirer for prompts, a `bin` entry, and a top-level `<name>.sh`
wrapper that sources `lib/node-tool.sh` like the existing two. The `bin` entries mean
`npm exec clone-repos -- skoolscout` and `npm exec create-database -- list` also work from the
repo once dependencies are installed; the wrappers stay the entry points on a fresh VM because
they find Node and install those dependencies first.

`lib/verdict.sh` holds `doctor_verdict`, the policy for how loudly the doctor complains
when an installed version drifts from the pin.

## Not installed, on purpose

Docker in any form (Colima, Docker Desktop, Docker Engine): these VMs are isolated dev
boxes and the app runs Postgres in-process, so nothing needs a container runtime. A macOS
guest on an M1/M2 host could not run one anyway, since Colima and Docker Desktop both boot
a Linux VM and that needs nested virtualization (M3 or newer host on macOS 15+).

Also skipped: dnsmasq (unused by any script), IntelliJ, yarn/bun, k6, ngrok, the Qodana
CLI (JetBrains installer) and `mtauth-install` (private; install it by hand).
