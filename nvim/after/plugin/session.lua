-- Reopen where you left off.
--
--   vim .   (or plain `vim`) in a folder reopens the files you had open there last
--           time, each at the line you left it, and the Claude / Codex / Antigravity
--           panels that were open (they continue their last chat, as Space c c does).
--   vim somefile   opens just that file, as before, and leaves the saved session alone
--                  (so e.g. `git commit` opening nvim never wipes it).
--   :SessionForget   the next `vim .` here starts empty.
--
-- One small file per folder in ~/.local/state/nvim/sessions/. Saved when you quit.

local DIR = vim.fn.stdpath('state') .. '/sessions'
local key = nil   -- folder this nvim was started in with `vim .` / `vim`; nil = file mode

local function log(...) pcall(require('adameljaa.log').log, 'session', ...) end

local function file_for(folder)
  return ('%s/%s-%s.json'):format(DIR, vim.fn.fnamemodify(folder, ':t'):gsub('[^%w._-]', '_'),
    vim.fn.sha256(folder):sub(1, 12))
end

local function is_file_buf(b)
  if not (vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '') then return false end
  local name = vim.api.nvim_buf_get_name(b)
  return name ~= '' and not name:find('/%.git/') and vim.fn.filereadable(name) == 1
end

local function panel_of(b)
  if vim.bo[b].buftype ~= 'terminal' then return nil end
  if vim.bo[b].filetype == 'claudecode' then return 'claude' end
  local name = vim.api.nvim_buf_get_name(b)
  if name:find('codex (', 1, true) then return 'codex' end
  if name:find('agy (', 1, true) then return 'agy' end
end

local function save()
  if not key then return end
  local files, current, panels, cursor = {}, nil, {}, {}
  -- where each file's cursor is: the window showing it, else where you last left it
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == '' then
      if is_file_buf(b) then
        cursor[b] = vim.api.nvim_win_get_cursor(w)
        if not current or w == vim.api.nvim_get_current_win() then current = vim.api.nvim_buf_get_name(b) end
      end
      local p = panel_of(b)
      if p then panels[#panels + 1] = { name = p, row = vim.api.nvim_win_get_position(w)[1] } end
    end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if is_file_buf(b) then
      local pos = cursor[b] or vim.api.nvim_buf_get_mark(b, '"')
      files[#files + 1] = { path = vim.api.nvim_buf_get_name(b), line = math.max(1, pos[1]), col = pos[2] }
    end
  end
  table.sort(panels, function(a, b) return a.row < b.row end)   -- top to bottom, to stack them the same way
  local data = { folder = key, files = files, current = current,
                 panels = vim.tbl_map(function(p) return p.name end, panels) }
  vim.fn.mkdir(DIR, 'p')
  vim.fn.writefile({ vim.json.encode(data) }, file_for(key))
  log('saved %d files, panels: %s', #files, table.concat(data.panels, ', '))
end

local OPEN_PANEL = { claude = '<leader>cc', codex = '<leader>cx', agy = '<leader>cg' }

local function restore()
  local f = file_for(key)
  if vim.fn.filereadable(f) == 0 then return end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(f), '\n'))
  if not ok or type(data) ~= 'table' then return end
  local start_buf = vim.api.nvim_get_current_buf()                 -- the folder view of `vim .`
  local opened, current_ok = 0, false
  for _, it in ipairs(data.files or {}) do
    if type(it.path) == 'string' and vim.fn.filereadable(it.path) == 1 then
      vim.cmd(('badd +%d %s'):format(tonumber(it.line) or 1, vim.fn.fnameescape(it.path)))
      opened = opened + 1
      if it.path == data.current then current_ok = true end
    end
  end
  if opened == 0 and #(data.panels or {}) == 0 then return end
  local first = (current_ok and data.current) or ((data.files or {})[1] or {}).path
  if first and vim.fn.filereadable(first) == 1 then
    vim.cmd('edit ' .. vim.fn.fnameescape(first))
    for _, it in ipairs(data.files) do
      if it.path == first then pcall(vim.api.nvim_win_set_cursor, 0, { it.line, it.col or 0 }) end
    end
    if start_buf ~= vim.api.nvim_get_current_buf() and #vim.fn.win_findbuf(start_buf) == 0 then
      pcall(vim.api.nvim_buf_delete, start_buf, { force = false })  -- the folder view, now replaced
    end
  end
  local code_win = vim.api.nvim_get_current_win()
  -- panels after everything else has started (they open from the code window, so they
  -- find the right repo and continue its chat)
  vim.defer_fn(function()
    local names = {}
    for _, p in ipairs(data.panels or {}) do
      local m = OPEN_PANEL[p] and vim.fn.maparg(OPEN_PANEL[p], 'n', false, true)
      if m and m.callback and vim.api.nvim_win_is_valid(code_win) then
        vim.api.nvim_set_current_win(code_win)
        local ok2, err = pcall(m.callback)
        if ok2 then names[#names + 1] = ({ claude = 'Claude', codex = 'Codex', agy = 'Antigravity' })[p]
        else log('could not reopen %s: %s', p, tostring(err)) end
      end
    end
    if vim.api.nvim_win_is_valid(code_win) then
      vim.cmd('stopinsert')
      vim.api.nvim_set_current_win(code_win)
    end
    -- show each reopened chat at its latest messages, not its first line (a chat window
    -- with the cursor on its last line keeps following new output)
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if panel_of(b) and panel_of(b) ~= 'claude' then
        pcall(vim.api.nvim_win_call, w, function() vim.cmd('normal! G') end)
      end
    end
    local what = ('%d file%s'):format(opened, opened == 1 and '' or 's')
    if #names > 0 then what = what .. ' and ' .. table.concat(names, ', ') end
    vim.notify('Reopened ' .. what .. ' from last time (:SessionForget to start fresh next time)')
    log('restored %s', what)
  end, 100)
end

local grp = vim.api.nvim_create_augroup('session_restore', { clear = true })
vim.api.nvim_create_autocmd('VimEnter', {
  group = grp, nested = true,
  callback = function()
    local argc = vim.fn.argc()
    -- the file explorer (oil) has already turned `vim .` into "oil:///full/path/"
    local arg = argc == 1 and vim.fn.argv(0) or ''
    arg = arg:match('^oil://(.+)$') or arg
    if argc == 0 then
      key = vim.fn.getcwd()
    elseif argc == 1 and vim.fn.isdirectory(arg) == 1 then
      key = vim.fn.fnamemodify(arg, ':p'):gsub('/$', '')
    else
      return                                                      -- `vim somefile`: no session
    end
    -- not for background nvims (scripts, checks): they'd overwrite your session on exit.
    -- (Can't test for "no screen" here: in nvim 0.11 the screen connects after startup.)
    if vim.tbl_contains(vim.v.argv, '--headless') then key = nil return end
    restore()
  end,
})
vim.api.nvim_create_autocmd('VimLeavePre', { group = grp, callback = function() pcall(save) end })

vim.api.nvim_create_user_command('SessionForget', function()
  local folder = key or vim.fn.getcwd()
  vim.fn.delete(file_for(folder))
  key = nil                                                       -- and don't save this one on quit
  vim.notify('Forgot the session for ' .. vim.fn.fnamemodify(folder, ':~') .. ': next `vim .` there starts empty')
end, { desc = 'Next `vim .` in this folder starts empty' })
