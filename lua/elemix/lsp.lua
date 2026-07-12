local config = require("elemix.config")
local resolve = require("elemix.resolve")

local M = {}

local NAME = "elemix-analyzer"

-- Completion engines that source LSP clients on their own. If any is present we
-- must NOT also turn on native completion, or the two race and auto-insert.
local ENGINE_MODULES = { "blink.cmp", "cmp", "coq", "mini.completion" }
local ENGINE_PLUGINS = { "blink.cmp", "nvim-cmp", "coq_nvim", "mini.nvim" }

local function completion_engine_present()
    -- Already loaded this session?
    for _, m in ipairs(ENGINE_MODULES) do
        if package.loaded[m] then
            return true
        end
    end
    -- Installed via lazy.nvim but not loaded yet (engines lazy-load on insert,
    -- often after our LSP has attached) - the registry is the reliable signal.
    local ok, lazy = pcall(require, "lazy.core.config")
    if ok and type(lazy.plugins) == "table" then
        for _, name in ipairs(ENGINE_PLUGINS) do
            if lazy.plugins[name] then
                return true
            end
        end
    end
    return false
end

-- Turn on native `vim.lsp.completion` only when it won't fight a real engine.
local function maybe_enable_native_completion(client, bufnr)
    local mode = config.options.completion
    if mode == false then
        return
    end
    if mode == "auto" and completion_engine_present() then
        return
    end
    local completion = vim.lsp.completion
    if not (completion and completion.enable) then
        return
    end
    -- Sane native popup: show it, but never auto-insert the first item so you
    -- can keep typing to narrow.
    local opts = vim.opt.completeopt:get()
    if not vim.tbl_contains(opts, "noinsert") and not vim.tbl_contains(opts, "noselect") then
        vim.opt.completeopt:append("menuone")
        vim.opt.completeopt:append("noselect")
    end
    pcall(completion.enable, true, client.id, bufnr, { autotrigger = true })
end

-- Start (or reuse) the analyzer server for a buffer's project root, rooted at
-- that folder. `vim.lsp.start` dedupes by name + root, so all of a folder's
-- TypeScript buffers share one server, exactly like the VS Code client.
function M.start(bufnr)
    if vim.bo[bufnr].filetype ~= "typescript" then
        return
    end
    local root = resolve.root(bufnr)
    if not root then
        return
    end
    local bin = resolve.analyzer_bin(root, config.options.analyzer.path)
    if not bin then
        return
    end
    vim.lsp.start({
        name = NAME,
        cmd = { bin, "--lsp", "--root", root },
        root_dir = root,
        cmd_cwd = root,
        on_attach = maybe_enable_native_completion,
    }, { bufnr = bufnr })
end

function M.stop()
    for _, client in ipairs(vim.lsp.get_clients({ name = NAME })) do
        vim.lsp.stop_client(client.id)
    end
end

return M
