-- nvim's built-in SystemVerilog indenter (indent/systemverilog.vim, from 2017) gets lost
-- in a module header like
--     module m #(
--         parameter int W = 8
--     ) (
--         input logic clk
--     );
-- It pushed `) (`, `);`, the whole module body and even `endmodule` 8 spaces too far
-- right. This wraps it: inside / right after a module (interface, program, package,
-- class) header it works the indent out itself, everywhere else the built-in one
-- decides (always/if/case/begin-end, which it gets right).

local START = { module = 1, interface = 1, program = 1, package = 1, class = 1, macromodule = 1 }

-- Indent for line `lnum`, or nil to let the built-in indenter decide.
local function header_indent(lnum)
  local sw = vim.fn.shiftwidth()
  -- nearest module/... start above, unless its end came first
  local m
  for l = lnum - 1, math.max(1, lnum - 2000), -1 do
    local t = vim.fn.getline(l)
    local kw = t:match('^%s*(%l+)')
    if kw and kw:match('^end') and START[kw:sub(4)] then return nil end   -- after an endmodule
    if kw and START[kw] and not t:match('^%s*%l+%s*;') then m = l; break end
    if kw == 'virtual' and t:match('^%s*virtual%s+class') then m = l; break end
  end
  if not m then return nil end
  local base = vim.fn.indent(m)

  local cur = vim.fn.getline(lnum)
  local kw = cur:match('^%s*(%l+)')
  if kw and kw:match('^end') and START[kw:sub(4)] then return base end   -- endmodule

  -- Where does the header end? (`;` with all brackets closed)
  local depth, hdr_end = 0, nil
  for l = m, lnum - 1 do
    local t = vim.fn.getline(l):gsub('//.*$', '')
    for ch in t:gmatch('[%(%);]') do
      if ch == '(' then depth = depth + 1
      elseif ch == ')' then depth = depth - 1
      elseif depth <= 0 then hdr_end = l; break end
    end
    if hdr_end then break end
  end

  if not hdr_end then                                  -- still inside the header
    if cur:match('^%s*%)') then return base end        -- `) (` and `);` line up with module
    return base + sw                                   -- parameters / ports
  end
  local prev = vim.fn.prevnonblank(lnum - 1)
  if prev == hdr_end then return base + sw end         -- first line of the body
  return nil
end

function _G.SvIndentFixed()
  local ok, n = pcall(header_indent, vim.v.lnum)
  if ok and n then return n end
  return vim.fn.SystemVerilogIndent()
end

vim.bo.indentexpr = 'v:lua.SvIndentFixed()'
vim.opt_local.indentkeys:append('0)')                 -- re-indent `);` as soon as you type it
vim.b.undo_indent = (vim.b.undo_indent or '') .. ' | setl inde< indk<'
