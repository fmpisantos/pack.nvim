-- Leader
vim.g.mapleader = " ";
vim.g.maplocalleader = " "

vim.pack.add({ "https://github.com/fmpisantos/pack.nvim" })
local pack = require("pack")

pack.require("plugins");
pack.require("plugins.myPlugins.init");

pack.install()
