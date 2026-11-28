-- A shell under your code, like VS Code's terminal.
--
--   Ctrl /    open the terminal (in the repo's folder) / jump to it / hide it again
--             (works from your code and from inside the terminal). Hiding keeps it
--             running: same shell, same history next time.
--   Ctrl q    (inside it) hide it too       Ctrl h   (inside it) back to your code
--   exit      closes it for good
--
-- You're always typing when you're in it. To scroll / copy its output with Vim keys
-- press Ctrl \ Ctrl n (normal mode), then i to type again.
-- Plain :terminal also starts in typing mode now (it used to open in normal mode, so
-- typing "ls" ran Vim's l and s commands: "Cannot make changes, 'modifiable' is off").

local term = { buf = nil, height = nil }

local function is_code_win(w)
  if vim.api.nvim_win_get_config(w).relative ~= '' then return false end
  local b = vim.api.nvim_win_get_buf(w)
  return (vim.bo[b].buftype == '' or vim.bo[b].filetype == 'oil') and vim.bo[b].filetype ~= 'NvimTree'
end

local function code_win()
  local prev = vim.fn.win_getid(vim.fn.winnr('#'))
  if prev ~= 0 and is_code_win(prev) then return prev end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_code_win(w) then return w end
  end
end

local function root()
  local name = vim.api.nvim_buf_get_name(0)
  local dir = name:match('^oil://(.+)$')
  if not dir and name ~= '' and vim.bo.buftype == '' then dir = vim.fn.fnamemodify(name, ':p:h') end
  dir = dir or vim.fn.getcwd()
  return vim.fs.root(dir, '.git') or dir
end

local function term_win()
  if not (term.buf and vim.api.nvim_buf_is_valid(term.buf)) then return nil end
  return vim.fn.win_findbuf(term.buf)[1]
end

local function hide()
  local w = term_win()
  local real = vim.tbl_filter(function(x) return vim.api.nvim_win_get_config(x).relative == '' end,
    vim.api.nvim_tabpage_list_wins(0))                 -- popups don't count (E444 otherwise)
  if not w or #real == 1 then return end
  term.height = vim.api.nvim_win_get_height(w)
  local back = code_win()
  vim.api.nvim_win_hide(w)
  if back and vim.api.nvim_win_is_valid(back) then vim.api.nvim_set_current_win(back) end
  vim.cmd('stopinsert')
end

local function show()
  -- under the code, not under the Claude/Codex column
  local w = vim.api.nvim_get_current_win()
  if not is_code_win(w) then w = code_win() or w end
  vim.api.nvim_set_current_win(w)
  local h = term.height or math.max(math.floor(vim.o.lines * 0.3), 10)
  vim.cmd('belowright ' .. h .. 'split')
  local new = vim.api.nvim_get_current_win()
  if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    vim.api.nvim_win_set_buf(new, term.buf)
  else
    local dir = vim.api.nvim_win_call(w, root)
    term.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(new, term.buf)
    vim.fn.jobstart(vim.o.shell, { term = true, cwd = dir, on_exit = function()
      vim.schedule(function()
        local b = term.buf
        term.buf = nil
        if not (b and vim.api.nvim_buf_is_valid(b)) then return end
        for _, tw in ipairs(vim.fn.win_findbuf(b)) do
          if #vim.api.nvim_tabpage_list_wins(0) > 1 then pcall(vim.api.nvim_win_close, tw, true) end
        end
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end)
    end })
    vim.bo[term.buf].buflisted = false   -- not a tab at the top
    vim.bo[term.buf].bufhidden = 'hide'
    -- typing mode and normal mode (after Ctrl-\ Ctrl-n, Ctrl-h was Harpoon's file 1, opened in here)
    local map = function(lhs, fn, desc) vim.keymap.set({ 't', 'n' }, lhs, fn, { buffer = term.buf, desc = desc }) end
    map('<C-q>', hide, 'Hide the terminal (keeps running)')
    map('<C-h>', function()
      vim.cmd('stopinsert')
      local c = code_win()
      if c then vim.api.nvim_set_current_win(c) end
    end, 'Back to your code')
    vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
      buffer = term.buf,
      callback = function() vim.cmd('startinsert') end,   -- always typing when you're in it
    })
  end
  local wo = vim.wo[new]
  wo.number, wo.relativenumber, wo.signcolumn, wo.winfixheight = false, false, 'no', true
  vim.cmd('startinsert')
end

local function toggle()
  local w = term_win()
  if w and w == vim.api.nvim_get_current_win() then return hide() end
  if w then
    vim.api.nvim_set_current_win(w)
    vim.cmd('startinsert')
    return
  end
  show()
end

-- Ctrl / reaches nvim as <C-/> or (through tmux / older terminals) as <C-_>
for _, lhs in ipairs({ '<C-/>', '<C-_>' }) do
  vim.keymap.set({ 'n', 't', 'i' }, lhs, toggle, { desc = 'Terminal: open / jump to / hide' })
end

-- Plain :terminal: start typing straight away (Claude/Codex panels handle themselves)
vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('terminal_start_typing', { clear = true }),
  callback = function(ev)
    local shell = vim.fs.basename(vim.o.shell)
    if vim.api.nvim_buf_get_name(ev.buf):match(':' .. vim.pesc(vim.o.shell) .. '$')
      or vim.api.nvim_buf_get_name(ev.buf):match('/' .. vim.pesc(shell) .. '$') then
      vim.wo.number, vim.wo.relativenumber = false, false
      vim.cmd('startinsert')
    end
  end,
})
