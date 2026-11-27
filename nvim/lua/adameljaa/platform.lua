-- Which OS nvim is running on, so Mac-only bits (iTerm splits, Skim, AppleScript,
-- Mac fonts) switch to something that works elsewhere.
--
--   local platform = require('adameljaa.platform')
--   if platform.mac then ... elseif platform.linux then ... end
--
--   mac    macOS
--   linux  Linux (not WSL)
--   wsl    Linux inside Windows (WSL): Linux tools, but PDFs open in Windows apps
--   win    native Windows nvim (tmux / the AI panels need WSL there)
--   unix   mac, linux or wsl
--
-- Try another OS's code path from this Mac: NVIM_PLATFORM=linux nvim   (or wsl / win)
-- (Not called "os": that would hide Lua's own os.date / os.rename.)

local M = {}

local name = vim.env.NVIM_PLATFORM
if not name or name == '' then
  if vim.fn.has('win32') == 1 then name = 'win'
  elseif vim.fn.has('wsl') == 1 then name = 'wsl'
  elseif vim.uv.os_uname().sysname == 'Darwin' then name = 'mac'
  else name = 'linux' end
end

M.name = name
M.mac, M.linux, M.wsl, M.win = name == 'mac', name == 'linux', name == 'wsl', name == 'win'
M.unix = not M.win

return M
