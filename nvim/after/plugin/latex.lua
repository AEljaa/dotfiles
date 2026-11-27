-- LaTeX like Overleaf: code on the left, compiled PDF on the right.
--
--   Space l l   compile + PDF in a terminal pane on the right (tdf, inside iTerm).
--               From then on every :w recompiles and the PDF reloads.
--               In the PDF pane: j/k or arrows = pages, / = search, i = dark mode,
--               q = close it (nvim goes back to full width). Space l q also closes it.
--               Move between panes: Cmd+[ / Cmd+]  (or Cmd+Opt+arrows)
--   Space l s   same, but in the Skim app instead (sharper, and synced: the PDF follows
--               your cursor, Cmd+Shift+click in it jumps nvim to that line).
--               Space l q closes Skim's PDF and gives iTerm its full size back.
--   Space l v   (Skim) scroll the PDF to where your cursor is
--   Space l e   list of errors / warnings          Space l o   full compiler output
--   Space l t   table of contents (jump to section) Space l c   delete .aux/.log/... files
--
-- nvim's own :terminal can't draw images, which is why the PDF pane is an iTerm split
-- and not a panel like Space c c.
-- Compiler: tectonic (brew). It downloads any \usepackage it doesn't have on first
-- use (first compile of a new document is slow), like Overleaf. Engine is XeTeX, so
-- \usepackage[utf8]{inputenc} etc. are harmless no-ops.
-- Skim settings already done via `defaults write`: auto-reload on change, and
-- Sync -> Custom: /opt/homebrew/bin/nvim --headless -c "VimtexInverseSearch %line '%file'"

-- tectonic/tdf live in Homebrew; make sure nvim finds them even when not started from a shell
if vim.fn.has('mac') == 1 and not vim.env.PATH:find('/opt/homebrew/bin', 1, true) then vim.env.PATH = '/opt/homebrew/bin:' .. vim.env.PATH end

vim.g.tex_flavor = 'latex'                  -- .tex is LaTeX, not plain TeX
vim.g.vimtex_compiler_method = 'tectonic'
-- vimtex's own viewer hook would launch Skim after every build, even when you use the
-- terminal pane, so the viewers are driven from this file instead.
vim.g.vimtex_view_enabled = 0
vim.g.vimtex_quickfix_mode = 2              -- on errors: show the list, don't jump into it
vim.g.vimtex_quickfix_open_on_warning = 0   -- warnings alone (overfull hbox...) don't pop it up

local live = false        -- set by Space l l / s: recompile on every save
local viewer = 'term'     -- 'term' (tdf in an iTerm split) or 'skim'
local pending_pdf = nil   -- PDF to show once the first compile succeeds
local queued = false      -- saved again while compiling: run once more afterwards
local build = nil         -- { pdf, log, start, tex, line } of the compile in progress
local pane_id = nil       -- iTerm session id of the tdf pane
local saved_bounds = nil  -- iTerm window size before Skim was put beside it

local pdfpane = require('adameljaa.pdfpane')
-- Not a Mac: no iTerm / Skim, so every view (Space l l, l s, l v) goes to an ordinary
-- PDF app via pdfpane.open_external (zathura if installed: follows your cursor, and
-- Ctrl+click in it jumps nvim to that line).
local platform = require('adameljaa.platform')
local can_split = pdfpane.can_split   -- in iTerm (also inside tmux); otherwise Skim

local function osa(lang, script, args, cb)
  local cmd = { 'osascript', '-l', lang, '-e', script }
  vim.list_extend(cmd, args or {})
  if cb then return vim.system(cmd, { text = true }, vim.schedule_wrap(cb)) end
  return vim.trim(vim.system(cmd, { text = true }):wait().stdout or '')
end

---------------------------------------------------------------- terminal pane (tdf)
-- act: exists | close | split (argv 3 = command). Finds this nvim's iTerm session by id.
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

local function pane_open() return pane_id ~= nil and osa('AppleScript', PANE_AS, { 'exists', pane_id }) == 'yes' end

local function show_term(pdf)
  if pane_open() then return end              -- tdf reloads the file by itself
  local tdf = vim.fn.exepath('tdf'); if tdf == '' then tdf = '/opt/homebrew/bin/tdf' end
  local cmd = vim.fn.shellescape(tdf) .. ' -f ' .. vim.fn.shellescape(pdf)   -- -f: just the page, no title/borders/status
  local host = pdfpane.host_session()
  if not host then return vim.notify('Could not find the iTerm tab to split', vim.log.levels.ERROR) end
  osa('AppleScript', PANE_AS, { 'split', host, cmd }, function(r)
    pane_id = vim.trim(r.stdout or '') ~= '' and vim.trim(r.stdout) or nil
    if not pane_id then vim.notify('Could not open the PDF pane: ' .. (r.stderr or ''), vim.log.levels.ERROR) end
  end)
end

---------------------------------------------------------------- Skim
-- Open (or reload) `pdf` in Skim and scroll it to `line` of `tex`, without stealing focus.
local function skim_js(pdf, tex, line)
  return ([[
var app = Application("Skim"); var f = Path(%q);
try { var d = app.documents.whose({ file: { _equals: f } }); if (d.length > 0) app.revert(d) } catch (e) {}
app.open(f);
app.documents[0].go({ to: app.texLines[%d], from: Path(%q), showingReadingBar: true });
]]):format(pdf, math.max(line - 1, 0), tex)
end

-- Put this iTerm window on the left half and the Skim window showing `pdf` on the right.
-- Prints iTerm's size from before, so Space l q can put it back.
local TILE_JS = [[
ObjC.import('AppKit');
function run(argv) {
  const frac = parseFloat(argv[0]), pdf = argv[1];
  const v = $.NSScreen.mainScreen.visibleFrame;
  const H = $.NSScreen.screens.objectAtIndex(0).frame.size.height;
  const x = v.origin.x, y = H - (v.origin.y + v.size.height), w = v.size.width, h = v.size.height;
  const left = Math.round(w * frac);
  let found = false;
  for (const win of Application('Skim').windows()) {
    try {
      if (win.document().name() === pdf) {
        win.bounds = { x: x + left, y: y, width: w - left, height: h };
        found = true; break;
      }
    } catch (e) {}
  }
  if (!found) return 'nopdf';
  const it = Application('iTerm').currentWindow;
  const before = JSON.stringify(it.bounds());
  it.bounds = { x: x, y: y, width: left, height: h };
  return before;
}
]]

local function tile(pdf, tries)
  if vim.env.TERM_PROGRAM ~= 'iTerm.app' then return end   -- only know how to move iTerm
  osa('JavaScript', TILE_JS, { '0.5', vim.fs.basename(pdf) }, function(r)
    local out = vim.trim(r.stdout or '')
    if out == 'nopdf' then
      if tries > 0 then vim.defer_fn(function() tile(pdf, tries - 1) end, 400) end   -- Skim still opening
    elseif out ~= '' then
      saved_bounds = saved_bounds or out    -- keep the original size across re-tiles
    end
  end)
end

local function show_skim(pdf, tex, line, first)
  osa('JavaScript', skim_js(pdf, tex, line), nil, function() end)
  if first then tile(pdf, 10) end
end

local CLOSE_SKIM_JS = [[
function run(argv) {
  const app = Application('Skim');
  if (app.running()) {
    for (const d of app.documents()) { try { if (d.file().toString() === argv[0]) d.close(); } catch (e) {} }
  }
  if (argv[1]) Application('iTerm').currentWindow.bounds = JSON.parse(argv[1]);
}
]]

---------------------------------------------------------------- common
local function pdf_path() return vim.b.vimtex.root .. '/' .. vim.b.vimtex.name .. '.pdf' end

local function show(pdf, tex, line, first)
  if not platform.mac then return pdfpane.open_external(pdf, tex, line) end
  if viewer == 'skim' or not can_split then show_skim(pdf, tex, line, first)
  else show_term(pdf) end
end

local function close_viewer()
  if not platform.mac then
    if not pdfpane.close_external() then vim.notify('No PDF view open') end
    live, pending_pdf = false, nil
    return
  end
  local closed = false
  if pane_open() then osa('AppleScript', PANE_AS, { 'close', pane_id }); closed = true end
  pane_id = nil
  if viewer == 'skim' or saved_bounds then
    local pdf = vim.b.vimtex and pdf_path() or ''
    osa('JavaScript', CLOSE_SKIM_JS, { pdf, saved_bounds or '' })
    saved_bounds, closed = nil, true
  end
  live, pending_pdf = false, nil
  if not closed then vim.notify('No PDF view open') end
end

-- :VimtexCompile toggles (a second call stops a running compile), so a quick
-- second :w would cancel the build. Instead queue it and rebuild when this one ends.
local function compile()
  if vim.fn.eval('b:vimtex.compiler.is_running()') == 1 then queued = true return end
  local pdf = pdf_path()
  build = { pdf = pdf, log = (pdf:gsub('%.pdf$', '.log')), start = os.time(),
            tex = vim.api.nvim_buf_get_name(0), line = vim.fn.line('.') }
  vim.cmd('VimtexCompile')
end

-- First real error in the .log, as "line 47: Unable to load picture ... 'energy_plot.jpg'."
local function first_log_error(log)
  local ok, lines = pcall(vim.fn.readfile, log)
  if not ok then return nil end
  for i, l in ipairs(lines) do
    if l:match('^! ') then
      local msg = l:sub(3)
      for j = i + 1, math.min(i + 12, #lines) do
        local n = lines[j]:match('^l%.(%d+)')
        if n then return 'line ' .. n .. ': ' .. msg end
      end
      return msg
    end
  end
end

local function open_preview(mode)
  return function()
    if not vim.b.vimtex then
      vim.notify('Not a LaTeX file (or vimtex not loaded)', vim.log.levels.WARN)
      return
    end
    if mode ~= viewer then close_viewer() end    -- switching tdf <-> Skim
    viewer, live = mode, true
    local pdf = pdf_path()
    if vim.fn.filereadable(pdf) == 1 then
      show(pdf, vim.api.nvim_buf_get_name(0), vim.fn.line('.'), true)   -- old PDF now, refreshed after the build
    else
      pending_pdf = pdf                                                -- nothing yet: show after the build
    end
    vim.notify('Compiling ' .. vim.b.vimtex.name .. '.tex (new packages download on first use, can take a minute)…')
    if vim.bo.modified then vim.cmd('silent write') else compile() end   -- :w compiles via BufWritePost
  end
end

local grp = vim.api.nvim_create_augroup('latex_overleaf', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  group = grp, pattern = '*.tex',
  callback = function() if live and vim.b.vimtex then compile() end end,
})

-- These fire in whatever buffer is current when the build ends, so no vim.b here.
local function after_build(ok)
  local b = build
  build = nil
  -- vimtex decides "success" by parsing the log, and its parser misses some errors
  -- (e.g. a missing image). The real test: did this build write a new PDF?
  if b and vim.fn.getftime(b.pdf) < b.start then ok = false end
  if queued then
    queued = false
    vim.schedule(function() if vim.b.vimtex then compile() end end)
  end
  if ok and b and live then
    local first = pending_pdf ~= nil
    pending_pdf = nil
    -- terminal pane reloads by itself; Skim gets reloaded + scrolled to where you were typing
    if first or viewer == 'skim' or not can_split then show(b.pdf, b.tex, b.line, first) end
  end
  if not ok then
    local err = b and first_log_error(b.log)
    vim.notify('LaTeX build failed' .. (err and (':\n' .. err) or '') ..
      '\n(Space l e = error list, Space l o = full output)', vim.log.levels.ERROR)
  end
end
vim.api.nvim_create_autocmd('User', { group = grp, pattern = 'VimtexEventCompileSuccess', callback = function() after_build(true) end })
vim.api.nvim_create_autocmd('User', { group = grp, pattern = 'VimtexEventCompileFailed', callback = function() after_build(false) end })


vim.api.nvim_create_autocmd('FileType', {
  group = grp, pattern = 'tex',
  callback = function(ev)
    local function map(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc }) end
    map('<leader>ll', open_preview('term'), 'LaTeX: compile + PDF pane on the right')
    map('<leader>ls', open_preview('skim'), 'LaTeX: compile + PDF in Skim (synced)')
    map('<leader>lq', close_viewer, 'LaTeX: close the PDF view')
    map('<leader>lv', function()
      if not platform.mac then pdfpane.open_external(pdf_path(), vim.api.nvim_buf_get_name(0), vim.fn.line('.'))
      elseif viewer == 'skim' then show_skim(pdf_path(), vim.api.nvim_buf_get_name(0), vim.fn.line('.'), false)
      else vim.notify('Cursor sync needs Skim: Space l s') end
    end, 'LaTeX: show cursor position in PDF (Skim)')
    map('<leader>le', '<cmd>VimtexErrors<CR>', 'LaTeX: errors / warnings')
    map('<leader>lo', '<cmd>VimtexCompileOutput<CR>', 'LaTeX: compiler output')
    map('<leader>lt', '<cmd>VimtexTocToggle<CR>', 'LaTeX: table of contents')
    map('<leader>lc', '<cmd>VimtexClean<CR>', 'LaTeX: delete aux files')
    vim.wo.wrap, vim.wo.linebreak = true, true   -- prose: wrap long lines at word boundaries
  end,
})
