vim.pack.add({{src = "https://github.com/stevearc/oil.nvim"}})

require("oil").setup({
  default_file_explorer = true,
  columns = { "icon" },
  view_options = {
    show_hidden = true,
  },
  keymaps = {

    ["qq"] = "actions.close"
  }
})

vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
