-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'
  
  use {
	  'nvim-telescope/telescope.nvim', branch = '0.1.x',
	  requires = { {'nvim-lua/plenary.nvim'} }
  }

  -- UI: icons, file tree, statusline, buffer tabs, git signs, keymap popup
  use 'nvim-tree/nvim-web-devicons'
  use 'nvim-tree/nvim-tree.lua'
  use 'stevearc/oil.nvim'   -- replaces netrw (<leader>pv)
  use 'nvim-lualine/lualine.nvim'
  use { 'akinsho/bufferline.nvim', tag = 'v4.*' }
  use 'lewis6991/gitsigns.nvim'
  use 'folke/which-key.nvim'
  -- Messages, errors and the : command line as popups instead of the bottom wall
  use { 'folke/noice.nvim', requires = { 'MunifTanjim/nui.nvim', 'rcarriga/nvim-notify' } }
  -- Claude Code in a side split, wired to the editor like the VS Code extension
  use 'coder/claudecode.nvim'
  -- LaTeX: compile + PDF preview in Skim with jump-to-line (after/plugin/latex.lua)
  use { 'lervag/vimtex', tag = 'v2.18' }   -- newer needs nvim 0.12.4+; drop the tag after upgrading nvim

  use { "ellisonleao/gruvbox.nvim" }
  use { "blazkowolf/gruber-darker.nvim" }
  use { "folke/tokyonight.nvim" }
  use {"AEljaa/nvim-remote-containers"}
  -- master = the classic API after/plugin/treesitter.lua uses (require'nvim-treesitter.configs').
  -- The plugin's default branch is now `main`, a rewrite without that module, so a fresh
  -- clone errored on every start. (Moving to `main` is part of the nvim 0.12 upgrade.)
  use { 'nvim-treesitter/nvim-treesitter', branch = 'master', run = ':TSUpdate' }
  use('mbbill/undotree')
  use('ThePrimeagen/harpoon')
  use('tpope/vim-fugitive')
  use {
	  'VonHeikemen/lsp-zero.nvim',
	  branch = 'v4.x',
	  requires = {
		   {'williamboman/mason.nvim'},
		   {'williamboman/mason-lspconfig.nvim'},

		  -- LSP Support
		  {'neovim/nvim-lspconfig'},
		  -- Autocompletion
		  {'hrsh7th/nvim-cmp'},
		  {'hrsh7th/cmp-nvim-lsp'},
		  {'hrsh7th/cmp-buffer'},  -- words already in open files (fallback when the LSP has nothing)
		  {'hrsh7th/cmp-path'},    -- file paths
		  {'L3MON4D3/LuaSnip'},
	  }
  }
end)
