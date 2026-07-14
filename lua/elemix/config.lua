local M = {}

-- Mirrors the VS Code extension's `elemix.*` settings (package.json).
M.defaults = {
    analyzer = {
        -- Path to the `ea` analyzer binary for the LSP server. Empty resolves the
        -- project's node_modules/.bin/ea; if that is absent the analyzer stays off.
        path = "",
    },
    formatter = {
        -- Path to the `etf` template formatter binary. Empty resolves the project's
        -- node_modules/.bin/etf, then `etf` on PATH.
        --
        -- Whether the formatter runs, plus width and indentation, is read from
        -- `elemix.toml` at the project root, not here. Format-on-save is a per-
        -- project toggle (`:ElemixFormatOnSave`), persisted in the nvim data dir.
        path = "",
    },
    -- Native LSP completion (`vim.lsp.completion` autotrigger). Any completion
    -- engine (blink.cmp, nvim-cmp, coq, ...) already sources our LSP server, so
    -- forcing native completion on top would make two engines race. Modes:
    --   "auto"  (default) enable native only when NO engine is detected, so a
    --           bare Neovim still gets an autocomplete popup, and an engine is
    --           left untouched (it, and native `<C-x><C-o>`, keep working).
    --   true    always enable native completion.
    --   false   never enable it; rely on your engine or `<C-x><C-o>`.
    completion = "auto",
}

M.options = vim.deepcopy(M.defaults)

function M.set(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    return M.options
end

return M
