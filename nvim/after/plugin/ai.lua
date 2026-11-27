-- Claude Code / Codex in a side panel, like the VS Code chat sidebar.
--
--   Space c c   Claude Code (claudecode.nvim)     Space c x   Codex
--     closed            -> open it on the right (in the git repo of this file) and focus it
--     open, not focused -> focus it
--     focused           -> hide it (the session keeps running; reopen to continue)
--   Entering a panel any way (click, Ctrl-w l, Space c c) puts you straight into typing.
--   Ctrl-h  or  Ctrl-\ Ctrl-\   (inside the panel) jump back to your code, panel stays open
--   Resize: drag the divider with the mouse, or Ctrl-w < / Ctrl-w >
--   Claude only: Space c a sends the visual selection (or adds the file);
--                Claude's edits open as diffs: :w or Space c y accepts, :q or Space c n rejects.
--
-- Each Codex session is per repo. Quitting the tool (/exit, Ctrl-d) closes the panel.

local panels = {}          -- key "<cmd>|<root>" -> { buf, win, width }
local function log(...) pcall(require('adameljaa.log').log, 'ai', ...) end
local skip_auto_insert = false   -- set when the scroll wheel moves you into Codex (see wheel())

-- Git repo of what you're looking at: the current file, the folder open in the file
-- explorer (oil://...), or nvim's folder. Claude and Codex both start here, and it's
-- also where Space c c looks for a previous chat to continue (the two must agree:
-- when Claude started in a subfolder, --continue found nothing there and quit).
local function repo_root()
  local name = vim.api.nvim_buf_get_name(0)
  local dir = name:match('^oil://(.+)$')
  if not dir and name ~= '' and vim.bo.buftype == '' then dir = vim.fn.fnamemodify(name, ':p:h') end
  dir = dir or vim.fn.getcwd()
  return vim.fs.root(dir, '.git') or vim.fn.getcwd()
end

local function visible_win(p)
  if p.win and vim.api.nvim_win_is_valid(p.win) and vim.api.nvim_win_get_buf(p.win) == p.buf then
    return p.win
  end
end

-- Is `buf` one of the AI terminals (Claude Code's, or a panel made below)?
local function is_ai_term(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= 'terminal' then return false end
  if vim.bo[buf].filetype == 'claudecode' then return true end
  for _, p in pairs(panels) do if p.buf == buf then return true end end
  return false
end

-- A normal (non-floating) window in this tab showing an AI terminal, other than `except`.
local function other_panel_win(except)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= except and vim.api.nvim_win_get_config(w).relative == ''
        and is_ai_term(vim.api.nvim_win_get_buf(w)) then
      return w
    end
  end
end

local function open_win(p)
  local other = other_panel_win()
  log('open panel %s, %s', vim.api.nvim_buf_get_name(p.buf):match('[^/:]+$') or '?', other and 'stacked' or 'new column')
  if other then
    -- Another AI panel is open: share its column (stacked underneath) instead of
    -- taking another 40% of the screen away from the code.
    vim.api.nvim_set_current_win(other)
    vim.cmd('belowright split')
  else
    -- Never come back narrower than 40 columns (e.g. if it was hidden while squashed).
    local width = math.max(p.width or math.floor(vim.o.columns * 0.4), 40)
    vim.cmd('botright vertical ' .. width .. 'split')
  end
  p.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(p.win, p.buf)
  local wo = vim.wo[p.win]
  wo.number, wo.relativenumber, wo.signcolumn = false, false, 'no'
  wo.winfixwidth = true   -- opening other splits won't squash it
  vim.cmd('startinsert')
end

local function toggle(cmd)
  local root = repo_root()
  local key = cmd .. '|' .. root
  local p = panels[key]

  if p and vim.api.nvim_buf_is_valid(p.buf) then
    local win = visible_win(p)
    if win and win == vim.api.nvim_get_current_win() then
      p.width = vim.api.nvim_win_get_width(win)   -- remember a resized width
      vim.api.nvim_win_hide(win)
    elseif win then
      vim.api.nvim_set_current_win(win)
      vim.cmd('startinsert')
    else
      open_win(p)
    end
    return
  end

  if vim.fn.executable(cmd) == 0 then
    vim.notify(cmd .. ' is not installed / not on PATH', vim.log.levels.ERROR)
    return
  end

  p = { buf = vim.api.nvim_create_buf(false, true) }
  panels[key] = p
  vim.bo[p.buf].bufhidden = 'hide'
  open_win(p)
  -- without tmux's variables: see "copy inside the panels" below
  -- codex --no-alt-screen: print into normal scrollback instead of a full-screen view,
  -- so the panel can be scrolled (wheel / Ctrl-u) and selected like Claude's
  -- Also without iTerm's: Codex took them to mean "running straight in iTerm" and sent
  -- iTerm's "turn finished" notification, which nvim's terminal can't show, so it
  -- printed as junk over Codex's prompt ("9;The slides make ...").
  local ENV = { 'env', '-u', 'TMUX', '-u', 'TERM_PROGRAM', '-u', 'LC_TERMINAL', '-u', 'LC_TERMINAL_VERSION',
                '-u', 'ITERM_SESSION_ID', '-u', 'ITERM_PROFILE' }
  local argv = vim.list_extend(vim.deepcopy(ENV), { cmd })
  if cmd == 'codex' then
    -- Continue the last Codex chat in this folder (like Space c c does for Claude).
    -- If there is none, resume fails straight away, so start a fresh chat instead. A
    -- resumed chat that you quit later (even with an error) never starts a new one.
    argv = vim.list_extend(vim.deepcopy(ENV), { 'sh', '-c', [[
      t=$(date +%s)
      codex resume --last --no-alt-screen; rc=$?
      if [ $rc -ne 0 ] && [ $(( $(date +%s) - t )) -lt 5 ]; then exec codex --no-alt-screen; fi
      exit $rc]] })
  end
  p.chan = vim.fn.jobstart(argv, {
    term = true,
    cwd = root,
    on_exit = function()
      vim.schedule(function()
        panels[key] = nil
        if not vim.api.nvim_buf_is_valid(p.buf) then return end
        -- Close its window(s) first: deleting a buffer shown in the *current* window
        -- leaves that window open with an empty buffer (the half-empty column bug).
        for _, w in ipairs(vim.fn.win_findbuf(p.buf)) do
          if #vim.api.nvim_tabpage_list_wins(0) > 1 then pcall(vim.api.nvim_win_close, w, true) end
        end
        log('%s exited; closed its panel', cmd)
        vim.api.nvim_buf_delete(p.buf, { force = true })
      end)
    end,
  })
  vim.api.nvim_buf_set_name(p.buf, cmd .. ' (' .. vim.fn.fnamemodify(root, ':t') .. ')')
end

vim.keymap.set('n', '<leader>cx', function() toggle('codex') end, { desc = 'Codex: open (continue last chat) / jump to it' })

-- Send the visual selection (with file:lines) or this file's path into the
-- Codex prompt, without submitting, so you can type your question after it.
-- If Codex isn't running yet it is opened and the snippet goes to the clipboard.
local function send_to(cmd, text)
  local key = cmd .. '|' .. repo_root()
  local fresh = not (panels[key] and vim.api.nvim_buf_is_valid(panels[key].buf))
  if fresh or not visible_win(panels[key]) then toggle(cmd) else
    vim.api.nvim_set_current_win(visible_win(panels[key])); vim.cmd('startinsert')
  end
  local p = panels[key]
  if not p or not p.chan or p.chan <= 0 then return end
  if fresh then
    -- A starting session may show a menu first (update prompt, login, trust); typing
    -- into that could pick an option. So hand it over via the clipboard instead.
    vim.fn.setreg('+', text)
    vim.notify(cmd .. ' is starting. When its prompt is ready, press Cmd+V to paste the snippet.', vim.log.levels.INFO)
    return
  end
  -- bracketed paste: multi-line text lands in the prompt instead of being submitted line by line
  vim.api.nvim_chan_send(p.chan, '\27[200~' .. text .. '\27[201~')
end

local function rel_path(root)
  local abs = vim.api.nvim_buf_get_name(0)
  return (abs:sub(1, #root + 1) == root .. '/') and abs:sub(#root + 2) or abs
end

vim.keymap.set('x', '<leader>cx', function()
  local root = repo_root()
  local s, e = vim.fn.line('v'), vim.fn.line('.')
  if s > e then s, e = e, s end
  local lines = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  local text = ('%s:%d-%d\n```%s\n%s\n```\n'):format(rel_path(root), s, e, vim.bo.filetype, table.concat(lines, '\n'))
  send_to('codex', text)
end, { desc = 'Send selection to Codex' })

vim.keymap.set('n', '<leader>cX', function()
  send_to('codex', rel_path(repo_root()) .. ' ')
end, { desc = 'Add this file to Codex prompt' })

-- Claude Code via coder/claudecode.nvim: same panel idea, but Claude also sees
-- your open file / selection, and its edits open as diffs here
-- (:w in the diff = accept, :q = reject).
local ok, claudecode = pcall(require, 'claudecode')
if ok then
  claudecode.setup({
    -- without tmux's variables: see "copy inside the panels" below
    -- (scripts/claude-panel: if --continue fails it shows why and starts a new chat)
    terminal_cmd = 'env -u TMUX -u TERM_PROGRAM ' .. vim.fn.shellescape(vim.fn.stdpath('config') .. '/scripts/claude-panel'),
    terminal = {
      split_side = 'right',
      split_width_percentage = 0.40,
      provider = 'native',             -- built-in terminal, no snacks.nvim needed
      auto_insert = true,
      cwd_provider = function() return repo_root() end,   -- run in the repo (see repo_root)
    },
    diff_opts = { layout = 'vertical' },
  })
  -- Space c c reopens your last chat in this repo after nvim restarts (claude --continue),
  -- instead of a blank one. Claude keeps chats in ~/.claude/projects/<repo path with
  -- every non-alphanumeric char turned into "-">/<id>.jsonl; with none there yet it
  -- starts fresh. (Within one nvim session, hiding or :q on the panel already keeps the
  -- chat running; --continue only matters once nvim itself was closed.)
  local function has_claude_history(root)
    local dir = vim.fn.expand('~/.claude/projects/') .. root:gsub('[^%w]', '-')
    return #vim.fn.glob(dir .. '/*.jsonl', false, true) > 0
  end
  vim.keymap.set('n', '<leader>cc', function()
    vim.cmd('ClaudeCodeFocus' .. (has_claude_history(repo_root()) and ' --continue' or ''))
  end, { desc = 'Claude Code: open (continue last chat) / jump to it' })
  vim.keymap.set('x', '<leader>ca', '<cmd>ClaudeCodeSend<CR>', { desc = 'Send selection to Claude' })
  vim.keymap.set('n', '<leader>ca', '<cmd>ClaudeCodeAdd %<CR>', { desc = 'Add this file to Claude' })
  vim.keymap.set('n', '<leader>cy', '<cmd>ClaudeCodeDiffAccept<CR>', { desc = 'Accept Claude diff' })

  -- Space c Y: Claude's last answer as clean text. Selecting in the panel with the mouse
  -- is unreliable (Claude redraws its screen, joins lines and grabs its input box), so
  -- this reads the answer from the chat Claude saves (~/.claude/projects/<repo>/*.jsonl):
  -- copies all of it, and opens it in a split so you can copy just part with v / y.
  local function last_claude_answer(root)
    local dir = vim.fn.expand('~/.claude/projects/') .. root:gsub('[^%w]', '-')
    local files = vim.fn.glob(dir .. '/*.jsonl', false, true)
    table.sort(files, function(a, b) return vim.fn.getftime(a) > vim.fn.getftime(b) end)
    if not files[1] then return nil end
    local turns, cur = {}, nil
    for _, line in ipairs(vim.fn.readfile(files[1])) do
      local ok, e = pcall(vim.json.decode, line)
      local m = ok and type(e) == 'table' and not e.isSidechain and e.message or nil
      if type(m) == 'table' then
        local c = m.content
        if e.type == 'user' and not e.isMeta then
          -- a prompt you typed (tool results are also "user" entries: skip those)
          local typed = type(c) == 'string'
          if type(c) == 'table' then
            for _, b in ipairs(c) do if b.type == 'text' then typed = true end end
          end
          if typed then cur = {}; turns[#turns + 1] = cur end
        elseif e.type == 'assistant' and type(c) == 'table' and cur then
          for _, b in ipairs(c) do
            if b.type == 'text' and type(b.text) == 'string' and b.text:match('%S') then cur[#cur + 1] = b.text end
          end
        end
      end
    end
    for i = #turns, 1, -1 do                -- newest turn that has text (the current one may still be running)
      if #turns[i] > 0 then return table.concat(turns[i], '\n\n') end
    end
  end
  vim.keymap.set('n', '<leader>cY', function()
    local text = last_claude_answer(repo_root())
    if not text then return vim.notify('No saved Claude answer for ' .. repo_root(), vim.log.levels.WARN) end
    vim.fn.setreg('+', text)
    vim.cmd('stopinsert')
    if is_ai_term(vim.api.nvim_get_current_buf()) then   -- open it under the code, not in the panel column
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local wb = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_win_get_config(w).relative == '' and (vim.bo[wb].buftype == '' or vim.bo[wb].filetype == 'oil') then
          vim.api.nvim_set_current_win(w); break
        end
      end
    end
    vim.cmd('belowright new')
    local b = vim.api.nvim_get_current_buf()
    vim.bo[b].buftype, vim.bo[b].bufhidden, vim.bo[b].swapfile = 'nofile', 'wipe', false
    vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(text, '\n', { plain = true }))
    vim.bo[b].filetype = 'markdown'
    vim.wo.wrap, vim.wo.linebreak = true, true
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = b, nowait = true })
    vim.notify(('Copied Claude\'s last answer (%d lines). It\'s open below: v + y copies part of it, q closes.'):format(vim.api.nvim_buf_line_count(b)))
  end, { desc = 'Copy Claude\'s last answer (+ open it to copy part)' })
  vim.keymap.set('n', '<leader>cn', '<cmd>ClaudeCodeDiffDeny<CR>', { desc = 'Reject Claude diff' })
else
  vim.keymap.set('n', '<leader>cc', function() toggle('claude') end, { desc = 'Claude Code panel' })
end

-- Keep the AI panels tidy whenever one of their terminals is shown somewhere:
--  * not a buffer tab at the top, so ]b / [b / clicking tabs never open Claude in
--    your code window (that showed the same session twice, garbled, at two widths)
--  * fixed width, so opening the file tree only resizes the code window
--  * if a second panel opens as a new column (claudecode always opens one), move it
--    under the first panel, so both together still use one 40% column
--  * if the same terminal ends up in a second window anyway, put your file back there
local function tidy(win, buf)
  if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)
          and vim.api.nvim_win_get_buf(win) == buf and is_ai_term(buf)) then return end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return end   -- floating: leave it
  vim.bo[buf].buflisted = false
  vim.bo[buf].bufhidden = 'hide'   -- closing its window never kills the session

  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= win and vim.api.nvim_win_get_buf(w) == buf then
      -- shown twice: this new window gets back the file it had before (or an empty one)
      log('%s was shown twice (win%d and win%d); putting the file back in win%d', vim.api.nvim_buf_get_name(buf), w, win, win)
      vim.api.nvim_win_call(win, function()
        local alt = vim.fn.bufnr('#')
        if alt > 0 and alt ~= buf and vim.bo[alt].buftype == '' then vim.cmd('buffer ' .. alt)
        else vim.cmd('enew') end
      end)
      return
    end
  end

  local other = other_panel_win(win)
  if other and vim.api.nvim_win_get_position(other)[2] ~= vim.api.nvim_win_get_position(win)[2] then
    local focused = vim.api.nvim_get_current_win() == win
    log('stacking %s (win%d) under the other panel (win%d)', vim.api.nvim_buf_get_name(buf):match('[^/:]+$') or '?', win, other)
    vim.api.nvim_win_close(win, false)            -- buffer just hides; the session keeps running
    vim.api.nvim_set_current_win(other)
    vim.cmd('belowright split')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    if not focused then vim.cmd('wincmd p') end
  end
  vim.wo[win].winfixwidth = true
end

-- Ctrl-h target: the code window you were last in (not just the previous window,
-- which can be the other panel once they're stacked).
local last_code_win
vim.api.nvim_create_autocmd('WinEnter', {
  group = vim.api.nvim_create_augroup('ai_last_code_win', { clear = true }),
  callback = function()
    local w = vim.api.nvim_get_current_win()
    if vim.bo.buftype == '' and vim.bo.filetype ~= 'NvimTree' and vim.api.nvim_win_get_config(w).relative == '' then
      last_code_win = w
    end
  end,
})
local function is_code_win(w)
  if not (w and vim.api.nvim_win_is_valid(w)) or vim.api.nvim_win_get_config(w).relative ~= '' then return false end
  local b = vim.api.nvim_win_get_buf(w)
  return vim.bo[b].buftype == '' and vim.bo[b].filetype ~= 'NvimTree'
end
local function back_to_code()
  vim.cmd('stopinsert')
  -- a panel's window briefly shows your file while opening, so re-check what it shows now
  local target = is_code_win(last_code_win) and last_code_win or nil
  if not target then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if is_code_win(w) then target = w; break end
    end
  end
  if target then vim.api.nvim_set_current_win(target) end
end

-- In any AI panel: typing goes straight to the tool whenever you enter it
-- (click, Ctrl-w l, Space c c), and Ctrl-h / Ctrl-\ Ctrl-\ jump back to the code.
vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter', 'TermOpen' }, {
  group = vim.api.nvim_create_augroup('ai_panel_insert', { clear = true }),
  callback = function(ev)
    local win, ebuf = vim.api.nvim_get_current_win(), ev.buf
    vim.schedule(function()
      if ev.event ~= 'WinEnter' then tidy(win, ebuf) end
      local buf = vim.api.nvim_get_current_buf()
      if is_ai_term(buf) then
        if not vim.b[buf].ai_keys then
          vim.b[buf].ai_keys = true
          for _, lhs in ipairs({ '<C-h>', '<C-\\><C-\\>' }) do
            vim.keymap.set('t', lhs, back_to_code, { buffer = buf, desc = 'Back to code (panel stays)' })
          end
          -- Ctrl-q: hide this panel straight from typing mode and go back to the code.
          -- The session keeps running; Space c c / Space c x brings it back as it was.
          vim.keymap.set({ 't', 'n' }, '<C-q>', function()
            local win = vim.api.nvim_get_current_win()
            back_to_code()
            if #vim.api.nvim_tabpage_list_wins(0) > 1 and vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_hide(win)
            end
          end, { buffer = buf, desc = 'Hide panel (session keeps running)' })
          -- Codex doesn't take the mouse (Claude does), so nvim handles a click in its
          -- panel and drops you into normal mode. A plain click now goes straight back
          -- to typing; a drag / double-click still selects text (visual mode, y copies),
          -- and the scroll wheel still scrolls back through the output.
          vim.keymap.set('n', '<LeftRelease>', function()
            if vim.api.nvim_get_mode().mode:match('^n') then vim.cmd('startinsert') end   -- 'nt' = normal mode in a terminal
          end, { buffer = buf, desc = 'Click in panel: back to typing' })
        end
        if skip_auto_insert then skip_auto_insert = false
        elseif vim.api.nvim_get_mode().mode ~= 't' then vim.cmd('startinsert') end
      end
    end)
  end,
})

-- Mouse wheel over the panels (one handler for every window, typing or not).
--  * Over a panel you're NOT in: nvim would scroll its own copy of that panel's screen
--    while the tool keeps redrawing it (flashing, jumping). So go into that panel first
--    and hand it the wheel: Claude then scrolls itself; Codex follows the rules below.
--  * Codex (nvim does the scrolling, Codex doesn't take the mouse): scrolling down
--    stops at the last line instead of running into empty space, and reaching the
--    bottom goes back to typing (which also follows new output again). While already
--    typing you're at the bottom, so more wheel-down does nothing.
--  * Everything else: normal scrolling.
local function wheel(dir)
  local key = vim.keycode('<ScrollWheel' .. dir .. '>')
  local function default() vim.api.nvim_feedkeys(key, 'n', false) end
  local win = vim.fn.getmousepos().winid
  if win == 0 or not vim.api.nvim_win_is_valid(win) then return default() end
  local buf = vim.api.nvim_win_get_buf(win)
  if not is_ai_term(buf) then return default() end
  local cur = vim.api.nvim_get_current_win()
  local typing = vim.api.nvim_get_mode().mode == 't'

  local claude = vim.bo[buf].filetype == 'claudecode'
  if win ~= cur then
    if claude then
      vim.api.nvim_set_current_win(win)
      vim.cmd('startinsert')   -- in typing mode nvim passes the wheel on to Claude
      return default()
    end
    skip_auto_insert = true    -- scrolling into Codex: stay out of typing to look back
    vim.api.nvim_set_current_win(win)
    typing = false
  end
  if claude then
    -- Claude scrolls itself, but only gets the wheel while you're typing in it. Out of
    -- typing (after a click/drag) nvim scrolled its own copy of Claude's screen instead:
    -- stale, repeated frames.
    if vim.api.nvim_get_mode().mode ~= 't' then vim.cmd('startinsert') end
    return default()
  end
  if dir == 'Up' then
    -- while typing, a wheel tick would only leave typing; leave it and then scroll
    if typing then vim.cmd('stopinsert'); vim.schedule(default) else default() end
    return
  end
  if typing then return end                                            -- already at the bottom

  local function scroll_down()
    if vim.api.nvim_get_current_win() ~= win then return end
    local step = tonumber(vim.o.mousescroll:match('ver:(%d+)')) or 3
    local left = vim.fn.line('$') - vim.fn.line('w$')     -- lines still below the window
    if left > 0 then vim.cmd(('normal! %d\5'):format(math.min(step, left))) end   -- \5 = Ctrl-e
    if left <= step then vim.cmd('startinsert') end       -- (w$ isn't updated until the next redraw)
  end
  -- Coming from typing in Claude, nvim is still in terminal mode for a moment after the
  -- switch, and :normal can't run there; leave it first, then scroll.
  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd('stopinsert'); vim.schedule(scroll_down)
  else
    scroll_down()
  end
end
for _, dir in ipairs({ 'Up', 'Down' }) do
  vim.keymap.set({ 'n', 't' }, '<ScrollWheel' .. dir .. '>', function() wheel(dir) end,
    { desc = 'Scroll (AI panels: see ai.lua)' })
end

-- Copy inside the panels (double-click / select in Claude or Codex).
-- They copy by sending the terminal an "OSC 52" clipboard sequence. nvim runs inside
-- tmux, so the panels inherited TMUX/TERM_PROGRAM and wrapped that sequence for tmux;
-- nvim's terminal doesn't understand the wrapper and printed the rest as junk
-- ("52;c;4p2vwq..."). So the panels start without those variables (above), and here
-- nvim takes the plain sequence and puts the text on the Mac clipboard.
vim.api.nvim_create_autocmd('TermRequest', {
  group = vim.api.nvim_create_augroup('terminal_osc52_copy', { clear = true }),
  callback = function(ev)
    local b64 = (ev.data and ev.data.sequence or ''):match('^\027%]52;[%w]*;([A-Za-z0-9+/=]+)')
    if not b64 then return end                       -- not a copy (or a '?' paste query)
    local ok, text = pcall(vim.base64.decode, b64)
    if ok and text then
      vim.fn.setreg('+', text)
      pcall(function() require('adameljaa.log').log('ai', 'copied %d chars from a terminal to the clipboard', #text) end)
    end
  end,
})

-- When Claude/Codex edit files you have open, reload them (unsaved buffers are left alone and you get asked).
vim.o.autoread = true
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'TermLeave', 'CursorHold' }, {
  group = vim.api.nvim_create_augroup('ai_panel_reload', { clear = true }),
  callback = function()
    if vim.fn.getcmdwintype() == '' and vim.bo.buftype == '' then vim.cmd('silent! checktime') end
  end,
})

-- Last chat closed and nothing else is on screen (you'd already :q'd your code window,
-- so nvim was only still open because of the panels): quit nvim instead of leaving an
-- empty page. If some file has unsaved changes it opens the project folder instead.
local function screen_is_empty()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == '' then
      local b = vim.api.nvim_win_get_buf(w)
      local blank = vim.bo[b].buftype == '' and vim.api.nvim_buf_get_name(b) == '' and not vim.bo[b].modified
        and vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ''
      if not (blank or vim.bo[b].filetype == 'NvimTree') then return false end
    end
  end
  return true
end
vim.api.nvim_create_autocmd('TermClose', {
  group = vim.api.nvim_create_augroup('ai_quit_when_empty', { clear = true }),
  callback = function(ev)
    if not is_ai_term(ev.buf) or vim.fn.tabpagenr('$') > 1 then return end
    -- wait for Claude's / Codex's own exit handling to close their windows first
    vim.defer_fn(function()
      if not screen_is_empty() then return end
      local ok, err = pcall(vim.cmd, 'qa')
      if ok then return end
      err = tostring(err):match('E%d+:.*') or tostring(err)
      -- couldn't quit: a file has unsaved changes, or a hidden chat (Ctrl q) is still running
      log('last visible chat closed but nvim could not quit (%s); showing the folder', err)
      vim.cmd('only | edit ' .. vim.fn.fnameescape(vim.fn.getcwd()))
      vim.notify('nvim stayed open: ' .. err, vim.log.levels.WARN)
    end, 300)
  end,
})
