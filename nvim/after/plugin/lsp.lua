local lsp_zero = require('lsp-zero')

require('mason').setup({})
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
    root_markers = { '.slang', '.git' },
})
vim.lsp.enable('slang_server')

local cmp = require('cmp')
local cmp_action = lsp_zero.cmp_action()

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
        { name = 'nvim_lsp' },
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

