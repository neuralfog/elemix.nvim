if vim.g.loaded_elemix then
    return
end
vim.g.loaded_elemix = true

require("elemix").init()
