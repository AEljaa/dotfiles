-- A PDF shown in an iTerm split pane on the right of this nvim (tdf, reloads by itself
-- when the file changes). Used by markdown.lua and latex.lua. Inside tmux it splits the
-- iTerm tab you're typing in (tmux just gets narrower). Outside iTerm it uses Skim.
-- Not on a Mac (Linux / WSL / Windows): an ordinary PDF app instead, see open_external.
local M = {}
local platform = require('adameljaa.platform')

M.can_split = platform.mac and (vim.env.ITERM_SESSION_ID ~= nil or vim.env.LC_TERMINAL == 'iTerm2')
local can_split = M.can_split
local pane_id, shown = nil, nil      -- iTerm session id of the pane, PDF it shows
local saved_bounds = nil             -- iTerm window size before Skim was put beside it

-- act: exists | close | split (argv 3 = command). Finds an iTerm session by id.
local PANE_AS = [[
on run argv
  set act to item 1 of argv
  set sid to item 2 of argv
  tell application "iTerm"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is sid then
            if act is "exists" then return "yes"
            if act is "close" then
              close s
              return "closed"
            end if
            if act is "split" then
              tell s to set p to (split vertically with default profile command (item 3 of argv))
              tell s to select
              return unique id of p
            end if
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return ""
end run
]]

-- iTerm on the left half, the Skim window showing argv[1] on the right; prints
-- iTerm's old size so close() can put it back.
local TILE_JS = [[
ObjC.import('AppKit');
function run(argv) {
  const pdf = argv[0];
  const v = $.NSScreen.mainScreen.visibleFrame;
  const H = $.NSScreen.screens.objectAtIndex(0).frame.size.height;
  const x = v.origin.x, y = H - (v.origin.y + v.size.height), w = v.size.width, h = v.size.height;
  const left = Math.round(w / 2);
  let found = false;
  for (const win of Application('Skim').windows()) {
    try { if (win.document().name() === pdf) { win.bounds = { x: x + left, y: y, width: w - left, height: h }; found = true; break; } } catch (e) {}
  }
  if (!found) return 'nopdf';
  const it = Application('iTerm').currentWindow;
  const before = JSON.stringify(it.bounds());
  it.bounds = { x: x, y: y, width: left, height: h };
  return before;
}
]]

local CLOSE_SKIM_JS = [[
function run(argv) {
  const app = Application('Skim');
  if (app.running()) {
    for (const d of app.documents()) { try { if (d.file().toString() === argv[0]) d.close(); } catch (e) {} }
  }
  if (argv[1]) Application('iTerm').currentWindow.bounds = JSON.parse(argv[1]);
}
]]

local function osa(lang, script, args, cb)
  local cmd = vim.list_extend({ 'osascript', '-l', lang, '-e', script }, args or {})
  if cb then return vim.system(cmd, { text = true }, vim.schedule_wrap(cb)) end
  return vim.trim(vim.system(cmd, { text = true }):wait().stdout or '')
end

-- The iTerm session to split: this nvim's own, or inside tmux (where the id belongs to
-- whichever tab started tmux) the one you're typing in right now.
function M.host_session()
  if not vim.env.TMUX and vim.env.ITERM_SESSION_ID then return vim.env.ITERM_SESSION_ID:match(':(.+)$') end
  local id = osa('AppleScript', 'tell application "iTerm" to get unique id of current session of current window')
  return id ~= '' and id or nil
end

local function tile(pdf, tries)
  if vim.env.TERM_PROGRAM ~= 'iTerm.app' and not vim.env.ITERM_SESSION_ID then return end
  osa('JavaScript', TILE_JS, { vim.fs.basename(pdf) }, function(r)
    local out = vim.trim(r.stdout or '')
    if out == 'nopdf' then
      if tries > 0 then vim.defer_fn(function() tile(pdf, tries - 1) end, 400) end   -- Skim still opening
    elseif out ~= '' then
      saved_bounds = saved_bounds or out
    end
  end)
end

function M.is_open()
  return pane_id ~= nil and osa('AppleScript', PANE_AS, { 'exists', pane_id }) == 'yes'
end

---------------------------------------------------------------- not a Mac
-- Opened once and left open: zathura (and most PDF apps) reload by themselves when the
-- file changes. zathura also gets the cursor position (`tex`, `line`), like Skim does.
local ext = { job = nil, pdf = nil }

local function ext_running()
  return ext.job ~= nil and vim.fn.jobwait({ ext.job }, 0)[1] == -1
end

function M.close_external()
  local closed = ext_running() or ext.pdf ~= nil
  if ext_running() then vim.fn.jobstop(ext.job) end
  ext.job, ext.pdf = nil, nil
  return closed
end

function M.open_external(pdf, tex, line)
  local zathura = vim.fn.executable('zathura') == 1
  local sync = (zathura and tex and line) and { '--synctex-forward', line .. ':1:' .. tex } or {}
  if ext.pdf == pdf and (ext_running() or not ext.job) then
    -- already showing it: just move zathura to the cursor (talks to the open window)
    if zathura and #sync > 0 and ext_running() then
      vim.system(vim.list_extend({ 'zathura' }, vim.list_extend(sync, { pdf })))
    end
    return
  end
  M.close_external()
  local cmd
  if zathura then
    cmd = vim.list_extend(vim.list_extend({ 'zathura' }, sync), { pdf })
    -- LaTeX: Ctrl+click in zathura jumps nvim to that line (vimtex inverse search)
    if tex then table.insert(cmd, 2, '-x'); table.insert(cmd, 3, [[nvim --headless -c "VimtexInverseSearch %{line} '%{input}'"]]) end
  elseif platform.wsl and vim.fn.executable('wslview') == 1 then
    cmd = { 'wslview', pdf }
  elseif platform.wsl then
    cmd = { 'explorer.exe', vim.trim(vim.fn.system({ 'wslpath', '-w', pdf })) }
  end
  ext.pdf = pdf
  if cmd then
    ext.job = vim.fn.jobstart(cmd, { detach = false })
  else
    vim.ui.open(pdf)   -- whatever the system uses for PDFs (xdg-open / Windows default app)
  end
end

---------------------------------------------------------------- open / close
function M.open(pdf)
  if not platform.mac then return M.open_external(pdf) end
  if not can_split then
    local first = shown ~= pdf
    vim.system({ 'open', '-g', '-a', 'Skim', pdf })   -- -g: keep focus in the terminal
    shown = pdf
    if first then tile(pdf, 10) end                   -- side by side, so it's not hidden behind iTerm
    return
  end
  if M.is_open() then
    if shown == pdf then return end                     -- tdf reloads by itself
    osa('AppleScript', PANE_AS, { 'close', pane_id })   -- a different file: swap it
  end
  shown = pdf
  local tdf = vim.fn.exepath('tdf'); if tdf == '' then tdf = '/opt/homebrew/bin/tdf' end
  local cmd = vim.fn.shellescape(tdf) .. ' -f ' .. vim.fn.shellescape(pdf)   -- -f: just the page
  local host = M.host_session()
  if not host then return vim.notify('Could not find the iTerm tab to split', vim.log.levels.ERROR) end
  osa('AppleScript', PANE_AS, { 'split', host, cmd }, function(r)
    local id = vim.trim(r.stdout or '')
    pane_id = id ~= '' and id or nil
    if not pane_id then vim.notify('Could not open the PDF pane: ' .. (r.stderr or ''), vim.log.levels.ERROR) end
  end)
end

-- Returns true if something was closed.
function M.close()
  if not platform.mac then return M.close_external() end
  local closed = false
  if M.is_open() then osa('AppleScript', PANE_AS, { 'close', pane_id }); closed = true end
  if not can_split and shown then osa('JavaScript', CLOSE_SKIM_JS, { shown, saved_bounds or '' }); closed = true end
  pane_id, shown, saved_bounds = nil, nil, nil
  return closed
end

return M
