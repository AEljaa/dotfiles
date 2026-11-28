-- Verilog (.v / .vh) files are Verilog-2005: SystemVerilog-only words are marked as
-- errors right on the word, as you type it, with what to use instead.
--
-- Why: in Verilog `always_ff` is an ordinary name, so the language servers only complain
-- once the code around it stops making sense, often several lines later (e.g. at
-- `endmodule`). It looked like there was no error at all.
--   * comments and strings are ignored
--   * logic / bit / byte / int ... are only marked when used as a type
--     (`input logic clk`, `logic [7:0] x`): in Verilog they're legal signal names
--     (`wire logic;`, `assign int = ...`)
--   * shown while typing (a whole keyword can't be a half-typed word)

local ns = vim.api.nvim_create_namespace('verilog_sv_keywords')
vim.diagnostic.config({ update_in_insert = true }, ns)

local ALWAYS = {
  always_ff = 'use always @(posedge clk)',
  always_comb = 'use always @(*)',
  always_latch = 'use always @(*)',
  typedef = 'use localparam constants',
  enum = 'use localparam constants for the states',
  struct = 'use separate signals or one wide vector',
  union = 'use separate signals or one wide vector',
  packed = 'use a plain vector [N:0]',
  interface = 'pass the signals as module ports',
  endinterface = 'pass the signals as module ports',
  modport = 'pass the signals as module ports',
  package = 'put shared constants in an `include file',
  endpackage = 'put shared constants in an `include file',
  import = 'put shared constants in an `include file',
  unique = 'use a plain case / if',
  unique0 = 'use a plain case / if',
  priority = 'use a plain case / if',
  foreach = 'use a for loop with an integer',
  inside = 'compare the values explicitly',
  class = 'not available in Verilog',
  endclass = 'not available in Verilog',
  assert = 'not available in Verilog-2005',
  assume = 'not available in Verilog-2005',
  property = 'not available in Verilog-2005',
  endproperty = 'not available in Verilog-2005',
  sequence = 'not available in Verilog-2005',
  endsequence = 'not available in Verilog-2005',
}
local TYPES = {
  logic = 'use reg (or wire)',
  bit = 'use reg',
  byte = 'use reg [7:0]',
  int = 'use integer',
  shortint = 'use reg [15:0]',
  longint = 'use reg [63:0]',
  string = 'not available in Verilog',
}

-- One line with comments and strings blanked out (same length, so columns stay right).
-- `in_block`: whether a /* */ comment is open at the start of the line.
local function code_only(line, in_block)
  local out, i, n = {}, 1, #line
  while i <= n do
    local two = line:sub(i, i + 1)
    if in_block then
      if two == '*/' then in_block = false; out[#out + 1] = '  '; i = i + 2
      else out[#out + 1] = ' '; i = i + 1 end
    elseif two == '//' then
      out[#out + 1] = string.rep(' ', n - i + 1); break
    elseif two == '/*' then
      in_block = true; out[#out + 1] = '  '; i = i + 2
    elseif line:sub(i, i) == '"' then
      local j = i + 1
      while j <= n and line:sub(j, j) ~= '"' do j = j + (line:sub(j, j) == '\\' and 2 or 1) end
      out[#out + 1] = string.rep(' ', math.min(j, n) - i + 1); i = j + 1
    else
      out[#out + 1] = line:sub(i, i); i = i + 1
    end
  end
  return table.concat(out), in_block
end

local function check(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'verilog' then return end
  local items, in_block = {}, false
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local code
    code, in_block = code_only(line, in_block)
    for s, word, e in code:gmatch('()([%a_][%w_$]*)()') do
      local before = s > 1 and code:sub(s - 1, s - 1) or ''
      if before ~= '`' and before ~= '$' and before ~= '.' and before ~= '\\' then
        local hint = ALWAYS[word]
        -- type words only as a type: followed by a name, [range], signed/unsigned
        if not hint and TYPES[word] and code:sub(e):match('^%s+[%a_%[]') then hint = TYPES[word] end
        if hint then
          items[#items + 1] = {
            lnum = lnum - 1, col = s - 1, end_col = e - 1,
            severity = vim.diagnostic.severity.ERROR,
            source = 'verilog-2005',
            message = ('`%s` is SystemVerilog, not Verilog-2005: %s'):format(word, hint),
          }
        end
      end
    end
  end
  vim.diagnostic.set(ns, buf, items)
end

local timers = {}
local function schedule_check(buf)
  local t = timers[buf]
  if not t then t = vim.uv.new_timer(); timers[buf] = t end
  t:stop()
  t:start(120, 0, vim.schedule_wrap(function() check(buf) end))
end

local grp = vim.api.nvim_create_augroup('verilog_sv_keywords', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = grp, pattern = 'verilog',
  callback = function(ev)
    local buf = ev.buf
    vim.api.nvim_clear_autocmds({ group = grp, buffer = buf })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufEnter' }, {
      group = grp, buffer = buf, callback = function() schedule_check(buf) end,
    })
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = grp, buffer = buf,
      callback = function()
        if timers[buf] then timers[buf]:stop(); timers[buf]:close(); timers[buf] = nil end
      end,
    })
    check(buf)
  end,
})
