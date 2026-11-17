-- Lumen OS - Configuração enxuta e rápida do Neovim (zero bloat)
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.scrolloff = 6
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250

vim.g.mapleader = " "
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Salvar arquivo" })
vim.keymap.set("n", "<leader>q", "<cmd>q<cr>", { desc = "Fechar" })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>")
