local lsp_zero = require('lsp-zero')

require('mason').setup({})

-- SystemVerilog / Verilog: svlangserver runs Verilator's lint as you type (its default):
-- legal-but-probably-wrong code (width mismatches, unused / undriven signals, latches,
-- blocking `=` in always_ff, case without default...) and anything Verilator would
-- reject when you simulate with it. slang-server (below) gives the compiler errors and
-- completion. Setting names are svlangserver's own (lib/svutils.js); the ones in Mason's
-- schema (compilerType, compileOnSave...) belong to the VS Code extension and do nothing.
vim.lsp.config('svlangserver', {
    settings = {
        systemverilog = {
            linter = 'verilator',
            -- by file extension: .v / .vh are Verilog-2005, .sv / .svh SystemVerilog.
            -- (svlangserver's default has -sv, which checked every .v file as SystemVerilog:
            -- false errors on legal Verilog, none on SystemVerilog-only code.)
            launchConfiguration = 'verilator --lint-only --Wall +1364-2005ext+v +1364-2005ext+vh +1800-2017ext+sv +1800-2017ext+svh',
        },
    },
})
require('mason-lspconfig').setup({
    ensure_installed = {
        'clangd',
        'sqlls',
        'rust_analyzer',
        'bashls',
        'ts_ls',
    },
    -- prosemd-lsp (markdown grammar) only ships an Intel binary: on this Mac it fails to
    -- start with "Bad CPU type" and showed a warning on every .md file.
    automatic_enable = { exclude = { 'prosemd_lsp' } },
    handlers = {
        function(server_name)
            require('lspconfig')[server_name].setup({})
        end,
    },
})

-- SystemVerilog completion. svlangserver / hdl_checker don't complete local
-- signals (wires, logic, ports inside a module); slang-server does.
-- Installed with :MasonInstall slang-server. It has no lspconfig entry
-- (lspconfig's "slangd" is the unrelated shader language), so it's defined here.
vim.lsp.config('slang_server', {
    cmd = { vim.fn.stdpath('data') .. '/mason/bin/slang-server' },
    filetypes = { 'systemverilog', 'verilog' },
    -- Project root: the nearest folder with .slang or .git, but never your home folder.
    -- (~/.slang holds slang-server's own settings, see below; with plain root_markers
    -- it made your whole home folder "the project", slang-server tried to scan all of
    -- it, crashed at startup and showed no errors at all.) No project: the file's folder.
    root_dir = function(bufnr, on_dir)
        local file = vim.api.nvim_buf_get_name(bufnr)
        local root = vim.fs.root(bufnr, { { '.slang', '.git' } })
        if not root or root == vim.env.HOME then root = vim.fs.dirname(file) end
        on_dir(root)
    end,
})
-- Only when it's installed (Mason doesn't install it by itself: on a new machine run
-- :MasonInstall slang-server). Enabling it anyway made :checkhealth warn and completion
-- silently missing.
if vim.fn.executable(vim.fn.stdpath('data') .. '/mason/bin/slang-server') == 1 then
    vim.lsp.enable('slang_server')

    -- slang-server's settings: read .v / .vh files with Verilog-2005 keywords (logic,
    -- always_ff, typedef... are plain names there, so using them as SystemVerilog is an
    -- error, and old Verilog that uses them as signal names isn't). Its settings live in
    -- ~/.slang/server.json, outside this config: written here if missing (new machines).
    local slang_cfg = vim.env.HOME .. '/.slang/server.json'
    if vim.fn.filereadable(slang_cfg) == 0 then
        vim.fn.mkdir(vim.env.HOME .. '/.slang', 'p')
        -- ".../" = any folder (slang's wildcard; "*.v" and "**/*.v" did nothing when tested)
        vim.fn.writefile({ '{ "flags": "--map-keyword-version=1364-2005+.../*.v,.../*.vh" }' }, slang_cfg)
    end
end

local cmp = require('cmp')
local cmp_action = lsp_zero.cmp_action()

-- In Verilog (.v) files, don't suggest SystemVerilog-only keywords (the language servers
-- offer the full SystemVerilog list everywhere). Only keyword / snippet suggestions are
-- dropped: a signal you named e.g. `logic` (legal in Verilog) still shows up.
local SV_ONLY = {}
for w in ([[accept_on alias always_comb always_ff always_latch assert assume before bind bins
  binsof bit break byte chandle checker class clocking const constraint context continue
  cover covergroup coverpoint cross dist do endchecker endclass endclocking endgroup
  endinterface endpackage endprogram endproperty endsequence enum eventually expect export
  extends extern final first_match foreach forkjoin global iff ignore_bins illegal_bins
  implies import inside int interface intersect join_any join_none let local logic longint
  matches modport nettype new null package packed priority program property protected pure
  rand randc randcase randsequence ref reject_on restrict return s_always s_eventually
  s_nexttime s_until s_until_with sequence shortint shortreal soft solve static string
  strong struct super sync_accept_on sync_reject_on tagged this throughout timeprecision
  timeunit type typedef union unique unique0 until until_with untyped var virtual void
  wait_order weak wildcard with within]]):gmatch('%S+') do SV_ONLY[w] = true end
local KIND = require('cmp.types').lsp.CompletionItemKind
local function verilog_entry_ok(entry)
    if vim.bo.filetype ~= 'verilog' then return true end
    local word = (entry:get_completion_item().label or ''):match('^%s*([%w_]+)')
    local kind = entry:get_kind()
    return not (word and SV_ONLY[word] and (kind == KIND.Keyword or kind == KIND.Snippet or kind == KIND.Text))
end

cmp.setup({
    mapping = {
        ['<C-p>'] = cmp.mapping.select_prev_item(),
        ['<C-n>'] = cmp.mapping.select_next_item(),
        ['<C-y>'] = cmp.mapping.confirm({ select = true }),
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<Tab>'] = nil,
        ['<S-Tab>'] = nil,
    },
    sources = {
        { name = 'nvim_lsp', entry_filter = verilog_entry_ok },
        { name = 'buffer' },
        { name = 'path' },
        { name = 'luasnip' },
    },
})

-- Neovim 0.11 already maps K, grn, grr, gra, gri, gO, [d, ]d. It does not map gd.
vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(ev)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = ev.buf, desc = 'Go to definition' })
    end,
})

-- Copy the error/warning on this line (to the system clipboard), optionally
-- also searching the web for it. If the line has several, the one under the
-- cursor wins; otherwise the most severe one.
local function line_diagnostic()
    local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
    local ds = vim.diagnostic.get(0, { lnum = lnum - 1 })
    if #ds == 0 then
        vim.notify('No error or warning on this line', vim.log.levels.INFO)
        return nil
    end
    table.sort(ds, function(a, b) return a.severity < b.severity end)
    for _, d in ipairs(ds) do
        if col >= d.col and col < (d.end_col or d.col + 1) then return d end
    end
    return ds[1]
end

local function copy_diagnostic()
    local d = line_diagnostic()
    if not d then return nil end
    local msg = d.message:gsub('%s+', ' ')
    vim.fn.setreg('+', msg)
    vim.fn.setreg('"', msg)
    vim.notify('Copied: ' .. msg, vim.log.levels.INFO)
    return msg, d
end

vim.keymap.set('n', '<leader>cd', copy_diagnostic, { desc = 'Copy error on this line' })
vim.keymap.set('n', '<leader>cs', function()
    local msg, d = copy_diagnostic()
    if not msg then return end
    local lang = (vim.bo.filetype == 'systemverilog' or vim.bo.filetype == 'verilog') and 'SystemVerilog ' or ''
    local query = lang .. (d.source and (d.source .. ' ') or '') .. msg
    vim.ui.open('https://www.google.com/search?q=' .. vim.uri_encode(query))
end, { desc = 'Copy error on this line + search the web' })

vim.diagnostic.config({
    virtual_text = true,
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
})

