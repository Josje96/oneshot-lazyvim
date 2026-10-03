#!/usr/bin/env bash
# ============================================================================
# LazyVim One-Shot Installer
# Sets up: Neovim (>= 0.11), JetBrainsMono Nerd Font, LazyVim starter config,
# and every LazyVim dependency (lazygit, tree-sitter-cli, C compiler, fzf,
# ripgrep, fd, node/npm, python3, clipboard tools)
#
# Usage:
#   ./install.sh            # full install
#   ./install.sh --font     # only install the Nerd Font
#   FORCE=1 ./install.sh    # skip version/idempotency guards
#
# Safe to re-run: existing configs are backed up, installs are skipped
# when already present and up to date.
# ============================================================================
set -euo pipefail

FONT_NAME="JetBrainsMono"
FONT_REPO="ryanoasis/nerd-fonts"
FONT_VERSION="v3.5.1"
FONT_DIR="${HOME}/.local/share/fonts"
LAZYNVIM_STARTER="https://github.com/LazyVim/starter"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
# LazyVim (v15+) requires Neovim >= 0.11.2
NVIM_MIN_MAJOR=0
NVIM_MIN_MINOR=11

FONT_ONLY=0

log()  { printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --font) FONT_ONLY=1 ;;
    *) die "Unknown argument: $arg (supported: --font)" ;;
  esac
done

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
    if [[ "$FONT_ONLY" == "1" ]] && command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
      log "Font-only install with curl/unzip present — no sudo needed"
    else
      # Fail early with a clear message when sudo can't prompt (piped/non-interactive runs)
      if ! sudo -n true 2>/dev/null && ! (exec 3<>/dev/tty) 2>/dev/null; then
        die "sudo needs a password but there is no terminal to prompt on — run this script in an interactive terminal (e.g. curl -fsSL <url> -o install.sh && bash install.sh), or run 'sudo -v' first"
      fi
      SUDO="sudo"
    fi
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
    apt)    # A broken third-party repo shouldn't abort the whole install;
            # apt-get install can still use the existing package indexes.
            $SUDO apt-get update -y || warn "apt-get update failed (a third-party repo on this system may be misconfigured) — trying to install with cached indexes"
            $SUDO apt-get install -y "$@" ;;
    pacman) $SUDO pacman -Sy --noconfirm --needed "$@" ;;
    zypper) $SUDO zypper install -y "$@" ;;
    brew)   brew install "$@" ;;
  esac
}

# Install the whole list in one go; if that fails (a name missing on this
# distro release), retry one at a time so a single bad name doesn't sink the rest.
install_packages_lenient() {
  install_packages "$@" && return 0
  warn "Bulk install failed — retrying packages one at a time"
  local p
  for p in "$@"; do
    install_packages "$p" || warn "Could not install '$p' — skipping"
  done
}

# Everything LazyVim (and the plugins it ships) expects on PATH:
#   git curl tar unzip gzip wget  — lazy.nvim, blink.cmp, Mason downloads
#   ripgrep fd fzf                — pickers / live grep
#   C compiler + make             — nvim-treesitter parser builds
#   node/npm, python3 + venv      — Mason-installed LSPs, formatters, linters
#   xclip / wl-clipboard          — system clipboard on X11 / Wayland
case "$PM" in
  apt)    NEEDED=(git curl wget tar unzip gzip ripgrep fd-find fzf build-essential
                  nodejs npm python3 python3-pip python3-venv xclip wl-clipboard) ;;
  dnf)    NEEDED=(git curl wget tar unzip gzip ripgrep fd-find fzf gcc gcc-c++ make
                  nodejs npm python3 python3-pip xclip wl-clipboard) ;;
  pacman) NEEDED=(git curl wget tar unzip gzip ripgrep fd fzf base-devel
                  nodejs npm python python-pip xclip wl-clipboard lazygit tree-sitter-cli) ;;
  zypper) NEEDED=(git curl wget tar unzip gzip ripgrep fd fzf gcc gcc-c++ make
                  nodejs-default npm-default python3 python3-pip xclip wl-clipboard) ;;
  brew)   NEEDED=(git wget ripgrep fd fzf lazygit tree-sitter-cli node python) ;;
esac
# Don't shadow an existing Node (nvm, fnm, volta, ...) with the distro's older one
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  filtered=()
  for p in "${NEEDED[@]}"; do
    case "$p" in nodejs|npm|nodejs-default|npm-default|node) ;; *) filtered+=("$p") ;; esac
  done
  NEEDED=("${filtered[@]}")
fi
if [[ "$FONT_ONLY" != "1" ]]; then
  install_packages_lenient "${NEEDED[@]}"

  # Debian/Ubuntu name the fd binary "fdfind"; LazyVim expects "fd"
  if [[ "$PM" == "apt" ]] && command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    $SUDO mkdir -p /usr/local/bin
    $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    log "Symlinked fdfind -> /usr/local/bin/fd"
  fi

  # macOS gets its C compiler from the Xcode Command Line Tools
  if [[ "$OS" == "Darwin" ]] && ! xcode-select -p >/dev/null 2>&1; then
    warn "Xcode Command Line Tools missing (needed to compile Treesitter parsers) — run: xcode-select --install"
  fi
fi

# ----------------------------------------------------------------------------
# Step 1b: lazygit + tree-sitter-cli from upstream releases (distro packages
# are missing or too old on most non-Arch Linux distros)
# ----------------------------------------------------------------------------
# nvim-treesitter (main) needs tree-sitter-cli >= 0.26.1
TS_MIN_MAJOR=0
TS_MIN_MINOR=26
TS_MIN_PATCH=1

latest_tag() {  # resolves the /releases/latest redirect — avoids API rate limits
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/tag/||'
}

install_lazygit_release() {
  local arch
  case "$(uname -m)" in
    x86_64)  arch="x86_64" ;;
    aarch64) arch="arm64" ;;
    *) warn "No lazygit binary for $(uname -m) — skipping"; return 0 ;;
  esac
  local tag; tag="$(latest_tag jesseduffield/lazygit)" || { warn "Could not resolve lazygit release — skipping"; return 0; }
  local tmp; tmp="$(mktemp -d)"
  log "Installing lazygit ${tag} from GitHub releases"
  if curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${tag#v}_linux_${arch}.tar.gz" \
       | tar -xz -C "$tmp" lazygit; then
    $SUDO mkdir -p /usr/local/bin
    $SUDO install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  else
    warn "lazygit download failed — skipping"
  fi
  rm -rf "$tmp"
}

have_good_treesitter() {
  command -v tree-sitter >/dev/null 2>&1 || return 1
  local v
  v="$(tree-sitter --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" || return 1
  [[ -n "$v" ]] || return 1
  local major minor patch
  IFS=. read -r major minor patch <<<"$v"
  (( major > TS_MIN_MAJOR ||
     (major == TS_MIN_MAJOR && (minor > TS_MIN_MINOR ||
       (minor == TS_MIN_MINOR && patch >= TS_MIN_PATCH))) ))
}

install_treesitter_release() {
  local arch
  case "$(uname -m)" in
    x86_64)  arch="x64" ;;
    aarch64) arch="arm64" ;;
    *) warn "No tree-sitter binary for $(uname -m) — skipping"; return 0 ;;
  esac
  local tmp; tmp="$(mktemp -d)"
  log "Installing tree-sitter-cli from GitHub releases"
  if curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${arch}.gz" \
       | gunzip > "$tmp/tree-sitter"; then
    $SUDO mkdir -p /usr/local/bin
    $SUDO install -m 0755 "$tmp/tree-sitter" /usr/local/bin/tree-sitter
    hash -r
  else
    warn "tree-sitter-cli download failed — skipping"
  fi
  rm -rf "$tmp"
}

if [[ "$FONT_ONLY" != "1" && "$OS" == "Linux" ]]; then
  if command -v lazygit >/dev/null 2>&1 && [[ "${FORCE:-0}" != "1" ]]; then
    log "lazygit already installed — skipping"
  else
    install_lazygit_release
  fi

  if have_good_treesitter && [[ "${FORCE:-0}" != "1" ]]; then
    log "tree-sitter-cli $(tree-sitter --version | grep -oE '[0-9.]+' | head -1) already installed — skipping"
  else
    install_treesitter_release
    have_good_treesitter || warn "tree-sitter-cli ${TS_MIN_MAJOR}.${TS_MIN_MINOR}.${TS_MIN_PATCH}+ not available — Treesitter parsers won't build"
  fi
fi
have_good_nvim() {
  command -v nvim >/dev/null 2>&1 || return 1
  local v
  v="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)" || return 1
  local major="${v%%.*}" minor="${v##*.}"
  (( major > NVIM_MIN_MAJOR || (major == NVIM_MIN_MAJOR && minor >= NVIM_MIN_MINOR) ))
}

install_nvim_appimage() {
  local arch
  case "$(uname -m)" in
    x86_64)  arch="x86_64" ;;
    aarch64) arch="arm64" ;;
    *) die "Unsupported architecture for Neovim AppImage: $(uname -m)" ;;
  esac
  warn "Installing Neovim stable via official AppImage."
  local tmp; tmp="$(mktemp -d)"
  curl -sL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch}.appimage" \
    -o "$tmp/nvim.appimage"
  chmod +x "$tmp/nvim.appimage"
  # AppImages need libfuse2 at runtime; extract instead so it runs everywhere
  (cd "$tmp" && ./nvim.appimage --appimage-extract >/dev/null)
  $SUDO rm -rf /opt/nvim.appimage
  $SUDO mv "$tmp/squashfs-root" /opt/nvim.appimage
  $SUDO mkdir -p /usr/local/bin
  $SUDO ln -sf /opt/nvim.appimage/AppRun /usr/local/bin/nvim
  rm -rf "$tmp"
}

if [[ "$FONT_ONLY" == "1" ]]; then
  : # font-only mode: nvim step is skipped
elif have_good_nvim && [[ "${FORCE:-0}" != "1" ]]; then
  log "Neovim $(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+') already installed — skipping"
elif [[ "$PM" == "brew" ]]; then
  install_packages neovim
else
  # no suitable nvim: try the distro package, then fall back to the AppImage
  if ! command -v nvim >/dev/null 2>&1; then
    install_packages neovim
  fi
  if ! have_good_nvim && [[ "$OS" == "Linux" ]]; then
    install_nvim_appimage
  fi
fi
if [[ "$FONT_ONLY" != "1" ]]; then
  have_good_nvim || die "Neovim ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR}+ install failed; please install it manually"
  log "Neovim OK: $(nvim --version | head -1)"
fi

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

if [[ "$FONT_ONLY" == "1" ]]; then
  # --font runs without sudo when curl/unzip are already present
  missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v unzip >/dev/null 2>&1 || missing+=(unzip)
  if ((${#missing[@]})); then
    warn "Installing missing download tools: ${missing[*]}"
    install_packages "${missing[@]}"
  fi
  install_font
  exit 0
fi

if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && [[ "${FORCE:-0}" != "1" ]]; then
  log "JetBrainsMono Nerd Font already installed — skipping"
else
  install_font
fi

# ----------------------------------------------------------------------------
# Step 3: LazyVim starter config
# ----------------------------------------------------------------------------
backup_existing() {
  if [[ -e "$NVIM_CONFIG" ]]; then
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    mv "$NVIM_CONFIG" "${NVIM_CONFIG}.bak.${stamp}"
    warn "Existing config backed up to ${NVIM_CONFIG}.bak.${stamp}"
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
# Step 3b: quiet :checkhealth noise (runs on existing configs too)
#   - LazyVim needs no luarocks plugins, so lazy's hererocks check only errors
#   - the python3/node/perl remote-plugin providers are unused by LazyVim
# ----------------------------------------------------------------------------
LAZY_LUA="$NVIM_CONFIG/lua/config/lazy.lua"
OPTIONS_LUA="$NVIM_CONFIG/lua/config/options.lua"

if [[ -f "$LAZY_LUA" ]] && ! grep -q "rocks" "$LAZY_LUA"; then
  if grep -q 'require("lazy").setup({' "$LAZY_LUA"; then
    awk '{ print } /require\("lazy"\)\.setup\(\{/ { print "  rocks = { enabled = false }," }' \
      "$LAZY_LUA" > "$LAZY_LUA.tmp" && mv "$LAZY_LUA.tmp" "$LAZY_LUA"
    log "Disabled luarocks support in $LAZY_LUA"
  else
    warn "Couldn't find lazy setup call in $LAZY_LUA — add 'rocks = { enabled = false }' manually"
  fi
fi

if [[ -d "$(dirname "$OPTIONS_LUA")" ]] && ! grep -q "loaded_python3_provider" "$OPTIONS_LUA" 2>/dev/null; then
  cat >> "$OPTIONS_LUA" <<'LUA'

-- Remote-plugin providers aren't used by LazyVim; disabling them silences :checkhealth
vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
LUA
  log "Disabled unused providers in $OPTIONS_LUA"
fi

# ----------------------------------------------------------------------------
# Done — headless warm-up so the first real launch isn't a wall of installs
# ----------------------------------------------------------------------------
log "Warming up plugin sync (this can take a minute)..."
nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || \
  warn "Headless sync had issues; run ':Lazy sync' inside nvim to retry"

# ----------------------------------------------------------------------------
# Dependency report
# ----------------------------------------------------------------------------
report() {  # report <label> <command>...  — first command found wins
  local label="$1"; shift
  local c
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then
      printf '  \033[1;32m✔\033[0m %-14s %s\n' "$label" "$(command -v "$c")"
      return
    fi
  done
  printf '  \033[1;31m✘\033[0m %-14s missing\n' "$label"
}

printf '\n  Dependencies:\n'
report nvim nvim
report git git
report curl curl
report ripgrep rg
report fd fd
report fzf fzf
report lazygit lazygit
report tree-sitter tree-sitter
report "C compiler" cc gcc clang
report node node
report npm npm
report python3 python3
if [[ "$OS" == "Linux" ]]; then
  report clipboard wl-copy xclip
fi

cat <<EOF

  ✔ Setup complete!

  Next steps:
    1. Set your terminal font to "JetBrainsMono Nerd Font"
    2. Run:  nvim      (first launch may take a moment for Treesitter)
    3. Press <space> to open LazyVim's which-key menu

EOF
