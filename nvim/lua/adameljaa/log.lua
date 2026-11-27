-- Debug log for "the windows went weird and I can't explain how" moments.
--
-- File: ~/.config/nvim/logs/nvim.log   (not committed: see ~/.config/nvim/.gitignore)
--   Space n l   "something just went wrong": writes a MARK with the full window
--               layout, recent popups and the last error (:LogMark <note> adds a note)
--   Space n L   open the log at the bottom (newest last)
--   :LogMark [note]  /  :LogOpen   the same as commands
--
-- What gets written (one line per event, "time [pid] [kind] ..."):
--   * session start: nvim version, folder, screen size, terminal, tmux
--   * window layout whenever it changes: every window's size, position, buffer,
--     filetype, fixed width (debounced, and only when something actually changed)
--   * keys you pressed in normal/visual mode since the last entry (NOT what you type
--     in insert mode, the : line, or the Claude/Codex panels, so no code or prompts)
--   * : commands you ran, popups/notifications, errors, LSP attach/detach,
--     terminals opening/closing, and what the AI-panel code did (ai.lua)
-- Several nvims (one per tmux window) share the file; the [pid] tells them apart and
-- each "session start" line says which folder that pid is in. Over 2 MB it rotates
-- to nvim.log.1 at the next start.
local M = {}

-- NVIM_DEBUG_LOG=/some/file overrides the location (used for test runs, so they
-- never touch the real log)
M.path = vim.env.NVIM_DEBUG_LOG or (vim.fn.stdpath('config') .. '/logs/nvim.log')
M.dir = vim.fn.fnamemodify(M.path, ':h')
local MAX_BYTES = 2 * 1024 * 1024
local pid = vim.fn.getpid()

local function stamp()
  local sec, usec = vim.uv.gettimeofday()
  return os.date('%Y-%m-%d %H:%M:%S', sec) .. string.format('.%03d', math.floor(usec / 1000))
end

function M.write(kind, msg)
  local f = io.open(M.path, 'a')
  if not f then return end
  for i, line in ipairs(vim.split(tostring(msg), '\n', { plain = true })) do
    f:write(('%s [%d] [%s] %s%s\n'):format(stamp(), pid, kind, i > 1 and '  | ' or '', line))
  end
  f:close()
end

-- Public: M.log('ai', 'docked %s', name)
function M.log(kind, fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  M.write(kind, ok and msg or tostring(fmt))
end

------------------------------------------------------------------------ keys
-- Normal/visual/operator-pending keys only, flushed into the next log entry.
local keys = {}
local function flush_keys()
  if #keys == 0 then return end
  M.write('keys', table.concat(keys))
  keys = {}
end

------------------------------------------------------------------------ layout
local function bufdesc(b)
  local name = vim.api.nvim_buf_get_name(b)
  if vim.bo[b].buftype == 'terminal' then
    name = 'term:' .. (name:match('([^/:]+)$') or name)       -- term:claude, term:codex
  elseif name == '' then
    name = '[No Name]'
  else
    name = vim.fn.fnamemodify(name, ':~:.')
  end
  return name
end

local function layout(include_floats)
  local lines, floats = {}, 0
  local cur = vim.api.nvim_get_current_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= '' and not include_floats then
      floats = floats + 1
    else
      local b = vim.api.nvim_win_get_buf(w)
      local pos = vim.api.nvim_win_get_position(w)
      lines[#lines + 1] = ('%s win%d %3dx%-3d @row%d,col%d buf%d %s ft=%s bt=%s%s%s%s'):format(
        w == cur and '>' or ' ', w, vim.api.nvim_win_get_width(w), vim.api.nvim_win_get_height(w),
        pos[1], pos[2], b, bufdesc(b), vim.bo[b].filetype, vim.bo[b].buftype,
        vim.wo[w].winfixwidth and ' fixwidth' or '', vim.bo[b].buflisted and ' listed' or '',
        cfg.relative ~= '' and ' FLOAT' or '')
    end
  end
  local head = ('screen %dx%d, mode %s, tab %d/%d%s'):format(vim.o.columns, vim.o.lines,
    vim.api.nvim_get_mode().mode, vim.fn.tabpagenr(), vim.fn.tabpagenr('$'),
    floats > 0 and (', +' .. floats .. ' popup(s)') or '')
  return head .. '\n' .. table.concat(lines, '\n')
end

local last_layout, reasons, timer = nil, {}, nil
local function snapshot()
  timer = nil
  local text = layout(false)
  local why = table.concat(vim.tbl_keys(reasons), ', ')
  reasons = {}
  if text == last_layout then return end    -- nothing actually moved
  last_layout = text
  flush_keys()
  M.write('layout', '(' .. why .. ') ' .. text)
end
local function layout_changed(reason)
  reasons[reason] = true
  if timer then timer:stop() end
  timer = vim.defer_fn(snapshot, 150)        -- one entry per burst of events
end

------------------------------------------------------------------------ popups
local seen_popups = 0
function M.flush_popups()
  local ok, hist = pcall(function() return require('notify').history() end)
  if not ok or not hist or #hist <= seen_popups then return end
  for i = seen_popups + 1, #hist do
    local n = hist[i]
    M.write('popup', ('%s: %s'):format(n.level, table.concat(n.message, ' | ')))
  end
  seen_popups = #hist
end

------------------------------------------------------------------------ errors
local last_err = ''
local function check_errmsg()
  local e = vim.v.errmsg
  if e ~= '' and e ~= last_err then
    last_err = e
    flush_keys()
    M.write('error', e)
  end
end

------------------------------------------------------------------------ mark / open
function M.mark(note)
  flush_keys()
  M.flush_popups()
  check_errmsg()
  -- recent popups (noice/nvim-notify own the message area, so :messages is empty here
  -- and reading it would pop open noice's split)
  local tail = {}
  local ok, hist = pcall(function() return require('notify').history() end)
  if ok and hist then
    for i = math.max(1, #hist - 9), #hist do
      local n = hist[i]
      tail[#tail + 1] = ('%s %s: %s'):format(os.date('%H:%M:%S', n.time), n.level, table.concat(n.message, ' '))
    end
  end
  tail = table.concat(tail, '\n')
  M.write('MARK', ('=== %s ===\n%s\nlast error: %s\nrecent popups:\n%s'):format(
    (note and note ~= '') and note or 'problem here', layout(true), vim.v.errmsg, tail))
  vim.notify('Logged. Tell Claude "check the nvim log" (' .. vim.fn.fnamemodify(M.path, ':~') .. ')')
end

function M.open()
  vim.cmd('botright split ' .. vim.fn.fnameescape(M.path))
  vim.bo.autoread = true
  vim.cmd('normal! G')
end

------------------------------------------------------------------------ setup
function M.setup()
  vim.fn.mkdir(M.dir, 'p')
  local st = vim.uv.fs_stat(M.path)
  if st and st.size > MAX_BYTES then os.rename(M.path, M.path .. '.1') end

  local g = vim.api.nvim_create_augroup('debug_log', { clear = true })
  local au = function(ev, fn, pat) vim.api.nvim_create_autocmd(ev, { group = g, callback = fn, pattern = pat }) end

  au('VimEnter', function()
    local v = vim.version()
    M.write('session', ('==== start: nvim %d.%d.%d, folder %s, screen %dx%d, %s%s'):format(
      v.major, v.minor, v.patch, vim.fn.fnamemodify(vim.fn.getcwd(), ':~'), vim.o.columns, vim.o.lines,
      vim.env.TERM_PROGRAM or vim.env.TERM or '?', vim.env.TMUX and ', in tmux' or ''))
    layout_changed('start')
    -- Popups: read nvim-notify's history every 2 s instead of wrapping vim.notify
    -- (noice checks vim.notify is its own and shows an error if anything wraps it).
    local t = vim.uv.new_timer()
    t:start(2000, 2000, vim.schedule_wrap(function() M.flush_popups() end))
  end)
  au('VimLeavePre', function() flush_keys(); M.flush_popups(); M.write('session', '==== exit') end)

  for _, ev in ipairs({ 'WinNew', 'WinClosed', 'WinResized', 'VimResized', 'TabEnter', 'BufWinEnter' }) do
    au(ev, function(a)
      local extra = (ev == 'BufWinEnter' and a.buf) and ('(' .. bufdesc(a.buf) .. ')') or ''
      layout_changed(ev .. extra)
    end)
  end

  au('CmdlineLeave', function()
    if vim.fn.getcmdtype() == ':' and not vim.v.event.abort then
      flush_keys()
      M.write('cmd', ':' .. vim.fn.getcmdline())
    end
  end)
  au({ 'CursorHold', 'ModeChanged' }, check_errmsg)
  au('LspAttach', function(a)
    local c = vim.lsp.get_client_by_id(a.data.client_id)
    M.write('lsp', ('attach %s -> %s'):format(c and c.name or '?', bufdesc(a.buf)))
  end)
  au('LspDetach', function(a)
    local c = vim.lsp.get_client_by_id(a.data.client_id)
    M.write('lsp', ('detach %s -> %s'):format(c and c.name or '?', bufdesc(a.buf)))
  end)
  au('TermOpen', function(a) M.write('term', 'open ' .. bufdesc(a.buf)) end)
  au('TermClose', function(a)
    local status = vim.v.event.status
    local msg = ('close %s (exit %s)'):format(bufdesc(a.buf), tostring(status))
    -- crashed: keep its last words (the window usually closes before you can read them)
    if status ~= 0 then
      local tail = {}
      for _, l in ipairs(vim.api.nvim_buf_get_lines(a.buf, 0, -1, false)) do
        if l:match('%S') then tail[#tail + 1] = l end
      end
      tail = vim.list_slice(tail, math.max(1, #tail - 14))
      if #tail > 0 then msg = msg .. ', last output:\n' .. table.concat(tail, '\n') end
    end
    M.write('term', msg)
  end)

  vim.on_key(function(_, typed)
    if not typed or typed == '' then return end
    local m = vim.api.nvim_get_mode().mode:sub(1, 1)
    if m == 'n' or m == 'v' or m == 'V' or m == '\22' or m == 'o' then
      keys[#keys + 1] = vim.fn.keytrans(typed)
      if #keys > 200 then flush_keys() end
    end
  end, vim.api.nvim_create_namespace('debug_log_keys'))

  vim.api.nvim_create_user_command('LogMark', function(o) M.mark(o.args) end, { nargs = '*', desc = 'Mark a problem in the debug log' })
  vim.api.nvim_create_user_command('LogOpen', M.open, { desc = 'Open the debug log' })
  vim.keymap.set('n', '<leader>nl', function() M.mark('') end, { desc = 'Log: mark a problem (+ layout snapshot)' })
  vim.keymap.set('n', '<leader>nL', M.open, { desc = 'Log: open the debug log' })
end

return M
