-- Claude Code / Codex / Antigravity in a side panel, like the VS Code chat sidebar.
--
--   Space c c   Claude Code (claudecode.nvim)     Space c x   Codex
--   Space c g   Antigravity CLI (agy)
--     closed            -> open it on the right (in the git repo of this file) and focus it
--     open, not focused -> focus it
--     focused           -> hide it (the session keeps running; reopen to continue)
--   Entering a panel any way (click, Ctrl-w l, Space c c) puts you straight into typing.
--   Ctrl-h  or  Ctrl-\ Ctrl-\   (inside the panel) jump back to your code, panel stays open
--   Resize: drag the divider with the mouse, or Ctrl-w < / Ctrl-w >
--   Claude only: Space c a sends the visual selection (or adds the file);
--                Claude's edits open as diffs: :w or Space c y accepts, :q or Space c n rejects.
--
-- Each Codex / Antigravity session is per repo. Quitting the tool (/exit, Ctrl-d) closes the panel.

local panels = {}          -- key "<cmd>|<root>" -> { buf, win, width }
local function log(...) pcall(require('adameljaa.log').log, 'ai', ...) end
local skip_auto_insert = false   -- set when the scroll wheel moves you into Codex (see wheel())
local chat_exited                -- "a chat's process ended": defined at the bottom, used by toggle()

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

-- Antigravity: the last chat started in `root`. agy's own --continue picks the newest chat
-- from *any* folder, so read its prompt history instead (~/.gemini/antigravity-cli/
-- history.jsonl: one line per prompt, with the folder ("workspace") and chat id).
local AGY_DIR = vim.fn.expand('~/.gemini/antigravity-cli')
local function agy_last_chat(root)
  local ok, lines = pcall(vim.fn.readfile, AGY_DIR .. '/history.jsonl')
  if not ok then return nil end
  for i = #lines, 1, -1 do
    local good, e = pcall(vim.json.decode, lines[i])
    if good and type(e) == 'table' and e.workspace == root and type(e.conversationId) == 'string'
        and e.conversationId:match('^[%w-]+$')
        and vim.fn.filereadable(AGY_DIR .. '/conversations/' .. e.conversationId .. '.db') == 1 then
      return e.conversationId
    end
  end
end

-- Codex and Antigravity redraw their whole chat whenever the panel changes size (another
-- panel opens or closes, hide + reopen, nvim resized). They first send "clear screen +
-- clear scrollback", but nvim's terminal ignores the scrollback part, so every redraw
-- stacked another full copy above the last (9 copies after a few panel changes, so
-- scrolling up showed the same chat over and over). Every copy starts with the tool's
-- banner, so once the output settles, drop everything above the newest banner. Anyone
-- scrolled up reading stays on the same text.
local BANNER = {
  codex = '^%s*>_ OpenAI Codex %(v[%w.%-]+%)%s*$',
  -- with or without its logo (a short panel gets the plain one-line banner)
  agy = '^[%s▄▀]*Antigravity CLI %d+%.%d+%.%d+%s*$',
}
local function drop_old_copies(buf, pat)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then return end                  -- hidden: its size is unknown; redone when shown
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first, last
  for i, l in ipairs(lines) do
    if l:find(pat) then first = first or i; last = i end
  end
  if not last or first == last then return end
  local start = last
  while start > 1 and start > last - 2 and lines[start - 1] == '' do start = start - 1 end
  -- only scrollback can go: the bottom `rows` lines are the live screen
  local rows = math.huge
  for _, w in ipairs(wins) do rows = math.min(rows, vim.api.nvim_win_get_height(w)) end
  local sb = #lines - rows
  local drop = math.min(start - 1, sb - 1)
  if drop <= 0 then return end
  local typing_in = vim.api.nvim_get_mode().mode == 't' and vim.api.nvim_get_current_win() or nil
  local views = {}
  for _, w in ipairs(wins) do
    if w ~= typing_in then views[w] = vim.api.nvim_win_call(w, vim.fn.winsaveview) end
  end
  local old = vim.bo[buf].scrollback
  vim.bo[buf].scrollback = math.max(1, sb - drop)   -- lowering it deletes the oldest lines
  vim.bo[buf].scrollback = old
  for w, v in pairs(views) do
    if vim.api.nvim_win_is_valid(w) then
      v.topline, v.lnum = math.max(1, v.topline - drop), math.max(1, v.lnum - drop)
      vim.api.nvim_win_call(w, function() vim.fn.winrestview(v) end)
    end
  end
  log('%s: dropped %d lines of old copies of the chat (after a redraw)', vim.api.nvim_buf_get_name(buf):match('[^/]+$') or '?', drop)
end
local function watch_redraws(buf, cmd)
  local pat = BANNER[cmd]
  if not pat then return end
  local timer = vim.uv.new_timer()
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()   -- output arrived: check 300 ms after it stops
      timer:stop()
      timer:start(300, 0, vim.schedule_wrap(function() pcall(drop_old_copies, buf, pat) end))
    end,
    on_detach = function() timer:stop(); if not timer:is_closing() then timer:close() end end,
  })
end

local function visible_win(p)
  if p.win and vim.api.nvim_win_is_valid(p.win) and vim.api.nvim_win_get_buf(p.win) == p.buf then
    return p.win
  end
  -- tidy() may have moved it to a new window (it doesn't know about `panels`): find it,
  -- otherwise Space c x thought it was hidden and opened it a second time
  for _, w in ipairs(vim.fn.win_findbuf(p.buf)) do
    if vim.api.nvim_win_get_config(w).relative == '' and vim.api.nvim_win_get_tabpage(w) == vim.api.nvim_get_current_tabpage() then
      p.win = w
      return w
    end
  end
end

-- Is the mouse really over window `w`? getmousepos().winid can't be trusted for this:
-- over nvim's tab bar (top row) it still names the window underneath, so events there
-- were treated as inside the panel, and nvim's terminal then dropped out of typing.
local function mouse_in(w, pos)
  local at = vim.api.nvim_win_get_position(w)
  local r, c = pos.screenrow - 1, pos.screencol - 1
  return r >= at[1] and r < at[1] + vim.api.nvim_win_get_height(w)
     and c >= at[2] and c < at[2] + vim.api.nvim_win_get_width(w)
end

-- Where the tool's input box starts, as a line of its terminal buffer: the bottom-most
-- prompt line (Claude ❯, Codex ›, Antigravity >) plus the rule / blank padding just
-- above it. Bottom-most, because your earlier questions show up with the same mark
-- higher up in the chat.
local function tool_of(buf)
  if vim.bo[buf].filetype == 'claudecode' then return 'claude' end
  local n = vim.api.nvim_buf_get_name(buf)
  if n:find('codex', 1, true) then return 'codex' end
  if n:find('agy', 1, true) then return 'agy' end
end
local function is_prompt(tool, l)
  if tool == 'claude' then return l:find('^❯') ~= nil end
  if tool == 'codex' then return l:find('^›') ~= nil end
  if tool == 'agy' then return l == '>' or l:find('^> ') ~= nil end
end
local function rule_or_blank(l) return (l:gsub('─', '')):match('^%s*$') ~= nil end
local function input_top(buf)
  local tool = tool_of(buf)
  if not tool then return nil end
  local n = vim.api.nvim_buf_line_count(buf)
  local from = math.max(1, n - 60)
  local lines = vim.api.nvim_buf_get_lines(buf, from - 1, n, false)
  for i = #lines, 1, -1 do
    if is_prompt(tool, lines[i]) then
      local top = i
      while top > 1 and rule_or_blank(lines[top - 1]) do top = top - 1 end
      return from + top - 1
    end
  end
end

-- Is `buf` one of the AI terminals (Claude Code's, or a panel made below)?
local function is_ai_term(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= 'terminal' then return false end
  if vim.bo[buf].filetype == 'claudecode' then return true end
  if vim.b[buf].ai_chat then return true end   -- a panel that has just exited (it left `panels`)
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

-- Windows that aren't popups. (Popups are in the window list too, so "more than one
-- window" was true with one panel + a notification, and hiding it failed: E444.)
local function real_wins()
  return vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == '' end,
    vim.api.nvim_tabpage_list_wins(0))
end
-- Real windows that aren't AI panels (your code, the file tree...), other than `except`.
local function code_wins(except)
  return vim.tbl_filter(function(w) return w ~= except and not is_ai_term(vim.api.nvim_win_get_buf(w)) end, real_wins())
end
-- The panels never squeeze your code below MIN_CODE columns (it used to shrink a bit
-- more every time Claude opened next to another panel, down to 1 column).
local MIN_CODE = 40
local function keep_code_room()
  local panel = other_panel_win()
  if not panel or #code_wins() == 0 then return end
  local maxw = vim.o.columns - MIN_CODE - 1
  if vim.api.nvim_win_get_width(panel) > maxw then
    log('panel column was %d wide, code squeezed: back to 40%%', vim.api.nvim_win_get_width(panel))
    pcall(vim.api.nvim_win_set_width, panel, math.max(40, math.min(maxw, math.floor(vim.o.columns * 0.4))))
  end
end

-- The panel column's width as you last had it (dragging the divider updates it).
-- Only read while the layout is settled, i.e. all panels in one column: when Claude
-- opens next to another panel, the Claude plugin first adds a column of its own, which
-- squeezes the panel column until tidy() moves Claude under the other panel.
local col_width
vim.api.nvim_create_autocmd('WinResized', {
  group = vim.api.nvim_create_augroup('ai_panel_width', { clear = true }),
  callback = function()
    local cols, w = {}, nil
    for _, x in ipairs(real_wins()) do
      if is_ai_term(vim.api.nvim_win_get_buf(x)) then cols[vim.api.nvim_win_get_position(x)[2]] = true; w = x end
    end
    if w and vim.tbl_count(cols) == 1 and #code_wins() > 0 then col_width = vim.api.nvim_win_get_width(w) end
  end,
})

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
      if #real_wins() > 1 then vim.api.nvim_win_hide(win) end
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
  vim.b[p.buf].ai_chat = true
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
  elseif cmd == 'agy' then
    -- Continue the last Antigravity chat in this repo, or start a new one if there's none.
    -- Same safety net as Codex: if resuming fails straight away, start fresh instead.
    local id = agy_last_chat(root)
    log('agy: %s', id and ('resuming chat ' .. id) or 'no earlier chat here, starting a new one')
    if id then
      argv = vim.list_extend(vim.deepcopy(ENV), { 'sh', '-c', [[
        t=$(date +%s)
        agy --conversation "$1"; rc=$?
        if [ $rc -ne 0 ] && [ $(( $(date +%s) - t )) -lt 5 ]; then exec agy; fi
        exit $rc]], 'sh', id })
    end
  end
  p.chan = vim.fn.jobstart(argv, {
    term = true,
    cwd = root,
    on_exit = function()
      vim.schedule(function()
        panels[key] = nil
        -- closing the window / quitting nvim is done by chat_exited (same for Claude)
        if vim.api.nvim_buf_is_valid(p.buf) then
          log('%s exited', cmd)
          chat_exited(p.buf)
        end
      end)
    end,
  })
  -- The name can already be taken, e.g. Harpoon pinned a chat and, with the chat not
  -- running, opened an empty file of that name: setting it again failed (E95) and
  -- left the panel half set up. Then use the next free "name 2", "name 3"...
  local name = cmd .. ' (' .. vim.fn.fnamemodify(root, ':t') .. ')'
  local ok_name = pcall(vim.api.nvim_buf_set_name, p.buf, name)
  for n = 2, 9 do
    if ok_name then break end
    ok_name = pcall(vim.api.nvim_buf_set_name, p.buf, name .. ' ' .. n)
  end
  if not ok_name then log('%s: could not name the panel (name taken)', cmd) end
  watch_redraws(p.buf, cmd)
end

vim.keymap.set('n', '<leader>cx', function() toggle('codex') end, { desc = 'Codex: open (continue last chat) / jump to it' })
vim.keymap.set('n', '<leader>cg', function() toggle('agy') end, { desc = 'Antigravity: open (continue last chat) / jump to it' })

-- Send the visual selection (with file:lines) or this file's path into the
-- Codex / Antigravity prompt, without submitting, so you can type your question after it.
-- If it isn't running yet it is opened and the snippet goes to the clipboard.
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

-- The send keys work on code in a file. Pressed inside a panel (e.g. text selected in
-- Claude's panel) they used to send the panel itself: Claude showed an error
-- ("path does not exist"), Codex got junk.
local function not_in_file()
  if vim.bo.buftype == '' then return false end
  vim.schedule(function()
    vim.notify('This sends code from a file: select it in your code window (Ctrl h gets you there).', vim.log.levels.WARN)
  end)
  return true
end

local function send_selection(cmd)
  if not_in_file() then return vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false) end
  local root = repo_root()
  local s, e = vim.fn.line('v'), vim.fn.line('.')
  if s > e then s, e = e, s end
  local lines = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  local text = ('%s:%d-%d\n```%s\n%s\n```\n'):format(rel_path(root), s, e, vim.bo.filetype, table.concat(lines, '\n'))
  send_to(cmd, text)
end

vim.keymap.set('x', '<leader>cx', function() send_selection('codex') end, { desc = 'Send selection to Codex' })
vim.keymap.set('n', '<leader>cX', function()
  if not_in_file() then return end
  send_to('codex', rel_path(repo_root()) .. ' ')
end, { desc = 'Add this file to Codex prompt' })
vim.keymap.set('x', '<leader>cg', function() send_selection('agy') end, { desc = 'Send selection to Antigravity' })
vim.keymap.set('n', '<leader>cG', function()
  if not_in_file() then return end
  send_to('agy', rel_path(repo_root()) .. ' ')
end, { desc = 'Add this file to Antigravity prompt' })

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
      -- no "Native terminal opened..." popup: it sat over the top of the Claude panel for a
      -- few seconds, and a drag that started on it went to nvim instead of Claude
      show_native_term_exit_tip = false,
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
  vim.keymap.set('x', '<leader>ca', function()
    if not_in_file() then return '<Esc>' end
    return '<cmd>ClaudeCodeSend<CR>'
  end, { expr = true, desc = 'Send selection to Claude' })
  vim.keymap.set('n', '<leader>ca', function()
    if not not_in_file() then vim.cmd('ClaudeCodeAdd %') end
  end, { desc = 'Add this file to Claude' })
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
  local focused = vim.api.nvim_get_current_win() == win
  local name = vim.api.nvim_buf_get_name(buf):match('[^/:]+$') or '?'

  if #code_wins(win) == 0 then
    -- The chat landed in your only code window (Harpoon, :b, a tab click...). Treating
    -- that window as a stray panel closed it: no code window left. Give it its file
    -- back and show the chat in the panel column instead.
    log('%s landed in the only code window (win%d); file back there, chat to the panel column', name, win)
    vim.api.nvim_win_call(win, function()
      local alt = vim.fn.bufnr('#')
      if alt > 0 and alt ~= buf and vim.bo[alt].buftype == '' then vim.cmd('buffer ' .. alt) else vim.cmd('enew') end
    end)
    local col_w = other and (col_width or vim.api.nvim_win_get_width(other))
    if other then
      vim.api.nvim_set_current_win(other)
      vim.cmd('belowright split')
    else
      vim.api.nvim_set_current_win(win)
      vim.cmd('botright vertical ' .. math.max(40, math.floor(vim.o.columns * 0.4)) .. 'split')
    end
    local nw = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(nw, buf)
    vim.wo[nw].winfixwidth = true
    if col_w then pcall(vim.api.nvim_win_set_width, other, col_w) end
    if not focused then vim.api.nvim_set_current_win(win) end
    return
  end

  if other and vim.api.nvim_win_get_position(other)[2] ~= vim.api.nvim_win_get_position(win)[2] then
    log('stacking %s (win%d) under the other panel (win%d)', name, win, other)
    local col_w = col_width or vim.api.nvim_win_get_width(other)
    vim.api.nvim_win_close(win, false)            -- buffer just hides; the session keeps running
    vim.api.nvim_set_current_win(other)
    vim.cmd('belowright split')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    -- the closed column's space went to the panel column: put it back to the width
    -- you had, so the rest goes to the code
    pcall(vim.api.nvim_win_set_width, other, col_w)
    if not focused then vim.cmd('wincmd p') end
  end
  vim.wo[win].winfixwidth = true
  keep_code_room()
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

-- Codex / Antigravity: nvim does the selecting there. Dragging a selection past the
-- panel's top (to see further up) only scrolled as far as the pointer had moved past
-- the edge, and stopped as soon as it stopped moving: a trackpad held still sends
-- nothing. A normal terminal keeps scrolling, so do the same: while the drag sits past
-- the top or bottom edge, keep scrolling and extending the selection, faster the
-- further out the pointer is, until you release or come back inside.
local edge = { timer = nil, win = nil, dir = 0, speed = 1 }
local function edge_stop()
  if edge.timer then edge.timer:stop(); edge.timer:close(); edge.timer = nil end
end
-- A selection dragged from the chat stops at the last line above the input box: the
-- box and the status lines under it never get copied along by accident. (A drag that
-- starts inside the box, to copy what you typed, is left alone.)
local function clamp_selection()
  local w = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(w)
  if not vim.fn.mode():match('^[vV\22]') then return end
  local top = input_top(buf)
  if not top or top <= 1 or vim.fn.getpos('v')[2] >= top or vim.fn.line('.') < top then return end
  local last = vim.api.nvim_buf_get_lines(buf, top - 2, top - 1, false)[1] or ''
  vim.api.nvim_win_set_cursor(w, { top - 1, math.max(0, #last - 1) })
end
local function edge_tick()
  local w = edge.win
  if not (w and vim.api.nvim_win_is_valid(w)) or vim.api.nvim_get_current_win() ~= w
      or not vim.fn.mode():match('^[vV\22]') then
    return edge_stop()
  end
  if edge.dir < 0 and vim.fn.line('w0') <= 1 then return end            -- already at the top
  if edge.dir > 0 and vim.fn.line('w$') >= vim.fn.line('$') then return end
  if edge.dir > 0 then                                                  -- not into the input box
    local top = input_top(vim.api.nvim_win_get_buf(w))
    if top and vim.fn.getpos('v')[2] < top and vim.fn.line('.') >= top - 1 then return end
  end
  vim.api.nvim_feedkeys(edge.speed .. (edge.dir < 0 and 'k' or 'j'), 'n', false)
end
local function edge_drag()
  vim.api.nvim_feedkeys(vim.keycode('<LeftDrag>'), 'n', false)        -- nvim extends the selection as usual
  vim.schedule(clamp_selection)
  local w, pos = vim.api.nvim_get_current_win(), vim.fn.getmousepos()
  local top = vim.api.nvim_win_get_position(w)[1]
  local r = pos.screenrow - 1
  local over, under = top - r, r - (top + vim.api.nvim_win_get_height(w) - 1)
  if over <= 0 and under <= 0 then return edge_stop() end
  edge.win, edge.dir, edge.speed = w, over > 0 and -1 or 1, math.min(5, math.max(over, under))
  if not edge.timer then
    edge.timer = vim.uv.new_timer()
    edge.timer:start(60, 60, vim.schedule_wrap(edge_tick))
  end
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
          -- (Ctrl-h in normal mode too, e.g. after copying: there it's otherwise Harpoon's
          -- "pinned file 1", which opened that file inside the panel)
          vim.keymap.set({ 't', 'n' }, '<C-h>', back_to_code, { buffer = buf, desc = 'Back to code (panel stays)' })
          vim.keymap.set('t', '<C-\\><C-\\>', back_to_code, { buffer = buf, desc = 'Back to code (panel stays)' })
          -- Ctrl-q: hide this panel straight from typing mode and go back to the code.
          -- The session keeps running; Space c c / Space c x brings it back as it was.
          vim.keymap.set({ 't', 'n' }, '<C-q>', function()
            local win = vim.api.nvim_get_current_win()
            back_to_code()
            if #real_wins() > 1 and vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_hide(win)
            end
          end, { buffer = buf, desc = 'Hide panel (session keeps running)' })
          -- Codex doesn't take the mouse (Claude does), so nvim handles a click in its
          -- panel and drops you into normal mode. A plain click now goes straight back
          -- to typing; a drag / double-click still selects text (visual mode, y copies),
          -- and the scroll wheel still scrolls back through the output.
          -- Scrolled up, typing again jumps to the bottom, so wait out a possible
          -- double-click first (it selects a word): going back at once made the second
          -- click land on whatever had scrolled under the mouse.
          vim.keymap.set('n', '<LeftRelease>', function()
            if not vim.api.nvim_get_mode().mode:match('^n') then return end   -- 'nt' = normal mode in a terminal
            if vim.fn.line('w$') >= vim.fn.line('$') then return vim.cmd('startinsert') end
            local w = vim.api.nvim_get_current_win()
            vim.defer_fn(function()
              if vim.api.nvim_get_current_win() == w and vim.api.nvim_get_mode().mode == 'nt' then vim.cmd('startinsert') end
            end, vim.o.mousetime + 50)
          end, { buffer = buf, desc = 'Click in panel: back to typing' })
        end
        -- Claude draws its chat itself and does its own selecting and copying, but only
        -- while you're typing in its panel. In nvim's normal mode there (after Ctrl-\
        -- Ctrl-n, or a click nvim handled) nvim only has Claude's current screen: scrolling
        -- stopped at its top, and a drag made an nvim selection that never reached the
        -- clipboard. So a mouse press there goes back to typing first and is handed on
        -- to Claude.
        if vim.bo[buf].filetype == 'claudecode' and not vim.b[buf].ai_claude_mouse then
          vim.b[buf].ai_claude_mouse = true
          vim.keymap.set('n', '<LeftMouse>', function()
            if mouse_in(vim.api.nvim_get_current_win(), vim.fn.getmousepos()) then
              vim.cmd('startinsert')
              -- 'm': goes through the typing-mode click handler below (notes where it started)
              return vim.api.nvim_feedkeys(vim.keycode('<LeftMouse>'), 'm', false)
            end
            vim.api.nvim_feedkeys(vim.keycode('<LeftMouse>'), 'n', false)
          end, { buffer = buf, desc = 'Click in Claude: back to typing, Claude handles it' })
          -- Drag-selecting up to make Claude scroll further only kept scrolling while the
          -- pointer sat exactly on the panel's top row (your pinned question). One row too
          -- far, over nvim's tab bar, and nvim took over the drag: Claude's selection and
          -- scrolling stopped dead. So keep sending the drag to Claude, pinned to the
          -- nearest edge of the panel (above it = its top row, so it keeps scrolling).
          -- Inside the panel nvim passes the event on exactly as before; outside it, the
          -- same event is re-sent at the nearest point on the panel's edge.
          -- Also: a drag that started in the chat never reaches the input box or the
          -- status lines under it (rows there count as the last row above the box).
          local function box_row(w)                       -- screen row (0-based) where the box starts
            local top = input_top(buf)
            if not top then return nil end
            return vim.api.nvim_win_get_position(w)[1] + (top - vim.fn.line('w0', w))
          end
          vim.keymap.set('t', '<LeftMouse>', function()
            local w, pos = vim.api.nvim_get_current_win(), vim.fn.getmousepos()
            local br = vim.api.nvim_win_get_buf(w) == buf and mouse_in(w, pos) and box_row(w)
            vim.b[buf].ai_drag_in_chat = br and (pos.screenrow - 1) < br or false
            vim.api.nvim_feedkeys(vim.keycode('<LeftMouse>'), 'n', false)
          end, { buffer = buf, desc = 'Click in Claude' })
          local function keep_in_claude(lhs, action)
            return function()
              local w, pos = vim.api.nvim_get_current_win(), vim.fn.getmousepos()
              if vim.api.nvim_win_get_buf(w) ~= buf then return vim.api.nvim_feedkeys(vim.keycode(lhs), 'n', false) end
              local at = vim.api.nvim_win_get_position(w)
              local row = math.max(at[1], math.min(at[1] + vim.api.nvim_win_get_height(w) - 1, pos.screenrow - 1))
              local col = math.max(at[2], math.min(at[2] + vim.api.nvim_win_get_width(w) - 1, pos.screencol - 1))
              local br = vim.b[buf].ai_drag_in_chat and box_row(w)
              if br and row >= br then row = math.max(at[1], br - 1) end
              if action == 'release' then vim.b[buf].ai_drag_in_chat = false end
              if row == pos.screenrow - 1 and col == pos.screencol - 1 then
                return vim.api.nvim_feedkeys(vim.keycode(lhs), 'n', false)   -- unchanged: as usual
              end
              vim.api.nvim_input_mouse('left', action, '', 0, row, col)
            end
          end
          vim.keymap.set('t', '<LeftDrag>', keep_in_claude('<LeftDrag>', 'drag'), { buffer = buf, desc = 'Drag in Claude (kept in the panel)' })
          vim.keymap.set('t', '<LeftRelease>', keep_in_claude('<LeftRelease>', 'release'), { buffer = buf, desc = 'Release in Claude (kept in the panel)' })
        end
        if vim.bo[buf].filetype ~= 'claudecode' and not vim.b[buf].ai_edge_scroll then
          vim.b[buf].ai_edge_scroll = true
          vim.keymap.set('x', '<LeftDrag>', edge_drag, { buffer = buf, desc = 'Drag-select (keeps scrolling past the edge)' })
          vim.keymap.set('x', '<LeftRelease>', function()
            edge_stop()
            vim.api.nvim_feedkeys(vim.keycode('<LeftRelease>'), 'n', false)
            vim.schedule(clamp_selection)
          end, { buffer = buf, desc = 'End drag-select' })
          -- the first drag (it starts the selection) comes in normal mode
          vim.keymap.set('n', '<LeftDrag>', function()
            vim.api.nvim_feedkeys(vim.keycode('<LeftDrag>'), 'n', false)
            vim.schedule(clamp_selection)
          end, { buffer = buf, desc = 'Drag-select (stops above the input box)' })
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
local wheel
function wheel(dir)
  local key = vim.keycode('<ScrollWheel' .. dir .. '>')
  local function default() vim.api.nvim_feedkeys(key, 'n', false) end
  local pos = vim.fn.getmousepos()
  local win = pos.winid
  -- over the tab bar / status line: nothing to scroll there, and passing it on dropped
  -- you out of typing in the panel you were in
  if win == 0 or (vim.api.nvim_win_is_valid(win) and not mouse_in(win, pos)) then return end
  if not vim.api.nvim_win_is_valid(win) then return default() end
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
    -- Scrolling into Codex / Antigravity: stay out of typing to look back. If you were
    -- typing in another panel, leave typing *before* switching: switching while typing
    -- carried typing mode over, which jumped this panel to the bottom (place lost).
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    local function enter()
      if not vim.api.nvim_win_is_valid(win) then return end
      skip_auto_insert = true
      vim.api.nvim_set_current_win(win)
      vim.fn.winrestview(view)
      wheel(dir)              -- now it's the current panel and you're not typing
    end
    if typing then vim.cmd('stopinsert'); vim.schedule(enter) else enter() end
    return
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

-- A chat's process ended (/exit, Ctrl-d, a crash): never leave its "[Process exited]"
-- window on screen (it stayed open full screen once the code window had been closed).
--  * your code is still on screen: the chat's window closes, and if you were in that
--    chat you land in the code, in normal mode (code windows are never resized)
--  * no code left: if nothing else needs nvim (no other chat running, nothing unsaved)
--    nvim quits to the shell; otherwise it stays and shows your last file (or the
--    folder), and says why
local function is_blank_win(w)
  local b = vim.api.nvim_win_get_buf(w)
  return vim.bo[b].buftype == '' and vim.api.nvim_buf_get_name(b) == '' and not vim.bo[b].modified
    and vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ''
end
-- Another chat whose process is still alive (visible or hidden with Ctrl q).
local function running_chat(except)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= except and is_ai_term(b) then
      local ch = vim.bo[b].channel
      if ch and ch > 0 and vim.fn.jobwait({ ch }, 0)[1] == -1 then return b end
    end
  end
end
local function modified_file()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == '' and vim.bo[b].modified then return b end
  end
end
-- Your most recently used file in window `w`, or the folder if you have none open.
local function show_last_file(w)
  local best
  for _, i in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if i.name ~= '' and vim.bo[i.bufnr].buftype == '' and (not best or i.lastused > best.lastused) then best = i end
  end
  vim.api.nvim_win_call(w, function()
    if best then vim.cmd('buffer ' .. best.bufnr) else vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd())) end
    -- it was a chat window: take back the normal look (the chat made it narrow and number-less)
    vim.cmd('setlocal winfixwidth< number< relativenumber< signcolumn<')
  end)
end

local function settle_chat(buf, was_in_it)
  local tab = vim.api.nvim_get_current_tabpage()
  local function chat_wins()
    if not vim.api.nvim_buf_is_valid(buf) then return {} end
    return vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative == '' and vim.api.nvim_win_get_tabpage(w) == tab
    end, vim.fn.win_findbuf(buf))
  end
  local cw = chat_wins()
  local function is_chat_win(w) return vim.tbl_contains(cw, w) end
  local function drop_buf() if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end end

  -- windows with something to work on: not a chat, not an empty page, not just the file tree
  local content = vim.tbl_filter(function(w)
    local b = vim.api.nvim_win_get_buf(w)
    return not is_chat_win(w) and not is_ai_term(b) and not is_blank_win(w) and vim.bo[b].filetype ~= 'NvimTree'
  end, real_wins())

  if #content > 0 then
    -- the code stays: only the chat's window goes (a chat in the last window can't happen here)
    for _, w in ipairs(cw) do pcall(vim.api.nvim_win_close, w, true) end
    drop_buf()
    log('chat exited; closed its window, code stays')
    if was_in_it or vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative ~= '' then
      back_to_code()   -- (also leaves typing mode)
      if is_ai_term(vim.api.nvim_get_current_buf()) or not vim.api.nvim_win_is_valid(vim.api.nvim_get_current_win()) then
        pcall(vim.api.nvim_set_current_win, content[1])
      end
    end
    if not is_ai_term(vim.api.nvim_get_current_buf()) then vim.cmd('stopinsert') end
    keep_code_room()
    return
  end

  -- no code left
  local other = running_chat(buf)
  local dirty = modified_file()
  if not other and not dirty and vim.fn.tabpagenr('$') == 1 then
    local ok, err = pcall(vim.cmd, 'qa')
    if ok then return end
    err = tostring(err):match('E%d+:.*') or tostring(err)
    vim.notify('nvim stayed open: ' .. err, vim.log.levels.WARN)   -- e.g. one of your own terminals is running
  elseif dirty then
    local n = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(dirty), ':t')
    vim.notify(('nvim stayed open: %s has unsaved changes.'):format(n ~= '' and n or 'a buffer'), vim.log.levels.WARN)
  elseif other then
    local n = vim.api.nvim_buf_get_name(other):match('[^/:]+$') or 'a chat'
    vim.notify(('nvim stayed open: %s is still running.'):format(n), vim.log.levels.WARN)
  end
  log('chat exited with no code window left; nvim stays open')

  -- an empty page is the natural spot for the file; else the chat's own window if it's all
  -- alone; else (other chats are on screen) a new window to their left
  local target
  for _, w in ipairs(real_wins()) do
    if not is_chat_win(w) and not is_ai_term(vim.api.nvim_win_get_buf(w)) and is_blank_win(w) then target = w; break end
  end
  if not target then
    local others = vim.tbl_filter(function(w) return not is_chat_win(w) end, real_wins())
    if #others == 0 and cw[1] then
      target = cw[1]
    else
      local keep = vim.api.nvim_get_current_win()
      if #cw > 0 and #others > 0 then pcall(vim.api.nvim_set_current_win, others[1]) end
      vim.cmd('topleft vsplit')
      target = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_is_valid(keep) and not was_in_it then pcall(vim.api.nvim_set_current_win, keep) end
    end
  end
  show_last_file(target)
  -- the chats had the whole screen: give them back their usual 40% and the rest to the file
  local panel = other_panel_win(target)
  if panel and panel ~= target and vim.api.nvim_win_get_position(panel)[2] > 0 then
    pcall(vim.api.nvim_win_set_width, panel, math.floor(vim.o.columns * 0.4))
  end
  for _, w in ipairs(cw) do
    if w ~= target and vim.api.nvim_win_is_valid(w) and #real_wins() > 1 then pcall(vim.api.nvim_win_close, w, true) end
  end
  drop_buf()
  if was_in_it and vim.api.nvim_win_is_valid(target) then vim.api.nvim_set_current_win(target) end
  if not is_ai_term(vim.api.nvim_get_current_buf()) then vim.cmd('stopinsert') end
  keep_code_room()
end

local handled = {}
-- Called when a chat's process ended (by toggle()'s on_exit and the TermClose below; the
-- first one wins). Waits a moment so Claude's own exit handling is finished first.
chat_exited = function(buf)
  if handled[buf] then return end
  handled[buf] = true
  local was_in_it = vim.api.nvim_get_current_buf() == buf
  vim.defer_fn(function()
    local ok, err = pcall(settle_chat, buf, was_in_it)
    if not ok then log('settle_chat failed: %s', tostring(err)) end
  end, 150)
end
vim.api.nvim_create_autocmd('TermClose', {
  group = vim.api.nvim_create_augroup('ai_quit_when_empty', { clear = true }),
  callback = function(ev)
    if is_ai_term(ev.buf) then chat_exited(ev.buf) end
  end,
})
