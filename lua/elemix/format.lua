local config = require("elemix.config")
local resolve = require("elemix.resolve")

local uv = vim.uv or vim.loop
local M = {}

-- The template formatter (`etf`) as an in-process LSP server. It mirrors the VS
-- Code integration: template diagnostics (squiggles), a "Format template"
-- quick-fix per unformatted template, and whole-file formatting. Running it as a
-- server means diagnostics, code actions, and formatting all flow through
-- Neovim's native LSP client - no extra plumbing, and the fixes show up in the
-- normal code-action menu.
local NAME = "elemix-formatter"

-- Pipe `input` through `etf <mode>` and hand stdout (or nil) to `cb`. The result
-- is marshalled back onto the main loop (vim.system's callback runs in a fast
-- event context, where LSP dispatch / API calls are forbidden). vim.system also
-- throws synchronously when the binary is missing, so guard the spawn too.
--
-- Width/indent are NOT passed as flags: `etf` reads them from `elemix.toml` at
-- the project root, so we just tell it where the root is with `--root`.
local function run_etf(root, mode, input, cb)
    local bin = resolve.formatter_bin(root, config.options.formatter.path)
    local cmd = { bin, mode }
    if root then
        cmd[#cmd + 1] = "--root"
        cmd[#cmd + 1] = root
    end
    local ok = pcall(vim.system, cmd, { stdin = input, text = true }, function(res)
        vim.schedule(function()
            cb((res.code == 0) and res.stdout or nil)
        end)
    end)
    if not ok then
        cb(nil)
    end
end

local function pos_le(a, b)
    return a.line < b.line or (a.line == b.line and a.character <= b.character)
end

-- Do two LSP ranges overlap? Used to offer the fix only for the template the
-- cursor/selection actually touches, like the VS Code provider.
local function ranges_intersect(a, b)
    return pos_le(a.start, b["end"]) and pos_le(b.start, a["end"])
end

-- End position of a document, as an LSP position.
local function doc_end(text)
    local lines = vim.split(text, "\n", { plain = true })
    return { line = #lines - 1, character = #lines[#lines] }
end

-- Turn one `etf --lsp` entry into an LSP diagnostic (warning).
local function to_diagnostic(d)
    return {
        range = d.range,
        severity = 2,
        message = d.message,
        source = "elemix",
    }
end

-- Build the in-process server bound to a project root (for binary resolution).
local function make_server(root)
    return function(dispatchers)
        local closing = false
        local docs = {} -- uri -> latest full text
        local timers = {} -- uri -> debounce timer

        local function publish(uri)
            local text = docs[uri]
            if not text then
                return
            end
            run_etf(root, "--lsp", text, function(out)
                if not out then
                    return
                end
                local ok, parsed = pcall(vim.json.decode, out)
                if not ok or type(parsed) ~= "table" then
                    return
                end
                local diags = {}
                for _, d in ipairs(parsed) do
                    diags[#diags + 1] = to_diagnostic(d)
                end
                dispatchers.notification("textDocument/publishDiagnostics", {
                    uri = uri,
                    diagnostics = diags,
                })
            end)
        end

        local function schedule_publish(uri)
            if timers[uri] then
                timers[uri]:stop()
                timers[uri]:close()
            end
            local t = uv.new_timer()
            timers[uri] = t
            t:start(
                300,
                0,
                vim.schedule_wrap(function()
                    if timers[uri] == t then
                        t:stop()
                        t:close()
                        timers[uri] = nil
                    end
                    publish(uri)
                end)
            )
        end

        local srv = {}

        function srv.request(method, params, callback)
            if method == "initialize" then
                callback(nil, {
                    capabilities = {
                        textDocumentSync = { openClose = true, change = 1 },
                        codeActionProvider = true,
                        documentFormattingProvider = true,
                    },
                    serverInfo = { name = NAME },
                })
            elseif method == "textDocument/codeAction" then
                local uri = params.textDocument.uri
                local text = docs[uri]
                if not text then
                    callback(nil, {})
                    return true, 1
                end
                run_etf(root, "--lsp", text, function(out)
                    local actions = {}
                    if out then
                        local ok, parsed = pcall(vim.json.decode, out)
                        if ok and type(parsed) == "table" then
                            for _, d in ipairs(parsed) do
                                if ranges_intersect(d.range, params.range) then
                                    actions[#actions + 1] = {
                                        title = "Format template",
                                        kind = "quickfix",
                                        edit = {
                                            changes = {
                                                [uri] = {
                                                    { range = d.range, newText = d.edit },
                                                },
                                            },
                                        },
                                    }
                                end
                            end
                        end
                    end
                    callback(nil, actions)
                end)
            elseif method == "textDocument/formatting" then
                local uri = params.textDocument.uri
                local text = docs[uri]
                if not text then
                    callback(nil, nil)
                    return true, 1
                end
                run_etf(root, "--stdin", text, function(out)
                    if not out or out == text then
                        callback(nil, nil)
                        return
                    end
                    callback(nil, {
                        {
                            range = {
                                start = { line = 0, character = 0 },
                                ["end"] = doc_end(text),
                            },
                            newText = out,
                        },
                    })
                end)
            elseif method == "shutdown" then
                callback(nil, nil)
            else
                callback(nil, nil)
            end
            return true, 1
        end

        function srv.notify(method, params)
            if method == "textDocument/didOpen" then
                local td = params.textDocument
                docs[td.uri] = td.text
                publish(td.uri)
            elseif method == "textDocument/didChange" then
                local uri = params.textDocument.uri
                local changes = params.contentChanges
                if changes and changes[#changes] then
                    docs[uri] = changes[#changes].text
                end
                schedule_publish(uri)
            elseif method == "textDocument/didClose" then
                local uri = params.textDocument.uri
                docs[uri] = nil
                if timers[uri] then
                    timers[uri]:stop()
                    timers[uri]:close()
                    timers[uri] = nil
                end
                dispatchers.notification("textDocument/publishDiagnostics", {
                    uri = uri,
                    diagnostics = {},
                })
            elseif method == "exit" then
                closing = true
            end
            return true
        end

        function srv.is_closing()
            return closing
        end

        function srv.terminate()
            closing = true
        end

        return srv
    end
end

-- Start (or reuse) the formatter server for a buffer's project root.
function M.start(bufnr)
    if vim.bo[bufnr].filetype ~= "typescript" then
        return
    end
    local root = resolve.root(bufnr)
    if not root then
        return
    end
    vim.lsp.start({
        name = NAME,
        cmd = make_server(root),
        root_dir = root,
    }, { bufnr = bufnr })
end

function M.stop()
    for _, client in ipairs(vim.lsp.get_clients({ name = NAME })) do
        vim.lsp.stop_client(client.id)
    end
end

-- `:ElemixFormat` - reformat every `tpl` template in the file, via the server's
-- documentFormatting. `async = false` so it also works as a save hook.
function M.format(bufnr)
    bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf()
        or bufnr
    vim.lsp.buf.format({ name = NAME, bufnr = bufnr, async = false })
end

-- Format-on-save: always pipe the buffer through `etf --stdin --on-save`, which
-- formats only when elemix.toml's `[formatter] format_on_save` is true and the
-- formatter is enabled - otherwise it echoes the buffer back unchanged. So the
-- on/off lives in the project config, not here. Synchronous (BufWritePre).
function M.on_save(bufnr)
    if vim.bo[bufnr].filetype ~= "typescript" then
        return
    end
    local root = resolve.root(bufnr)
    local bin = resolve.formatter_bin(root, config.options.formatter.path)
    local src = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    local cmd = { bin, "--stdin", "--on-save" }
    if root then
        cmd[#cmd + 1] = "--root"
        cmd[#cmd + 1] = root
    end
    local ok, res = pcall(function()
        return vim.system(cmd, { stdin = src, text = true }):wait()
    end)
    if not ok or res.code ~= 0 or not res.stdout then
        return
    end
    local out = res.stdout:gsub("\n$", "")
    if out == "" or out == src then
        return
    end
    local view = vim.fn.winsaveview()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(out, "\n", { plain = true }))
    vim.fn.winrestview(view)
end

return M
