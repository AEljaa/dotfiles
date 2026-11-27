-- UI layer: icons, file tree, statusline, buffer tabs, git signs, keymap popup.
-- Icons need a Nerd Font in the terminal (iTerm: MesloLGS NF as the non-ASCII font).

vim.opt.showmode = false     -- lualine shows the mode
vim.opt.laststatus = 3       -- one statusline across all splits
vim.opt.cursorline = true

require('nvim-web-devicons').setup({ default = true })

-- File tree ------------------------------------------------------------------
-- netrw is left alone, so <leader>pv still opens it.
require('nvim-tree').setup({
  hijack_netrw = false,
  sync_root_with_cwd = true,
  update_focused_file = { enable = true },   -- tree follows the current buffer
  view = { width = 32 },
  renderer = {
    group_empty = true,
    highlight_git = true,
    indent_markers = { enable = true },
  },
  diagnostics = { enable = true, show_on_dirs = true },
  filters = { custom = { '^\\.git$', '^\\.DS_Store$' } },
})
local tree = require('nvim-tree.api').tree
vim.keymap.set('n', '<leader>e', function() tree.toggle({ find_file = true, focus = true }) end,
  { desc = 'Toggle file tree' })
vim.keymap.set('n', '<leader>E', function() tree.find_file({ open = true, focus = true }) end,
  { desc = 'Reveal file in tree' })

-- Directory browser (replaces netrw) -----------------------------------------
-- Edit the listing like text: rename a line, dd to delete, add a line ending in
-- "/" for a new dir, then :w to apply. g? shows every key.
function _G.oil_winbar()
  local dir = require('oil').get_current_dir(vim.api.nvim_win_get_buf(vim.g.statusline_winid))
  dir = dir and vim.fn.fnamemodify(dir, ':~') or vim.api.nvim_buf_get_name(0)
  local width = vim.api.nvim_win_get_width(vim.g.statusline_winid)
  local hints = {
    'Enter open · - up · Ctrl p preview · Ctrl v split · g . hidden · edit + :w to rename/delete · g ? all keys ',
    'Enter open · - up · Ctrl p preview · edit + :w to save · g ? all keys ',
    'Space ? shortcuts ',
  }
  local hint = ''
  for _, h in ipairs(hints) do
    if #dir + #h + 6 <= width then hint = h; break end
  end
  return '%#Directory#  ' .. dir:gsub('%%', '%%%%') .. '%=%#Comment#' .. hint
end
require('oil').setup({
  default_file_explorer = true,      -- `nvim .` and directory buffers open in oil
  columns = {
    'icon',
    'permissions',
    'size',
    { 'mtime', format = '%b %d %H:%M' },
  },
  view_options = {
    show_hidden = true,
    is_always_hidden = function(name) return name == '..' or name == '.git' or name == '.DS_Store' end,
  },
  delete_to_trash = true,            -- dd + :w goes to the macOS Trash, not rm
  skip_confirm_for_simple_edits = true,
  win_options = { winbar = '%!v:lua.oil_winbar()', signcolumn = 'no', cursorline = true },
  float = { padding = 4, max_width = 120, border = 'rounded' },
  preview_win = { preview_method = 'load' },
  keymaps = {
    -- oil's defaults use <C-s>/<C-h>/<C-t>, which are your harpoon jumps
    ['<C-s>'] = false,
    ['<C-h>'] = false,
    ['<C-t>'] = false,
    ['<C-v>'] = { 'actions.select', opts = { vertical = true }, desc = 'Open in vertical split' },
    ['<C-x>'] = { 'actions.select', opts = { horizontal = true }, desc = 'Open in horizontal split' },
    ['q'] = { 'actions.close', mode = 'n' },
  },
})
vim.keymap.set('n', '<leader>pV', function() require('oil').open_float() end, { desc = 'File explorer (float)' })

-- Statusline -----------------------------------------------------------------
require('lualine').setup({
  options = {
    theme = 'auto',
    globalstatus = true,
    disabled_filetypes = { statusline = { 'NvimTree' } },
  },
  sections = {
    lualine_c = { { 'filename', path = 1 } },   -- path relative to cwd
    lualine_x = {
      { function()
          local names = {}
          for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do names[#names + 1] = c.name end
          return #names > 0 and (' ' .. table.concat(names, ',')) or ''
        end },
      'filetype',
    },
    -- right end: cursor line:col, then a 24-hour clock (lualine redraws every second)
    lualine_z = { 'location', { function() return os.date('%H:%M') end, icon = '' } },
  },
})

-- Buffer tabs (switch with [b / ]b, built into Neovim 0.11) -------------------
require('bufferline').setup({
  options = {
    diagnostics = 'nvim_lsp',
    show_buffer_close_icons = false,
    max_name_length = 40,     -- default 18 cut off names like foreach_with_basics.sv
    truncate_names = false,
    tab_size = 20,
    offsets = { { filetype = 'NvimTree', text = 'Files', separator = true } },
    -- Clicking a tab opens that file in a code window, even if you're in the
    -- Claude/Codex panel or the file tree (default would replace whatever is focused).
    left_mouse_command = function(bufnr)
      local function is_code(w)
        local b = vim.api.nvim_win_get_buf(w)
        return vim.api.nvim_win_get_config(w).relative == '' and vim.bo[b].buftype == ''
          and vim.bo[b].filetype ~= 'NvimTree'
      end
      local target = vim.api.nvim_get_current_win()
      if not is_code(target) then
        local prev = vim.fn.win_getid(vim.fn.winnr('#'))
        target = (prev ~= 0 and is_code(prev)) and prev or nil
        for _, w in ipairs(target and {} or vim.api.nvim_tabpage_list_wins(0)) do
          if is_code(w) then target = w; break end
        end
      end
      if not target then return end
      vim.api.nvim_set_current_win(target)
      vim.api.nvim_win_set_buf(target, bufnr)
    end,
  },
  highlights = (function()
    local h = {}
    for _, k in ipairs({ 'buffer_selected', 'numbers_selected', 'diagnostic_selected',
                         'hint_selected', 'hint_diagnostic_selected', 'info_selected',
                         'info_diagnostic_selected', 'warning_selected', 'warning_diagnostic_selected',
                         'error_selected', 'error_diagnostic_selected' }) do
      h[k] = { italic = false, bold = true }
    end
    return h
  end)(),
})
vim.keymap.set('n', '<leader>bp', '<cmd>BufferLinePick<CR>', { desc = 'Pick buffer' })
vim.keymap.set('n', '<leader>bd', '<cmd>bp|bd #<CR>', { desc = 'Close buffer' })

-- Git signs in the gutter ----------------------------------------------------
require('gitsigns').setup({
  on_attach = function(bufnr)
    local gs = require('gitsigns')
    local map = function(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { buffer = bufnr, desc = desc }) end
    map(']h', function() gs.nav_hunk('next') end, 'Next git hunk')
    map('[h', function() gs.nav_hunk('prev') end, 'Prev git hunk')
    map('<leader>hp', gs.preview_hunk, 'Preview hunk')
    map('<leader>hb', gs.blame_line, 'Blame line')
  end,
})

-- Keymap popup: press <leader> and wait ---------------------------------------
local wk = require('which-key')
wk.setup({
  preset = 'modern',
  -- spell keys out as words instead of symbol icons
  icons = {
    keys = {
      Space = 'Space ', C = 'Ctrl ', M = 'Alt ', S = 'Shift ', D = 'Cmd ',
      CR = 'Enter ', NL = 'Enter ', Esc = 'Esc ', BS = 'Backspace ', Tab = 'Tab ',
      Up = 'Up ', Down = 'Down ', Left = 'Left ', Right = 'Right ',
    },
  },
})
wk.add({
  { '<leader>p', group = 'project / find' },
  { '<leader>b', group = 'buffers' },
  { '<leader>h', group = 'git hunks' },
  { '<leader>n', group = 'notifications / debug log' },
  { '<leader>c', group = 'copy error / AI chat' },
  { '<leader>t', group = 'theme' },
  { '<leader>l', group = 'LaTeX (in .tex files)' },
  { '<leader>m', group = 'Markdown preview (in .md files)' },
  { '<leader>?', function() require('adameljaa.cheatsheet').open() end, desc = 'Cheatsheet: all shortcuts' },
  { 'gR', desc = 'Replace word under cursor in file' },
  { '<leader>a', desc = 'Harpoon: add file' },
  { '<leader>u', desc = 'Undo tree' },
  { '<leader>gs', desc = 'Git status (fugitive)' },
})

-- Messages / errors / cmdline as popups ---------------------------------------
require('notify').setup({ stages = 'fade', timeout = 3000, render = 'wrapped-compact', max_width = 60 })
require('noice').setup({
  lsp = {
    -- render LSP hover / docs with treesitter markdown
    override = {
      ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
      ['vim.lsp.util.stylize_markdown'] = true,
      ['cmp.entry.get_documentation'] = true,
    },
  },
  presets = {
    bottom_search = true,          -- / and ? stay at the bottom
    command_palette = true,        -- : opens a centered box with the completion menu under it
    long_message_to_split = true,  -- long errors (stack traces) open in a split you can scroll/yank
    lsp_doc_border = true,         -- borders on hover and signature help
  },
  routes = {
    -- hide hdl_checker's chatty startup info ("Searching...", "Added N sources", version nag)
    { filter = { event = 'notify', find = 'hdl_checker' }, opts = { skip = true } },
    { filter = { event = 'msg_show', find = 'written' }, opts = { skip = true } },
  },
})
vim.keymap.set('n', '<leader>nh', '<cmd>Noice history<CR>', { desc = 'Message history' })
vim.keymap.set('n', '<leader>nd', '<cmd>Noice dismiss<CR>', { desc = 'Dismiss popups' })

-- :help on its own opens the cheatsheet (:help <topic> and :h still go to Vim's docs)
vim.api.nvim_create_user_command('Cheatsheet', function() require('adameljaa.cheatsheet').open() end,
  { desc = 'Show all shortcuts' })
vim.api.nvim_create_user_command('Keys', 'Cheatsheet', { desc = 'Show all shortcuts' })
vim.keymap.set('c', '<CR>', function()
  if vim.fn.getcmdtype() == ':' and vim.fn.getcmdline() == 'help' then
    return '<C-u>Cheatsheet<CR>'
  end
  return '<CR>'
end, { expr = true, desc = 'Bare :help opens the cheatsheet' })

-- Diagnostic signs with icons ------------------------------------------------
vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '',
      [vim.diagnostic.severity.WARN]  = '',
      [vim.diagnostic.severity.INFO]  = '',
      [vim.diagnostic.severity.HINT]  = '󰌵',
    },
  },
})
