#!/usr/bin/env bash
# ui-clone-skills installer — bootstraps system deps and registers the plugin.
#
# Usage (one of):
#   curl -LsSf https://raw.githubusercontent.com/voidmatcha/ui-clone-skills/main/install.sh | bash
#   git clone https://github.com/voidmatcha/ui-clone-skills.git && cd ui-clone-skills && ./install.sh
#
# Idempotent: every step detects existing installs and skips. Safe to re-run.
#
# Flags:
#   --no-deps        skip system dependency installs (uv/ffmpeg/imagemagick/dssim/agent-browser)
#   --no-marketplace skip Claude Code marketplace registration
#   --yes            assume yes for prompts (e.g. apt sudo install)
#
# Env:
#   UI_CLONE_REPO    git URL to clone (default: https://github.com/voidmatcha/ui-clone-skills.git)
#   UI_CLONE_REF     branch/tag/sha to checkout after clone (default: leave on default branch)
#   INSTALL_DIR      where to clone when running via curl-pipe (default: ~/.local/share/ui-clone-skills)
set -euo pipefail

# --- curl-pipe bootstrap -----------------------------------------------------
# When piped from curl, BASH_SOURCE[0] is unset or points at a non-file. In that
# case clone the repo to INSTALL_DIR and re-exec the on-disk copy so the rest of
# the script runs against a real working tree (uv sync, marketplace add, etc.).
_self="${BASH_SOURCE[0]:-}"
if [ -z "$_self" ] || [ ! -f "$_self" ]; then
  REPO_URL="${UI_CLONE_REPO:-https://github.com/voidmatcha/ui-clone-skills.git}"
  TARGET="${INSTALL_DIR:-$HOME/.local/share/ui-clone-skills}"
  if ! command -v git >/dev/null 2>&1; then
    echo "git not found — install git and re-run." >&2
    exit 1
  fi
  if [ -d "$TARGET/.claude-plugin" ]; then
    echo "==> Updating existing checkout at $TARGET"
    git -C "$TARGET" fetch --quiet origin
    git -C "$TARGET" pull --ff-only --quiet || {
      echo "  ! local changes in $TARGET prevent fast-forward; leaving as-is" >&2
    }
  elif [ -e "$TARGET" ]; then
    echo "Refusing to clone: $TARGET exists but is not a ui-clone-skills checkout." >&2
    echo "Set INSTALL_DIR=<other path>, or remove/rename $TARGET, then re-run." >&2
    exit 1
  else
    echo "==> Cloning $REPO_URL → $TARGET"
    mkdir -p "$(dirname "$TARGET")"
    git clone --quiet "$REPO_URL" "$TARGET"
  fi
  if [ -n "${UI_CLONE_REF:-}" ]; then
    git -C "$TARGET" checkout --quiet "$UI_CLONE_REF"
  fi
  exec bash "$TARGET/install.sh" "$@"
fi

REPO_ROOT="$(cd "$(dirname "$_self")" && pwd)"
MARKETPLACE_NAME="voidmatcha"
PLUGIN_NAME="ui-clone-skills"

NO_DEPS=0
NO_MARKETPLACE=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --no-deps) NO_DEPS=1 ;;
    --no-marketplace) NO_MARKETPLACE=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help)
      awk 'NR==1{next} /^set -euo/{exit} {sub(/^# ?/,""); print}' "$0"
      exit 0
      ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_SKIP=$'\033[2m'; C_ACT=$'\033[36m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_RST=$'\033[0m'
else
  C_OK=""; C_SKIP=""; C_ACT=""; C_WARN=""; C_ERR=""; C_RST=""
fi
ok()   { printf "  %s✓%s %s\n" "$C_OK" "$C_RST" "$*"; }
skip() { printf "  %s✓ %s (already present)%s\n" "$C_SKIP" "$*" "$C_RST"; }
act()  { printf "  %s→%s %s\n" "$C_ACT" "$C_RST" "$*"; }
warn() { printf "  %s! %s%s\n" "$C_WARN" "$*" "$C_RST"; }
err()  { printf "  %s✗ %s%s\n" "$C_ERR" "$*" "$C_RST" >&2; }
section() { printf "\n%s== %s ==%s\n" "$C_ACT" "$*" "$C_RST"; }

UNAME="$(uname -s)"
case "$UNAME" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *) err "Unsupported OS: $UNAME (only macOS and Linux are supported)"; exit 1 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }

# Linux uses sudo for apt; macOS Homebrew does not.
sudo_run() {
  if [ "$OS" = "linux" ] && [ "$(id -u)" -ne 0 ]; then
    if [ "$ASSUME_YES" -eq 0 ]; then
      warn "About to run: sudo $*"
    fi
    sudo "$@"
  else
    "$@"
  fi
}

apt_install() {
  if ! have apt-get; then
    err "apt-get not found. Install '$*' manually for your distro."
    return 1
  fi
  sudo_run apt-get update -y >/dev/null
  sudo_run apt-get install -y "$@"
}

ensure_uv() {
  if have uv; then skip "uv $(uv --version | awk '{print $2}')"; return; fi
  act "Installing uv (Python package manager)"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  if ! have uv; then
    # uv installs to ~/.local/bin or ~/.cargo/bin depending on platform; surface the next step.
    warn "uv installed but not on PATH yet. Add ~/.local/bin (or ~/.cargo/bin) to PATH and re-run."
    return 1
  fi
  ok "uv $(uv --version | awk '{print $2}')"
}

ensure_ffmpeg() {
  if have ffmpeg; then skip "ffmpeg"; return; fi
  act "Installing ffmpeg"
  if [ "$OS" = "mac" ]; then
    brew install ffmpeg
  else
    apt_install ffmpeg
  fi
  ok "ffmpeg $(ffmpeg -version | head -1 | awk '{print $3}')"
}

ensure_imagemagick() {
  if have magick || have convert; then skip "imagemagick"; return; fi
  act "Installing imagemagick"
  if [ "$OS" = "mac" ]; then
    brew install imagemagick
  else
    apt_install imagemagick
  fi
  ok "imagemagick"
}

ensure_dssim() {
  if have dssim; then skip "dssim"; return; fi
  act "Installing dssim"
  if [ "$OS" = "mac" ]; then
    brew install dssim
  elif have cargo; then
    cargo install dssim
  else
    err "dssim install requires either Homebrew (mac) or cargo (linux)."
    err "Install Rust toolchain first: https://rustup.rs/  — then re-run this script."
    return 1
  fi
  ok "dssim"
}

ensure_node_npm() {
  if have npm; then skip "npm $(npm --version)"; return; fi
  err "npm not found. Install Node.js 18+ (https://nodejs.org/) and re-run."
  return 1
}

ensure_agent_browser() {
  if have agent-browser; then skip "agent-browser"; return; fi
  if npm list -g --depth=0 agent-browser >/dev/null 2>&1; then skip "agent-browser (via npm -g)"; return; fi
  act "Installing agent-browser globally via npm"
  npm install -g agent-browser
  ok "agent-browser"
}

uv_sync() {
  if [ ! -f "$REPO_ROOT/pyproject.toml" ]; then
    warn "No pyproject.toml at $REPO_ROOT — skipping uv sync."
    return
  fi
  act "Resolving Python deps (uv sync)"
  ( cd "$REPO_ROOT" && uv sync --quiet )
  ok "Python deps resolved"
}

register_marketplace() {
  if ! have claude; then
    warn "Claude Code CLI ('claude') not found on PATH — skipping marketplace registration."
    warn "Install Claude Code, then re-run with --no-deps to register the plugin."
    return
  fi
  # `claude plugin marketplace add` is idempotent in recent CLI versions; tolerate either outcome.
  act "Registering local repo as marketplace '$MARKETPLACE_NAME'"
  if claude plugin marketplace add "$REPO_ROOT" >/dev/null 2>&1; then
    ok "marketplace '$MARKETPLACE_NAME' registered"
  else
    skip "marketplace '$MARKETPLACE_NAME' already registered (or CLI declined re-add)"
  fi
}

main() {
  section "ui-clone-skills installer (OS: $OS, repo: $REPO_ROOT)"

  if [ "$NO_DEPS" -eq 0 ]; then
    section "System dependencies"
    if [ "$OS" = "mac" ] && ! have brew; then
      err "Homebrew not found. Install from https://brew.sh/ and re-run."
      exit 1
    fi
    ensure_uv
    ensure_ffmpeg
    ensure_imagemagick
    ensure_dssim
    ensure_node_npm
    ensure_agent_browser

    section "Python deps"
    uv_sync
  else
    warn "--no-deps: skipping system dependency bootstrap"
  fi

  if [ "$NO_MARKETPLACE" -eq 0 ]; then
    section "Claude Code plugin"
    register_marketplace
  fi

  section "Done"
  cat <<EOF
  Next step (run inside Claude Code):

      /plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}

  Verify deps:
      agent-browser --version && uv --version && ffmpeg -version | head -1
EOF
}

main "$@"
