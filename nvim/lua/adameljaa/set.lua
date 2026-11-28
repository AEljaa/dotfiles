vim.opt.guicursor = ""
vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

-- .v is ambiguous (Verilog / V lang / Coq); in this setup it is always Verilog
vim.filetype.add({ extension = { v = 'verilog' } })

-- Over SSH on a Linux / WSL machine there's usually no clipboard tool, so yanks (and copies
-- from the Claude / Codex panels) never reached your Mac. Copy through the terminal instead
-- (OSC 52: Ghostty / iTerm put it on the Mac clipboard; inside tmux this needs
-- `set-clipboard on`, see tmux.conf). Paste uses nvim's own last yank: terminals usually
-- refuse to let programs read the clipboard.
if vim.env.SSH_TTY and not require('adameljaa.platform').mac
    and vim.fn.executable('xclip') == 0 and vim.fn.executable('wl-copy') == 0 then
  local osc52 = require('vim.ui.clipboard.osc52')
  local function paste() return { vim.fn.split(vim.fn.getreg(''), '\n'), vim.fn.getregtype('') } end
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
    paste = { ['+'] = paste, ['*'] = paste },
  }
end


