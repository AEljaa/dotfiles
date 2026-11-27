-- Plain-English list of every shortcut in this config. Opened with Space ?.
-- When you add a keymap somewhere, add a line here too.
local M = {}

M.sections = {
  { 'Files & search', {
    { 'Space p v',   'File explorer (oil)' },
    { 'Space p V',   'File explorer, floating' },
    { '-',           'Open the folder of this file' },
    { 'Space e',     'File tree sidebar on / off' },
    { 'Space E',     'Show this file in the tree' },
    { 'Space p f',   'Find file by name' },
    { 'Space g',     'Find file tracked by git' },
    { 'Space p s',   'Search all files for a word' },
    { 'Space p g',   'Live search as you type' },
    { 'Space p r',   'Recently opened files' },
    { 'Space p d',   'All errors / warnings' },
    { 'Space p o',   'Functions, classes in this file' },
    { 'Space p k',   'Search every shortcut' },
  } },
  { 'Harpoon (pinned files)', {
    { 'Space a',     'Pin this file' },
    { 'Ctrl e',      'Show pinned files (edit list, Enter to jump)' },
    { 'Ctrl h',      'Jump to pinned file 1' },
    { 'Ctrl t',      'Jump to pinned file 2' },
    { 'Ctrl n',      'Jump to pinned file 3' },
    { 'Ctrl s',      'Jump to pinned file 4' },
  } },
  { 'Buffers (open files, tabs at the top)', {
    { '] b  /  [ b', 'Next / previous buffer' },
    { 'Space b p',   'Pick a buffer by letter' },
    { 'Space b d',   'Close this buffer' },
    { 'Space p b',   'Search open buffers' },
  } },
  { 'Code (LSP)', {
    { 'g d',         'Go to definition' },
    { 'K',           'Docs / type of thing under cursor' },
    { 'g r r',       'Find all references' },
    { 'g r n',       'Rename symbol everywhere' },
    { 'g r a',       'Code actions / quick fixes' },
    { 'g r i',       'Go to implementation' },
    { 'g O',         'Outline of this file' },
    { '] d  /  [ d', 'Next / previous error or warning' },
    { 'Ctrl w  d',   'Show the full error message' },
    { 'Space c d',   'Copy the error on this line' },
    { 'Space c s',   'Copy the error + search it on Google' },
    { 'g R',         'Replace word under cursor in this file' },
    { 'Space r',     'Replace last yanked text (visual: replace selection)' },
    { '* then c g n', 'Change next match; . repeats, n skips' },
  } },
  { 'Autocomplete (while typing)', {
    { 'Ctrl n / Ctrl p', 'Next / previous suggestion' },
    { 'Enter or Ctrl y', 'Accept suggestion' },
    { 'Ctrl Space',  'Show suggestions' },
    { 'Ctrl e',      'Close suggestions' },
    { 'Ctrl f / Ctrl b', 'Scroll the docs popup' },
  } },
  { 'Git', {
    { 'Space g s',   'Git status (fugitive)' },
    { '] h  /  [ h', 'Next / previous changed block' },
    { 'Space h p',   'Preview what changed here' },
    { 'Space h b',   'Who last changed this line' },
  } },
  { 'Inside the file explorer (oil)', {
    { 'Enter',       'Open file / folder' },
    { '-',           'Go up a folder' },
    { '_',           'Jump to project root' },
    { 'Ctrl p',      'Preview file' },
    { 'Ctrl v / Ctrl x', 'Open in side / bottom split' },
    { 'g .',         'Show / hide hidden files' },
    { 'g s',         'Change sort order' },
    { 'q',           'Close explorer' },
    { 'edit + :w',   'Rename / dd delete / new line = new file' },
    { 'g ?',         'All explorer keys' },
  } },
  { 'AI panel (Claude Code / Codex, right side)', {
    { 'Space c c',   'Claude Code: open (continues last chat) / jump to it' },
    { 'Space c x',   'Codex: open (continues last chat) / jump to it' },
    { '(just type)', 'Entering a panel puts you in typing mode' },
    { 'Ctrl h',      'From the panel, back to your code' },
    { 'Ctrl q',      'From the panel: hide it (chat keeps running)' },
    { 'Space c Y',   'Copy Claude\'s last answer (opens it: v + y copies part)' },
    { 'Space c a',   'Send selection (visual) / this file to Claude' },
    { 'Space c x (visual)', 'Send selection to Codex' },
    { 'Space c X',   'Put this file\'s path in the Codex prompt' },
    { 'Space c y / n', 'Accept / reject Claude\'s diff (or :w / :q)' },
    { 'Ctrl w < / >', 'Make panel narrower / wider (or drag the line)' },
  } },
  { 'LaTeX (.tex files, like Overleaf)', {
    { 'Space l l',   'Compile + PDF pane on the right; every :w recompiles' },
    { 'Space l s',   'Same but in Skim (PDF follows your cursor)' },
    { 'Space l q',   'Close the PDF (terminal goes back to full width)' },
    { 'In PDF pane', 'j k = pages, / = search, i = dark, f = borders, q = close' },
    { 'Cmd [  Cmd ]', 'Move between nvim and the PDF pane' },
    { 'Space l v',   'Skim: scroll the PDF to your cursor' },
    { 'Cmd Shift click', 'Skim: jump to that line in nvim' },
    { 'Space l e',   'List of errors / warnings' },
    { 'Space l o',   'Full compiler output' },
    { 'Space l t',   'Table of contents (jump to a section)' },
    { 'Space l c',   'Delete .aux / .log / ... files' },
  } },
  { 'Terminal (shell under your code)', {
    { 'Ctrl /',      'Open / jump to / hide (keeps running)' },
    { 'Ctrl q',      'From the terminal: hide it' },
    { 'Ctrl h',      'From the terminal: back to your code' },
    { 'Ctrl \\ Ctrl n', 'Stop typing (scroll / copy with Vim keys), i = type again' },
    { 'exit',        'Close it for good' },
  } },
  { 'Markdown preview (.md files)', {
    { 'Space m m',   'Render to PDF + pane on the right; every :w refreshes' },
    { 'Space m q',   'Close the preview' },
    { 'In the pane', 'j k = pages, / = search, i = dark, q = close' },
  } },
  { 'Other', {
    { 'Space u',     'Undo history tree' },
    { 'Space n h',   'Message / error history' },
    { 'Space n d',   'Dismiss popups' },
    { 'Space n l',   'Something went wrong: note it in the debug log' },
    { 'Space n L',   'Open the debug log (nvim/logs/nvim.log)' },
    { 'Space t t',   'Light / dark theme (light = for bright rooms)' },
    { 'Space (wait)', 'Popup of what you can press next' },
    { 'Space ?',     'This cheatsheet' },
  } },
}

local KEY_W, DESC_W = 17, 44
local COL_W = KEY_W + DESC_W

-- Render one section to { text, hl ranges }
local function render_section(sec)
  local rows = { { text = sec[1], hls = { { 'Title', 0, #sec[1] } } } }
  for _, item in ipairs(sec[2]) do
    local key = item[1] .. string.rep(' ', KEY_W - vim.fn.strdisplaywidth(item[1]))
    rows[#rows + 1] = { text = '  ' .. key .. item[2], hls = { { 'Special', 2, 2 + #item[1] } } }
  end
  rows[#rows + 1] = { text = '', hls = {} }
  return rows
end

function M.open()
  local two_col = vim.o.columns >= COL_W * 2 + 12
  local cols = { {}, {} }
  if two_col then
    -- greedy balance: put each section in the shorter column
    for _, sec in ipairs(M.sections) do
      local r = render_section(sec)
      local tgt = #cols[1] <= #cols[2] and cols[1] or cols[2]
      vim.list_extend(tgt, r)
    end
  else
    for _, sec in ipairs(M.sections) do vim.list_extend(cols[1], render_section(sec)) end
  end

  local lines, marks = {}, {}
  local n = math.max(#cols[1], #cols[2])
  for i = 1, n do
    local l, r = cols[1][i] or { text = '', hls = {} }, cols[2][i]
    local left = ' ' .. l.text
    local pad = two_col and string.rep(' ', COL_W + 4 - vim.fn.strdisplaywidth(left)) or ''
    local line = left .. (r and (pad .. r.text) or '')
    lines[i] = line
    for _, h in ipairs(l.hls) do marks[#marks + 1] = { i - 1, h[1], h[2] + 1, h[3] + 1 } end
    if r then
      local off = #left + #pad
      for _, h in ipairs(r.hls) do marks[#marks + 1] = { i - 1, h[1], h[2] + off, h[3] + off } end
    end
  end
  while lines[#lines] and lines[#lines]:match('^%s*$') do table.remove(lines) end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ns = vim.api.nvim_create_namespace('cheatsheet')
  for _, m in ipairs(marks) do
    if m[1] < #lines then
      vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[3], { end_col = m[4], hl_group = m[2] })
    end
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'

  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width + 2, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    title = ' Shortcuts ', title_pos = 'center',
    footer = ' q / Esc to close  ·  j k to scroll ', footer_pos = 'center',
  })
  vim.wo[win].cursorline = false
  for _, k in ipairs({ 'q', '<Esc>', '<leader>?' }) do
    vim.keymap.set('n', k, function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
  end
  return win, buf
end

return M
