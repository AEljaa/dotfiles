# dotfiles

My Neovim + tmux setup. Works on **macOS**, **Linux** and **Windows (through WSL)**.
The OS is detected automatically (`nvim/lua/adameljaa/platform.lua`, and `uname` checks
in tmux), so Mac-only parts switch to something that works on the other systems.

Inside nvim, **`Space ?`** lists every shortcut in plain English.

| Folder | What it is |
|---|---|
| `nvim/` | Neovim config (plugins via packer): LSP + autocomplete, Telescope search, oil / file tree, Harpoon, Claude Code + Codex side panel, LaTeX and Markdown PDF preview, terminal toggle (`Ctrl /`), SystemVerilog indent fix, debug log |
| `tmux/` | tmux config: prefix `Ctrl a`, sessions saved and restored automatically (resurrect + continuum), status bar with the song that's playing and the time |

---

## Dependencies

### Needed

| Tool | Why |
|---|---|
| **Neovim 0.11 or newer** | The config uses 0.11 features. Ubuntu's `apt` version is too old, see below |
| **git** | Plugin manager downloads plugins with it |
| **C compiler** (`clang` / `gcc`, `make`) | Builds the Tree-sitter syntax parsers |
| **ripgrep** (`rg`) | Telescope's "search all files" (`Space p s`, `Space p g`) |
| **Node.js 18+ and npm** | Mason installs some language servers (bash, TypeScript, SQL) with npm |
| **curl, unzip, tar, gzip** | Mason downloads the other language servers (clangd, rust-analyzer) |
| **tmux 3.3 or newer** | |
| **A Nerd Font** in your terminal (I use MesloLGS NF) | Icons in the file tree, tabs and status bar |
| **Clipboard tool** (Linux / WSL only) | nvim copies to the system clipboard. Linux: `xclip` (X11) or `wl-clipboard` (Wayland). WSL: `win32yank.exe` |

The language servers themselves (clangd, rust-analyzer, bash, TypeScript, SQL) install
themselves through Mason the first time nvim starts. You don't install them by hand.

### Optional (only for the feature next to them)

| Tool | Feature | macOS | Linux | WSL |
|---|---|---|---|---|
| `claude` (Claude Code CLI) | `Space c c` panel | ✓ | ✓ | ✓ |
| `codex` (Codex CLI) | `Space c x` panel | ✓ | ✓ | ✓ |
| `tectonic` | LaTeX compile (`Space l l`), Markdown → PDF | ✓ | ✓ | ✓ |
| `pandoc` | Markdown → PDF (`Space m m`) | ✓ | ✓ | ✓ |
| `tdf` + iTerm2 | PDF pane next to nvim | ✓ | | |
| Skim | PDF that follows your cursor (`Space l s`) | ✓ | | |
| `zathura` | PDF viewer that follows your cursor, Ctrl+click jumps back to nvim | | ✓ | |
| `wslu` (`wslview`) | Opens PDFs in your Windows PDF app | | | ✓ |
| `playerctl` | Song in the tmux status bar (on a Mac it reads Spotify / Apple Music, nothing to install) | | ✓ | |
| `fd` | Faster "find file" in Telescope | ✓ | ✓ | ✓ |

---

## Install

The repo is **private**, so the new machine needs access first: either add an SSH key to
GitHub (`ssh-keygen -t ed25519`, then paste `~/.ssh/id_ed25519.pub` into GitHub →
Settings → SSH keys), or run `gh auth login` and clone with the https URL.

### macOS

```sh
xcode-select --install                     # C compiler, git
brew install neovim tmux ripgrep fd node tectonic pandoc tdf
brew install --cask iterm2 skim font-meslo-lg-nerd-font
curl -fsSL https://claude.ai/install.sh | bash       # Claude Code (optional)
npm install -g @openai/codex                         # Codex (optional)
```

Then **Get the config** below.

### Linux (Ubuntu / Debian; other distros have the same packages)

```sh
sudo apt update
sudo apt install git build-essential curl unzip tar gzip tmux ripgrep fd-find \
                 xclip zathura zathura-pdf-poppler playerctl pandoc fontconfig

# Neovim: apt's is too old, use the official build (arm64 machines: nvim-linux-arm64)
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64 && sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
echo 'export PATH="$PATH:/opt/nvim-linux-x86_64/bin"' >> ~/.bashrc   # or ~/.zshrc

# Node.js: apt's can be too old, nvm gives a current one
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
# (open a new terminal)
nvm install --lts

# tectonic (LaTeX), optional
curl --proto '=https' --tlsv1.2 -fsSL https://drop-sh.fullyjustified.net | sh
sudo mv tectonic /usr/local/bin/

curl -fsSL https://claude.ai/install.sh | bash       # Claude Code (optional)
npm install -g @openai/codex                         # Codex (optional)
```

Font: download **Meslo** from <https://www.nerdfonts.com/font-downloads>, put the files in
`~/.local/share/fonts`, run `fc-cache -f`, and choose it in your terminal's settings.
On Wayland, use `wl-clipboard` instead of `xclip`.

Then **Get the config** below.

### Windows (WSL)

tmux and the Claude / Codex panels need a Unix system, so on Windows everything runs in
WSL (a real Linux inside Windows). Native Windows nvim isn't supported.

1. **PowerShell as administrator:** `wsl --install`, restart, then open **Ubuntu** from the
   Start menu and choose a username and password.
2. **Font (in Windows, not in Ubuntu):** download **Meslo** from
   <https://www.nerdfonts.com/font-downloads>, right-click the `.ttf` files → *Install*.
   Then in **Windows Terminal** → Settings → Ubuntu → Appearance → Font face → the Meslo
   Nerd Font.
3. **In Ubuntu:** run everything from the **Linux** section above. You can skip `zathura`,
   `xclip` and `playerctl`. Then add the WSL extras:

   ```sh
   sudo apt install wslu                  # opens PDFs in your Windows PDF app
   # clipboard: copy in nvim, paste in Windows (and back)
   mkdir -p ~/.local/bin
   curl -sLo /tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip
   unzip -p /tmp/win32yank.zip win32yank.exe > ~/.local/bin/win32yank.exe
   chmod +x ~/.local/bin/win32yank.exe
   ```

   Keep your projects inside the Linux side (e.g. `~/projects`), not `/mnt/c/...`. It's much
   faster there.

---

## Get the config

Clone it somewhere of its own and link the two folders into `~/.config`, so nothing that's
already in `~/.config` gets overwritten:

```sh
git clone git@github.com:AEljaa/dotfiles.git ~/dotfiles
mkdir -p ~/.config
ln -s ~/dotfiles/nvim ~/.config/nvim
ln -s ~/dotfiles/tmux ~/.config/tmux
```

(On my Mac the repo *is* `~/.config`. The `.gitignore` at the top only lets `nvim/`,
`tmux/` and this README in, so other apps' settings and login tokens in `~/.config` can't
get committed by accident.)

## First start

**Neovim plugins** (once per machine):

```sh
git clone --depth 1 https://github.com/wbthomason/packer.nvim \
  ~/.local/share/nvim/site/pack/packer/start/packer.nvim
nvim ~/.config/nvim/lua/adameljaa/packer.lua
```

Inside nvim run `:so` then `:PackerSync`, wait for it to finish, then quit and reopen
nvim. The first time it opens, errors about missing plugins are normal: press Enter
through them. They're gone after the sync and restart. Mason then installs the language
servers in the background (watch with `:Mason`), and Tree-sitter compiles its parsers.

**tmux:** just run `tmux`. The first start downloads the plugin manager and the plugins
by itself, which takes a few seconds. To reinstall the plugins later, press `Ctrl a` then
`I`.

**Check:** inside nvim, `:checkhealth` lists anything still missing.

## Updating

```sh
cd ~/dotfiles && git pull        # then :PackerSync in nvim if plugins changed
```

---

## What's different per OS

| | macOS | Linux | Windows (WSL) |
|---|---|---|---|
| LaTeX / Markdown PDF | iTerm pane (tdf) or Skim | zathura (or the default PDF app) | Windows' default PDF app |
| Markdown PDF fonts | Helvetica / Menlo | Built-in TeX font (+ DejaVu Sans for arrows / ✓ if installed) | Same as Linux |
| Song in the tmux bar | Spotify / Apple Music | Any player, via `playerctl` | Not shown |
| Everything else | Same | Same | Same |

To try another OS's code path on this machine: `NVIM_PLATFORM=linux nvim` (or `wsl`).
