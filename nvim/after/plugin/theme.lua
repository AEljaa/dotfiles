-- tokyonight "night", pushed darker (black with a blue tint) and with the
-- yellow/orange syntax colours swapped for blues/cyans.
-- Plus a high-contrast light variant for bright rooms / sunlight:
--   Space t t  or  :ThemeToggle   (also :ThemeLight, :ThemeDark)
-- The last choice is remembered across restarts.
-- To go back: vim.cmd("colorscheme gruber-darker")

local palettes = {
  dark = {
    bg       = '#0a0d14', -- editor background
    bg_dark  = '#06080d', -- sidebars, floats, statusline
    bg_hl    = '#131a28', -- cursorline, selection-ish
    pale     = '#b4f9f8', -- constants / numbers (was orange)
    param    = '#7dcfff', -- function parameters (was yellow)
    warn     = '#8c9eff', -- warnings: periwinkle (was yellow)
  },
  -- Same blue/cyan idea, but near-white background and dark, saturated text.
  light = {
    bg       = '#fbfcfe',
    bg_dark  = '#eceef4',
    bg_hl    = '#e3e7f1',
    fg       = '#141b33', -- normal text: near-black navy (stock day is a mid blue)
    fg_dark  = '#2f3a5e',
    comment  = '#56607f', -- stock day comments are #848cb5, too faint in sunlight
    gutter   = '#8890ad', -- line numbers
    pale     = '#006570',
    param    = '#00589e',
    warn     = '#3b47b8',
  },
}

local state_file = vim.fn.stdpath('state') .. '/theme_mode'

local function read_mode()
  local ok, lines = pcall(vim.fn.readfile, state_file)
  return (ok and lines[1] == 'light') and 'light' or 'dark'
end

local function apply(mode)
  local p = palettes[mode]
  local light = mode == 'light'

  require('tokyonight').setup({
    style = 'night',
    light_style = 'day',
    day_brightness = 0.1, -- lower = darker, punchier syntax colours on the light bg
    on_colors = function(c)
      c.bg            = p.bg
      c.bg_dark       = p.bg_dark
      c.bg_dark1      = p.bg_dark
      c.bg_float      = p.bg_dark
      c.bg_popup      = p.bg_dark
      c.bg_sidebar    = p.bg_dark
      c.bg_statusline = p.bg_dark
      c.bg_highlight  = p.bg_hl
      c.warning       = p.warn   -- diagnostics, underlines, statusline/tab counts
      c.todo          = c.blue
      if light then
        c.fg        = p.fg
        c.fg_dark   = p.fg_dark
        c.fg_float  = p.fg
        c.comment   = p.comment
        c.fg_gutter = p.gutter
      end
    end,
    on_highlights = function(hl, c)
      hl.Constant                        = { fg = p.pale }
      hl.Number                          = { fg = p.pale }
      hl.Boolean                         = { fg = p.pale }
      hl['@constant']                    = { fg = p.pale }
      hl['@constant.builtin']            = { fg = p.pale }
      hl['@number']                      = { fg = p.pale }
      hl['@number.float']                = { fg = p.pale }
      hl['@boolean']                     = { fg = p.pale }
      hl['@variable.parameter']          = { fg = p.param }
      hl['@variable.parameter.builtin']  = { fg = p.param }
      hl['@string.documentation']        = { fg = c.green }
      hl['@markup.list.markdown']        = { fg = c.blue, bold = true }
      hl['@punctuation.special.markdown'] = { fg = c.blue }
      hl.CursorLineNr                    = { fg = c.blue, bold = true }
      hl.MatchParen                      = { fg = c.cyan, bold = true, underline = true }
      hl.IncSearch                       = { bg = c.blue1, fg = light and p.bg or c.black }
      hl.Todo                            = { bg = c.blue, fg = light and p.bg or c.black, bold = true }
    end,
  })

  vim.o.background = mode
  vim.cmd('colorscheme ' .. (light and 'tokyonight-day' or 'tokyonight-night'))
  pcall(vim.fn.writefile, { mode }, state_file)
end

apply(read_mode())

vim.api.nvim_create_user_command('ThemeLight', function() apply('light') end, { desc = 'High-contrast light theme' })
vim.api.nvim_create_user_command('ThemeDark', function() apply('dark') end, { desc = 'Dark theme' })
vim.api.nvim_create_user_command('ThemeToggle', function()
  apply(vim.o.background == 'light' and 'dark' or 'light')
end, { desc = 'Toggle light / dark theme' })
vim.keymap.set('n', '<leader>tt', '<cmd>ThemeToggle<CR>', { desc = 'Toggle light / dark theme' })
