require'nvim-treesitter.configs'.setup {
  -- A list of parser names, or "all" (the five listed parsers should always be installed)
  -- regex/bash/markdown/markdown_inline are used by noice to render popups
  ensure_installed = { "rust","c","cpp","python","verilog", "lua", "vim", "vimdoc", "query",
                       "regex", "bash", "markdown", "markdown_inline" },

  -- Install parsers synchronously (only applied to `ensure_installed`)
  sync_install = false,

  -- Automatically install missing parsers when entering buffer
  -- Recommendation: set to false if you don't have `tree-sitter` CLI installed locally
  auto_install = true,
  -- latex: vimtex highlights it, and its parser needs the tree-sitter CLI to build
  ignore_install = { "latex" },


  highlight = {
    enable = true,
    -- vimtex does its own LaTeX highlighting (needed for its math/concealing features)
    disable = { "latex" },

    -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
    -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
    -- Using this option may slow down your editor, and you may see some duplicate highlights.
    -- Instead of true it can also be a list of languages
    additional_vim_regex_highlighting = false,
  },
}
