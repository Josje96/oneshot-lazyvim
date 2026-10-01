# oneshot-lazyvim

One script, one command: Neovim + JetBrainsMono Nerd Font + LazyVim, ready to use on
any Linux distro (dnf / apt / pacman / zypper) or macOS (Homebrew).

## One-shot install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Josje96/oneshot-lazyvim/main/install.sh)
```

Or clone first if you prefer:

```bash
git clone https://github.com/Josje96/oneshot-lazyvim.git && cd oneshot-lazyvim && ./install.sh
```

## What it installs

| Component | Detail |
|-----------|--------|
| Neovim    | >= 0.9 via your package manager; falls back to the official AppImage if the distro ships an old version |
| Font      | [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts) v3.2.1 → `~/.local/share/fonts` (Homebrew cask on macOS) |
| LazyVim   | Official [starter](https://github.com/LazyVim/starter) cloned into `~/.config/nvim`, plugin sync warmed up headlessly |
| Extras    | `ripgrep` + `fd` (LazyVim's recommended fuzzy-finders), plus `git curl tar unzip` |

## After installing

1. Set your terminal font to **JetBrainsMono Nerd Font**
2. Run `nvim` — press `<Space>` to open the which-key menu
3. Optional: `:LazyExtras` to toggle language packs (TypeScript, Python, Go, ...)

## Safety

- **Idempotent** — safe to re-run; already-installed pieces are skipped.
- **Non-destructive** — an existing `~/.config/nvim` is backed up to
  `~/.config/nvim.bak.<timestamp>`, never deleted.
- Requires `sudo` only for system package installs (not needed on macOS).

## Flags

```bash
FORCE=1 ./install.sh     # reinstall even if everything looks up to date
./install.sh             # normal run
```
