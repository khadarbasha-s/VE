#!/usr/bin/env bash
# =============================================================================
#  OpenCut – one-shot setup & run script
#
#  Checks requirements, installs every toolchain/dependency into a local
#  virtual environment (./.venv), then starts all services:
#
#    web      – TanStack Start / Vite frontend      http://localhost:5173
#    api      – Elysia on Cloudflare Workers        http://localhost:8787
#    desktop  – GPUI (Rust) desktop app            (opt-in: --desktop)
#
#  Everything that gets downloaded (Bun, Node if needed, Rust if needed, and
#  package caches) lives inside ./.venv – nothing is installed globally and no
#  shell rc files are modified. Project node_modules stay in each app folder.
#
#  Usage:
#    ./run.sh                 setup + run web & api
#    ./run.sh --desktop       also build & run the desktop app
#    ./run.sh --setup-only    install everything, don't start services
#    ./run.sh --check         only check requirements
#    ./run.sh --clean         delete ./.venv, node_modules and logs, then exit
#    ./run.sh --help
# =============================================================================
set -Eeuo pipefail

# ----------------------------------------------------------------------------- config
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/.venv"
LOG_DIR="$ROOT/.venv/logs"

# Versions pinned in .prototools (fallbacks if parsing fails)
BUN_VERSION="$(sed -nE 's/^bun *= *"([^"]+)".*/\1/p' "$ROOT/.prototools" 2>/dev/null || true)"
RUST_VERSION="$(sed -nE 's/^rust *= *"([^"]+)".*/\1/p' "$ROOT/.prototools" 2>/dev/null || true)"
BUN_VERSION="${BUN_VERSION:-1.3.11}"
RUST_VERSION="${RUST_VERSION:-stable}"
NODE_MIN_MAJOR=20          # vite 8 / wrangler 4 need Node >= 20
NODE_VENV_VERSION="22.12.0" # installed into .venv only if system node is missing/too old

WEB_PORT=5173
API_PORT=8787

RUN_DESKTOP=0
SETUP_ONLY=0
CHECK_ONLY=0

# ----------------------------------------------------------------------------- helpers
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_RED=$'\e[31m'; C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'; C_MAGENTA=$'\e[35m'
else
  C_RESET=; C_BOLD=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=; C_MAGENTA=
fi

step() { echo; echo "${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()   { echo "  ${C_GREEN}✔${C_RESET} $*"; }
warn() { echo "  ${C_YELLOW}!${C_RESET} $*"; }
fail() { echo "  ${C_RED}✘${C_RESET} $*" >&2; }
die()  { fail "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

for arg in "$@"; do
  case "$arg" in
    --desktop)    RUN_DESKTOP=1 ;;
    --setup-only) SETUP_ONLY=1 ;;
    --check)      CHECK_ONLY=1 ;;
    --clean)
      step "Cleaning"
      rm -rf "$VENV" "$ROOT/apps/web/node_modules" "$ROOT/apps/api/node_modules"
      ok "Removed .venv and node_modules"
      exit 0 ;;
    -h|--help)    usage ;;
    *) die "Unknown option: $arg (see --help)" ;;
  esac
done

# ----------------------------------------------------------------------------- platform
detect_platform() {
  case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) die "Unsupported OS: $(uname -s). Use Linux, macOS or WSL." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=x64 ;;
    arm64|aarch64) ARCH=aarch64 ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

# ----------------------------------------------------------------------------- 1. requirements
check_requirements() {
  step "Checking system requirements"
  local missing=()

  for cmd in curl unzip tar git; do
    if have "$cmd"; then ok "$cmd"; else fail "$cmd not found"; missing+=("$cmd"); fi
  done

  if have python3 && python3 -c 'import venv, ensurepip' 2>/dev/null; then
    ok "python3 $(python3 -c 'import sys;print(".".join(map(str,sys.version_info[:3])))') (with venv)"
  else
    fail "python3 with the 'venv' module is required (Debian/Ubuntu: sudo apt install python3-venv)"
    missing+=("python3-venv")
  fi

  if have node; then
    local major; major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if (( major >= NODE_MIN_MAJOR )); then
      ok "node $(node --version) (system)"
    else
      warn "node $(node --version) is older than v$NODE_MIN_MAJOR – v$NODE_VENV_VERSION will be installed into .venv"
    fi
  else
    warn "node not found – v$NODE_VENV_VERSION will be installed into .venv"
  fi

  if [[ -x "$VENV/bin/bun" ]]; then ok "bun $("$VENV/bin/bun" --version) (.venv)"
  else warn "bun $BUN_VERSION will be installed into .venv"; fi

  if (( RUN_DESKTOP )); then
    if [[ -x "$VENV/cargo/bin/cargo" ]]; then ok "rust (.venv)"
    else warn "rust $RUST_VERSION will be installed into .venv"; fi
    for cmd in cc cmake pkg-config; do
      if have "$cmd"; then ok "$cmd"; else fail "$cmd not found (needed to build the desktop app)"; missing+=("$cmd"); fi
    done
    if [[ "$OS" == linux ]]; then
      if have pkg-config; then
        for lib in fontconfig xkbcommon-x11 x11-xcb wayland-client vulkan; do
          if pkg-config --exists "$lib" 2>/dev/null; then ok "lib$lib"
          else fail "lib$lib dev package not found"; missing+=("lib$lib"); fi
        done
      fi
      if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        warn "No DISPLAY/WAYLAND_DISPLAY set – the desktop window cannot open here (headless?)"
      fi
    fi
  fi

  # Disk space (needs ~1.5 GB for web/api, ~5 GB more with the Rust desktop build)
  local free_mb; free_mb="$(df -Pm "$ROOT" | awk 'NR==2{print $4}')"
  local need_mb=1500; (( RUN_DESKTOP )) && need_mb=6500
  if (( free_mb >= need_mb )); then ok "disk space: ${free_mb} MB free"
  else warn "only ${free_mb} MB free – about ${need_mb} MB is recommended"; fi

  if (( ${#missing[@]} )); then
    echo
    fail "Missing requirements: ${missing[*]}"
    if (( RUN_DESKTOP )) && [[ "$OS" == linux ]]; then
      echo "    Debian/Ubuntu desktop deps:"
      echo "      sudo apt install build-essential cmake pkg-config libfontconfig-dev \\"
      echo "        libxkbcommon-x11-dev libx11-xcb-dev libwayland-dev libvulkan-dev libvulkan1"
    fi
    exit 1
  fi
  ok "All requirements satisfied"
}

# ----------------------------------------------------------------------------- 2. venv
setup_venv() {
  step "Preparing virtual environment at .venv"
  if [[ ! -f "$VENV/bin/activate" ]]; then
    python3 -m venv "$VENV"
    ok "Created .venv"
  else
    ok ".venv already exists"
  fi
  mkdir -p "$VENV/downloads" "$VENV/cache" "$LOG_DIR"

  # Route every tool and cache into the venv
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  export BUN_INSTALL="$VENV"
  export BUN_INSTALL_CACHE_DIR="$VENV/cache/bun"
  export npm_config_cache="$VENV/cache/npm"
  export PIP_CACHE_DIR="$VENV/cache/pip"
  export RUSTUP_HOME="$VENV/rustup"
  export CARGO_HOME="$VENV/cargo"
  export CARGO_TARGET_DIR="$ROOT/target"
  export XDG_CONFIG_HOME="$VENV/config"        # wrangler config / metrics opt-in
  export WRANGLER_SEND_METRICS=false
  export PATH="$VENV/bin:$CARGO_HOME/bin:$PATH"
  hash -r
}

# ----------------------------------------------------------------------------- 3. toolchains
install_node() {
  step "Node.js"
  local major=0
  have node && major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if (( major >= NODE_MIN_MAJOR )); then
    ok "Using node $(node --version) ($(command -v node))"
    return
  fi
  echo "  Installing node v$NODE_VENV_VERSION into .venv (via nodeenv)…"
  pip install --quiet --disable-pip-version-check nodeenv
  nodeenv --python-virtualenv --node="$NODE_VENV_VERSION" --prebuilt
  hash -r
  ok "node $(node --version) installed in .venv"
}

install_bun() {
  step "Bun $BUN_VERSION"
  if [[ -x "$VENV/bin/bun" && "$("$VENV/bin/bun" --version)" == "$BUN_VERSION" ]]; then
    ok "bun $BUN_VERSION already in .venv"
    return
  fi
  local target="bun-$OS-$ARCH"
  # Older x64 CPUs without AVX2 need the "baseline" build
  if [[ "$OS" == linux && "$ARCH" == x64 ]] && ! grep -q avx2 /proc/cpuinfo 2>/dev/null; then
    target="$target-baseline"
  fi
  local url="https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/$target.zip"
  local dl="$VENV/downloads/bun"
  rm -rf "$dl"; mkdir -p "$dl"
  echo "  Downloading $url"
  curl -fL --progress-bar -o "$dl/bun.zip" "$url" || die "Failed to download Bun"
  unzip -q -o "$dl/bun.zip" -d "$dl"
  install -m 755 "$dl/$target/bun" "$VENV/bin/bun"
  ln -sf bun "$VENV/bin/bunx"
  rm -rf "$dl"
  hash -r
  ok "bun $(bun --version) installed in .venv"
}

install_rust() {
  step "Rust $RUST_VERSION"
  if [[ -x "$CARGO_HOME/bin/rustup" ]]; then
    rustup toolchain install "$RUST_VERSION" --profile minimal >/dev/null
    rustup default "$RUST_VERSION" >/dev/null
    ok "rust $(rustc --version | awk '{print $2}') in .venv"
    return
  fi
  echo "  Installing rustup + Rust $RUST_VERSION into .venv…"
  curl -fsSL https://sh.rustup.rs -o "$VENV/downloads/rustup-init.sh"
  sh "$VENV/downloads/rustup-init.sh" -y --no-modify-path --profile minimal \
     --default-toolchain "$RUST_VERSION" >/dev/null
  rm -f "$VENV/downloads/rustup-init.sh"
  hash -r
  ok "rust $(rustc --version | awk '{print $2}') installed in .venv"
}

# ----------------------------------------------------------------------------- 4. dependencies
install_js_deps() {
  local app="$1"
  step "Installing dependencies for apps/$app"
  (
    cd "$ROOT/apps/$app"
    # A node_modules tree previously created by pnpm confuses bun – start fresh
    if [[ -d node_modules/.pnpm ]]; then
      warn "Removing pnpm-created node_modules"
      rm -rf node_modules
    fi
    bun install 2>&1 | sed 's/^/    /'
  ) || die "bun install failed for apps/$app"
  ok "apps/$app dependencies installed"
}

setup_env_files() {
  if [[ -f "$ROOT/.env.example" && ! -f "$ROOT/.env.local" ]]; then
    cp "$ROOT/.env.example" "$ROOT/.env.local"
    ok "Created .env.local from .env.example"
  fi
}

# ----------------------------------------------------------------------------- 5. run services
PIDS=()
NAMES=()

port_in_use() {
  if have ss; then ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"
  else (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; fi
}

start_service() {
  local name="$1" color="$2" dir="$3"; shift 3
  local log="$LOG_DIR/$name.log"
  : > "$log"
  (
    cd "$dir"
    # setsid gives each service its own process group so we can stop it cleanly
    exec setsid "$@" > >(tee -a "$log" | sed -u "s/^/${color}[$name]${C_RESET} /") 2>&1
  ) &
  PIDS+=("$!")
  NAMES+=("$name")
  ok "Started $name (pid $!, log: .venv/logs/$name.log)"
}

wait_for_http() {
  local name="$1" url="$2" timeout="${3:-120}"
  local i
  for ((i = 0; i < timeout; i++)); do
    if curl -s -o /dev/null --max-time 2 "$url"; then
      ok "$name is up → $url"
      return 0
    fi
    sleep 1
  done
  warn "$name did not respond at $url within ${timeout}s – check .venv/logs/$name.log"
}

cleanup() {
  trap - INT TERM EXIT
  echo
  step "Stopping services"
  local pid
  for pid in "${PIDS[@]}"; do
    # kill the whole process group (vite / wrangler / workerd children)
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in "${PIDS[@]}"; do
    kill -KILL -- "-$pid" 2>/dev/null || true
  done
  ok "All services stopped"
}

run_services() {
  step "Starting services"
  for p in $WEB_PORT $API_PORT; do
    port_in_use "$p" && die "Port $p is already in use – stop the process using it first"
  done

  trap 'cleanup; exit 130' INT
  trap 'cleanup; exit 143' TERM
  trap cleanup EXIT

  start_service api "$C_MAGENTA" "$ROOT/apps/api" \
    bun run dev --port "$API_PORT" --ip 0.0.0.0
  start_service web "$C_CYAN" "$ROOT/apps/web" \
    bun run dev --host 0.0.0.0
  if (( RUN_DESKTOP )); then
    start_service desktop "$C_YELLOW" "$ROOT/apps/desktop" cargo run
  fi

  wait_for_http api "http://localhost:$API_PORT" 90
  wait_for_http web "http://localhost:$WEB_PORT" 120

  echo
  echo "${C_BOLD}${C_GREEN}OpenCut is running${C_RESET}"
  echo "  Frontend : http://localhost:$WEB_PORT"
  echo "  API      : http://localhost:$API_PORT"
  (( RUN_DESKTOP )) && echo "  Desktop  : building/running (first build compiles GPUI – this takes a while)"
  echo "  Logs     : .venv/logs/"
  echo "  Press Ctrl+C to stop everything."
  echo

  # Exit as soon as any service dies, then cleanup() stops the rest
  local status=0
  wait -n "${PIDS[@]}" || status=$?
  local i
  for i in "${!PIDS[@]}"; do
    if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
      fail "Service '${NAMES[$i]}' exited (code $status) – see .venv/logs/${NAMES[$i]}.log"
    fi
  done
  exit "$status"
}

# ----------------------------------------------------------------------------- main
main() {
  cd "$ROOT"
  echo "${C_BOLD}OpenCut setup & run${C_RESET}  (root: $ROOT)"
  detect_platform
  check_requirements
  (( CHECK_ONLY )) && exit 0

  setup_venv
  install_node
  install_bun
  (( RUN_DESKTOP )) && install_rust
  setup_env_files
  install_js_deps api
  install_js_deps web

  if (( SETUP_ONLY )); then
    step "Setup complete"
    ok "Run ./run.sh to start the services"
    exit 0
  fi

  run_services
}

main "$@"
