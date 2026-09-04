#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/50-docker.sh — Colima on macOS, Docker Engine (apt) on Ubuntu.
STEP_DESC="Docker: Colima on macOS, Docker Engine on Ubuntu"
STEP_OS="all"
STEP_SUDO="linux"

docker_ready() { command_exists docker && docker info >/dev/null 2>&1; }

# Inside a macOS VM this is 0 unless nested virtualization is enabled (M3+ host, macOS 15+).
macos_virt_available() { [[ "$(sysctl -n kern.hv_support 2>/dev/null)" == 1 ]]; }

step_check() {
  load_brew || true
  if [[ "$WI_OS" == macos ]]; then export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"; fi
  docker_ready
}

docker_run_macos() {
  load_brew || die "Homebrew missing"
  if ! macos_virt_available; then
    log_warn "Hardware virtualization is not available here (kern.hv_support != 1), so Colima cannot start."
    log_warn "Inside a macOS VM this needs an M3+ host on macOS 15+ AND nested virtualization enabled"
    log_warn "in the VM settings (Parallels: Hardware > CPU & Memory > Advanced). Skipping Docker."
    return 0
  fi
  if ! colima status >/dev/null 2>&1; then
    wi_run colima start --cpu 4 --memory 8 --vm-type vz --mount-type virtiofs
  fi
  wi_run brew services start colima
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
  if [[ "$WI_DRY_RUN" != 1 ]] && ! docker_ready; then die "colima is up but 'docker info' fails"; fi
}

docker_run_linux() {
  local arch codename
  arch="$(dpkg --print-architecture)"
  # shellcheck source=/dev/null
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    wi_run sudo install -m 0755 -d /etc/apt/keyrings
    wi_run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    wi_run sudo chmod a+r /etc/apt/keyrings/docker.asc
  fi
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    if ! wi_dry "write /etc/apt/sources.list.d/docker.list ($codename, $arch)"; then
      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$arch" "$codename" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi
  fi
  wi_run sudo apt-get update -qq
  wi_run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  wi_run sudo usermod -aG docker "$USER"
  wi_run sudo systemctl enable --now docker
  if [[ "$WI_DRY_RUN" != 1 ]] && ! docker_ready; then
    log_warn "Docker installed. Log out and back in so the docker group applies; 'docker info' works after that."
  fi
}

step_run() {
  case "$WI_OS" in
    macos) docker_run_macos ;;
    linux) docker_run_linux ;;
  esac
}
