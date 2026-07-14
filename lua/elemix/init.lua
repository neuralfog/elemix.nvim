local config = require("elemix.config")
local lsp = require("elemix.lsp")
local format = require("elemix.format")
local highlight = require("elemix.highlight")
local ts_patch = require("elemix.ts_patch")

-- Neutralise the nvim tree-sitter injection crash on tpl`` templates as early as
-- this module is required (before any parse), independent of init().
ts_patch.apply()

local M = {}

-- Per-buffer debounce timers for highlight repaints.
local hl_timers = {}
local uv = vim.uv or vim.loop

local function highlight_soon(bufnr)
    if hl_timers[bufnr] then
        hl_timers[bufnr]:stop()
        hl_timers[bufnr]:close()
    end
    local t = uv.new_timer()
    hl_timers[bufnr] = t
    t:start(
        120,
        0,
        vim.schedule_wrap(function()
            if hl_timers[bufnr] == t then
                t:stop()
                t:close()
                hl_timers[bufnr] = nil
            end
            if vim.api.nvim_buf_is_valid(bufnr) then
                highlight.apply(bufnr)
            end
        end)
    )
end

-- TypeScript file globs. FileType `typescript` already covers .ts/.mts/.cts, so
-- these patterns only need to gate the filename-based events.
local TS_PATTERNS = { "*.ts", "*.mts", "*.cts" }

-- Restart both servers - the analyzer and the in-process formatter.
local function restart()
    lsp.stop()
    format.stop()
    vim.defer_fn(function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if
                vim.api.nvim_buf_is_loaded(b)
                and vim.bo[b].filetype == "typescript"
            then
                lsp.start(b)
                format.start(b)
            end
        end
        vim.notify("elemix: language servers restarted", vim.log.levels.INFO)
    end, 200)
end

local function define_commands()
    vim.api.nvim_create_user_command("ElemixRestart", function()
        restart()
    end, { desc = "elemix: restart the elemix language servers" })

    vim.api.nvim_create_user_command("ElemixFormat", function()
        format.format()
    end, { desc = "elemix: format tpl templates in the current file" })

    vim.api.nvim_create_user_command("ElemixFormatOnSave", function()
        format.toggle_on_save()
    end, { desc = "elemix: toggle format-on-save for this project" })
end

local function define_autocmds()
    local group = vim.api.nvim_create_augroup("elemix", { clear = true })

    -- Attach both servers when a TS file opens. The formatter server then owns
    -- diagnostics/code-actions/formatting through the LSP client - no manual
    -- refresh needed.
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "typescript",
        callback = function(ev)
            lsp.start(ev.buf)
            format.start(ev.buf)
            highlight.apply(ev.buf)
        end,
    })

    -- Repaint template markup on edits and when the buffer is shown.
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        pattern = TS_PATTERNS,
        callback = function(ev)
            highlight_soon(ev.buf)
        end,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        pattern = TS_PATTERNS,
        callback = function(ev)
            highlight.apply(ev.buf)
        end,
    })
    -- Re-assert our highlight links after a colorscheme swap.
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            highlight.setup_hl()
        end,
    })

    vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        pattern = TS_PATTERNS,
        callback = function(ev)
            format.on_save(ev.buf)
        end,
    })
end

local function check_version()
    if vim.fn.has("nvim-0.10") == 0 then
        vim.notify("elemix.nvim requires Neovim 0.10+", vim.log.levels.ERROR)
        return false
    end
    return true
end

local initialized = false

-- Wire up commands + autocmds, and attach to any TS buffers already open. Runs
-- automatically on plugin load (plugin/elemix.lua), so no setup() call is needed.
function M.init()
    if initialized then
        return
    end
    if not check_version() then
        return
    end
    initialized = true
    ts_patch.apply()
    highlight.setup_hl()
    define_commands()
    define_autocmds()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "typescript" then
            lsp.start(b)
            format.start(b)
            highlight.apply(b)
        end
    end
end

-- Optional: override the defaults. Re-applies config to a running session.
function M.setup(opts)
    config.set(opts)
    if initialized then
        restart()
    else
        M.init()
    end
end

return M
