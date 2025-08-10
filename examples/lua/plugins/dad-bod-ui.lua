return {
    src = {
        "kristijanhusak/vim-dadbod-ui",
    },
    deps = {
        "tpope/vim-dadbod",
        "kristijanhusak/vim-dadbod-completion",
    },
    setup = function()
        vim.g.db_ui_use_nerd_fonts = 1;
    end
}
