#!/usr/bin/env bash
# ============================================================================
# LazyVim One-Shot Installer
# Sets up: Neovim (>= 0.9), JetBrainsMono Nerd Font, LazyVim starter config
#
# Usage:
#   ./install-lazyvim.sh            # full install
#   ./install-lazyvim.sh --font     # only install the Nerd Font
#   FORCE=1 ./install-lazyvim.sh    # skip version/idempotency guards
#
# Safe to re-run: existing configs are backed up, installs are skipped
# when already present and up to date.
# ============================================================================
set -euo pipefail

FONT_NAME="JetBrainsMono"
FONT_REPO="ryanoasis/nerd-fonts"
FONT_VERSION="v3.2.1"
FONT_DIR="${HOME}/.local/share/fonts"
LAZYNVIM_STARTER="https://github.com/LazyVim/starter"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_MIN_MAJOR=0
NVIM_MIN_MINOR=9

log()  { printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# Detect OS + package manager
# ----------------------------------------------------------------------------
OS="$(uname -s)"
PM=""
SUDO=""

if [[ "$OS" == "Linux" ]]; then
  if command -v dnf >/dev/null 2>&1; then    PM="dnf"
  elif command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v pacman >/dev/null 2>&1; then  PM="pacman"
  elif command -v zypper >/dev/null 2>&1; then  PM="zypper"
  else die "Unsupported Linux distro: no dnf/apt/pacman/zypper found."
  fi
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo required for package installs"
    SUDO="sudo"
  fi
  log "Detected Linux with package manager: $PM"
elif [[ "$OS" == "Darwin" ]]; then
  command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install it from https://brew.sh first."
  PM="brew"
  log "Detected macOS with Homebrew"
else
  die "Unsupported OS: $OS"
fi

# ----------------------------------------------------------------------------
# Step 1: install build prerequisites + neovim
# ----------------------------------------------------------------------------
install_packages() {
  log "Installing packages: $*"
  case "$PM" in
    dnf)    $SUDO dnf install -y "$@" ;;
    apt)    $SUDO apt-get update -y && $SUDO apt-get install -y "$@" ;;
    pacman) $SUDO pacman -Sy --noconfirm --needed "$@" ;;
    zypper) $SUDO zypper install -y "$@" ;;
    brew)   brew install "$@" ;;
  esac
}

# git/curl/tar/unzip are needed regardless; ripgrep + fd are LazyVim-recommended
NEEDED=(git curl tar unzip ripgrep fd-find)
[[ "$PM" == "pacman" ]] && NEEDED=(git curl tar unzip ripgrep fd)   # arch names fd-find "fd"
install_packages "${NEEDED[@]}"

have_good_nvim() {
  command -v nvim >/dev/null 2>&1 || return 1
  local v
  v="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)" || return 1
  local major="${v%%.*}" minor="${v##*.}"
  (( major > NVIM_MIN_MAJOR || (major == NVIM_MIN_MAJOR && minor >= NVIM_MIN_MINOR) ))
}

if have_good_nvim && [[ "${FORCE:-0}" != "1" ]]; then
  log "Neovim $(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+') already installed — skipping"
elif [[ "$PM" == "brew" ]]; then
  install_packages neovim
elif [[ "$OS" == "Linux" ]] && command -v nvim >/dev/null 2>&1; then
  # distro nvim exists but too old (common on Debian/Ubuntu) -> appimage
  warn "Distro Neovim is too old (< ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR}). Installing Neovim stable via AppImage."
  $SUDO mkdir -p /usr/local/bin
  curl -sL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage \
    -o /tmp/nvim.appimage
  chmod +x /tmp/nvim.appimage
  # AppImages need libfuse2; extract instead so it runs everywhere
  /tmp/nvim.appimage --appimage-extract >/dev/null
  $SUDO mv /tmp/nvim.appimage /usr/local/bin/nvim.appimage 2>/dev/null || true
  $SUDO rm -rf /opt/nvim.appimage
  $SUDO mv squashfs-root /opt/nvim.appimage
  $SUDO ln -sf /opt/nvim.appimage/AppRun /usr/local/bin/nvim
  rm -f /tmp/nvim.appimage
  have_good_nvim || die "AppImage install failed; please install Neovim >= 0.9 manually"
else
  # no nvim at all: try distro package first, fall back to AppImage if too old
  install_packages neovim
  if ! have_good_nvim && [[ "$OS" == "Linux" ]]; then
    warn "Distro neovim still too old, falling back to AppImage"
    exec "$0" "$@"   # re-run; second pass takes the AppImage branch above
  fi
fi
log "Neovim OK: $(nvim --version | head -1)"

# ----------------------------------------------------------------------------
# Step 2: JetBrainsMono Nerd Font (Linux only needs it locally; macOS: skip —
# terminal apps usually bundle their own font)
# ----------------------------------------------------------------------------
install_font() {
  if [[ "$OS" == "Darwin" ]]; then
    install_packages --cask font-jetbrains-mono-nerd-font
    return
  fi
  mkdir -p "$FONT_DIR"
  local zip_url="https://github.com/${FONT_REPO}/releases/download/${FONT_VERSION}/${FONT_NAME}.zip"
  local tmp; tmp="$(mktemp -d)"
  log "Downloading ${FONT_NAME} Nerd Font ${FONT_VERSION}..."
  curl -sL "$zip_url" -o "$tmp/font.zip"
  unzip -qo "$tmp/font.zip" -d "$tmp/font"
  # install only the main regular/mono variants (skip "Mono" dupes & extras)
  find "$tmp/font" -maxdepth 1 -name '*.ttf' \
       ! -name '*Propo*' ! -name '*CodeNewRoman*' ! -name '*NerdFontMono*' \
       ! -name '*ExtraLight*' ! -name '*Thin*' -exec cp -f {} "$FONT_DIR/" \;
  rm -rf "$tmp"
  fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  log "Font installed to $FONT_DIR"
}

if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && [[ "${FORCE:-0}" != "1" ]]; then
  log "JetBrainsMono Nerd Font already installed — skipping"
else
  install_font
fi

# ----------------------------------------------------------------------------
# Step 3: LazyVim starter config
# ----------------------------------------------------------------------------
backup_existing() {
  if [[ -e "$NVIM_CONFIG" && ! -d "${NVIM_CONFIG}.bak" ]]; then
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    mv "$NVIM_CONFIG" "${NVIM_CONFIG}.bak.${stamp}"
    warn "Existing config backed up to ${NVIM_CONFIG}.bak.${stamp}"
  elif [[ -d "${NVIM_CONFIG}.bak" ]]; then
    # a prior backup exists and config dir is gone or stale — just remove
    rm -rf "$NVIM_CONFIG"
  fi
}

if [[ -f "$NVIM_CONFIG/init.lua" ]] && grep -q "LazyVim" "$NVIM_CONFIG"/lua/config/lazy.lua 2>/dev/null \
   && [[ "${FORCE:-0}" != "1" ]]; then
  log "LazyVim config already present at $NVIM_CONFIG — skipping"
else
  backup_existing
  log "Cloning LazyVim starter into $NVIM_CONFIG"
  git clone --depth 1 "$LAZYNVIM_STARTER" "$NVIM_CONFIG"
  rm -rf "$NVIM_CONFIG/.git"
  log "LazyVim cloned. Plugin bootstrap happens on first launch."
fi

# ----------------------------------------------------------------------------
# Done — headless warm-up so the first real launch isn't a wall of installs
# ----------------------------------------------------------------------------
log "Warming up plugin sync (this can take a minute)..."
nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || \
  warn "Headless sync had issues; run ':Lazy sync' inside nvim to retry"

cat <<EOF

  ✔ Setup complete!

  Next steps:
    1. Set your terminal font to "JetBrainsMono Nerd Font"
    2. Run:  nvim      (first launch may take a moment for Treesitter)
    3. Press <space> to open LazyVim's which-key menu

EOF
