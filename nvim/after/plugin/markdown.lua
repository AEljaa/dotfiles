-- Markdown preview, same idea as LaTeX's Space l l: rendered PDF on the right.
--
--   Space m m   render this .md to PDF + show it in a pane on the right (tdf, inside
--               iTerm). From then on every :w re-renders and the pane reloads.
--               In the pane: j/k = pages, / = search, i = dark mode, q = close.
--   Space m q   close the preview (nvim goes back to full width)
--
-- How: pandoc turns the markdown into LaTeX and tectonic (the LaTeX compiler from
-- latex.lua) makes the PDF, so $math$ and $$math$$ render properly too. The PDF goes
-- in nvim's cache folder, not next to your .md. Images use paths relative to the .md.
-- Inside tmux it splits the iTerm tab you're in (tmux gets narrower until Space m q).

local platform = require('adameljaa.platform')
if platform.mac then   -- Homebrew tools, even when nvim wasn't started from a shell
  if not vim.env.PATH:find('/opt/homebrew/bin', 1, true) then vim.env.PATH = '/opt/homebrew/bin:' .. vim.env.PATH end
  if not vim.env.PATH:find('/usr/local/bin', 1, true) then vim.env.PATH = vim.env.PATH .. ':/usr/local/bin' end  -- pandoc
end

local pane = require('adameljaa.pdfpane')
local CACHE = vim.fn.stdpath('cache') .. '/md-preview'

-- Wrap long lines in code blocks instead of running off the page, and borrow arrows /
-- check marks (common in AI-written notes) from fonts that have them.
local HEADER = CACHE .. '/header.tex'
local HEADER_TEX = [[
\usepackage{fvextra}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,breakanywhere,commandchars=\\\{\}}
\fvset{breaklines,breakanywhere}
\usepackage{newunicodechar}
\newfontfamily\symbolfont{SYMBOLFONT}
\newfontfamily\dingfont{DINGFONT}
\newunicodechar{→}{{\symbolfont →}}\newunicodechar{←}{{\symbolfont ←}}\newunicodechar{↔}{{\symbolfont ↔}}
\newunicodechar{⇒}{{\symbolfont ⇒}}\newunicodechar{↑}{{\symbolfont ↑}}\newunicodechar{↓}{{\symbolfont ↓}}
\newunicodechar{✓}{{\dingfont ✓}}\newunicodechar{✔}{{\dingfont ✔}}\newunicodechar{✗}{{\dingfont ✗}}\newunicodechar{✘}{{\dingfont ✘}}
]]

-- Fonts: Mac ones on a Mac. Elsewhere tectonic's built-in font for the text (always
-- there) and DejaVu Sans for arrows / check marks if it's installed (a missing font
-- would make every render fail, a missing glyph only leaves a gap).
local FONT_ARGS = { '-V', 'mainfont=Helvetica Neue', '-V', 'monofont=Menlo' }
local fonts_ready = false
local function prepare_fonts()   -- once, at the first render (fc-list isn't free)
  if fonts_ready then return end
  fonts_ready = true
  if platform.mac then
    HEADER_TEX = HEADER_TEX:gsub('SYMBOLFONT', 'Apple Symbols'):gsub('DINGFONT', 'Zapf Dingbats')
  else
    FONT_ARGS = {}
    local has_dejavu = vim.fn.executable('fc-list') == 1
      and vim.fn.system({ 'fc-list', 'DejaVu Sans' }):find('DejaVu') ~= nil
    if has_dejavu then
      HEADER_TEX = HEADER_TEX:gsub('SYMBOLFONT', 'DejaVu Sans'):gsub('DINGFONT', 'DejaVu Sans')
    else
      HEADER_TEX = HEADER_TEX:gsub('\\newfontfamily[^\n]*\n', ''):gsub('\\newunicodechar[^\n]*\n', '')
    end
  end
end

local live = {}            -- [buf] = true once Space m m was pressed there
local running = false
local queued = nil         -- buf saved again while rendering: render once more afterwards

local function pdf_for(file)
  return ('%s/%s-%s.pdf'):format(CACHE, vim.fn.fnamemodify(file, ':t:r'), vim.fn.sha256(file):sub(1, 8))
end

local function render(buf, show_after)
  if running then queued = buf return end
  local file = vim.api.nvim_buf_get_name(buf)
  local dir, pdf = vim.fn.fnamemodify(file, ':h'), pdf_for(file)
  vim.fn.mkdir(CACHE, 'p')
  prepare_fonts()
  vim.fn.writefile(vim.split(HEADER_TEX, '\n'), HEADER)
  running = true
  vim.system({
    'pandoc', file, '-o', pdf, '--pdf-engine=tectonic', '--standalone',
    -- GitHub-style: lists straight after a paragraph, ~~strike~~, - [ ] checkboxes
    '-f', 'markdown+lists_without_preceding_blankline+strikeout+task_lists-implicit_figures',
    '--resource-path', dir, '-H', HEADER,
    '-V', 'geometry:a4paper,margin=2cm', '-V', 'colorlinks', '-V', 'linkcolor=blue', '-V', 'urlcolor=blue',
    unpack(FONT_ARGS),
  }, { cwd = dir, text = true }, vim.schedule_wrap(function(r)
    running = false
    if r.code == 0 then
      if show_after then pane.open(pdf) end
    else
      local err = vim.trim(r.stderr or '')
      local lines = vim.split(err, '\n')
      vim.notify('Markdown render failed:\n' .. table.concat(vim.list_slice(lines, 1, 6), '\n'), vim.log.levels.ERROR)
    end
    if queued then
      local b = queued
      queued = nil
      if vim.api.nvim_buf_is_valid(b) and live[b] then render(b, false) end
    end
  end))
end

local function open_preview()
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) == '' then
    vim.notify('Save the file first (:w name.md)', vim.log.levels.WARN)
    return
  end
  live[buf] = true
  local pdf = pdf_for(vim.api.nvim_buf_get_name(buf))
  local have = vim.fn.filereadable(pdf) == 1
  if have then pane.open(pdf) end                 -- old version now, refreshed after the render
  vim.notify('Rendering ' .. vim.fn.expand('%:t') .. ' (first time can take a minute: LaTeX packages download)…')
  if vim.bo[buf].modified then vim.cmd('silent write') else render(buf, not have) end
end

local function close_preview()
  for b in pairs(live) do live[b] = nil end
  if not pane.close() then vim.notify('No preview open') end
end

local grp = vim.api.nvim_create_augroup('markdown_preview', { clear = true })
vim.api.nvim_create_autocmd('BufWritePost', {
  group = grp, pattern = { '*.md', '*.markdown' },
  callback = function(ev)
    if not live[ev.buf] then return end
    local first = vim.fn.filereadable(pdf_for(vim.api.nvim_buf_get_name(ev.buf))) == 0
    render(ev.buf, first)
  end,
})
vim.api.nvim_create_autocmd('FileType', {
  group = grp, pattern = 'markdown',
  callback = function(ev)
    vim.keymap.set('n', '<leader>mm', open_preview, { buffer = ev.buf, desc = 'Markdown: PDF preview pane on the right' })
    vim.keymap.set('n', '<leader>mq', close_preview, { buffer = ev.buf, desc = 'Markdown: close the preview' })
    vim.wo.wrap, vim.wo.linebreak = true, true   -- prose: wrap long lines at word boundaries
  end,
})
