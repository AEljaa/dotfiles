vim.g.mapleader = " "
-- <leader>pv / - open oil.nvim (netrw replacement), configured in after/plugin/ui.lua
vim.keymap.set("n", "<leader>pv", "<cmd>Oil<CR>", { desc = "File explorer (oil)" })
vim.keymap.set("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
vim.cmd('set clipboard=unnamedplus')
-- Find & replace in this file. Each one opens
--   :%s/<text>//gc
-- with the cursor where the new text goes: type it, Enter, then y/n per match
-- (a = all remaining, q = stop). The text is matched literally (\V), so
-- . * [ ] / etc. in it are fine.
local function replace_cmd(text, whole_word)
  local pat = vim.fn.escape(text, '/\\'):gsub('\n', '\\n')
  if whole_word then pat = '\\<' .. pat .. '\\>' end
  pat = pat:gsub('<', '<lt>')          -- keep "<=" etc. from being read as key names
  return ':<C-u>%s/\\V' .. pat .. '//gc<Left><Left><Left>'
end

vim.keymap.set('n', 'gR', function()
  return replace_cmd(vim.fn.expand('<cword>'), true)
end, { expr = true, desc = 'Replace word under cursor in file' })

vim.keymap.set('x', '<leader>r', function()
  local lines = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
  return replace_cmd(table.concat(lines, '\n'), false)
end, { expr = true, desc = 'Replace selected text in file' })

vim.keymap.set('n', '<leader>r', function()
  local text = vim.fn.getreg('0')     -- last yank (not overwritten by deletes)
  if text == '' then vim.notify('Nothing yanked yet', vim.log.levels.INFO) return '' end
  return replace_cmd((text:gsub('\n$', '')), false)
end, { expr = true, desc = 'Replace last yanked text in file' })

