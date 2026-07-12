local uv = vim.uv or vim.loop
local is_win = vim.fn.has("win32") == 1

local M = {}

-- The project root for a buffer: the nearest ancestor holding one of these
-- markers. This is the analog of the VS Code "workspace folder" the analyzer is
-- rooted at (`node_modules` first, where the installed binaries live).
local MARKERS = { "node_modules", "package.json", "tsconfig.json", ".git" }

function M.root(bufnr)
    if vim.api.nvim_buf_get_name(bufnr) == "" then
        return nil
    end
    return vim.fs.root(bufnr, MARKERS)
end

local function local_bin(root, name)
    local exe = name .. (is_win and ".cmd" or "")
    local p = root .. "/node_modules/.bin/" .. exe
    if uv.fs_stat(p) then
        return p
    end
    return nil
end

-- `etf`: an explicit setting, else the project's installed launcher, else `etf`
-- on PATH.
function M.formatter_bin(root, custom)
    custom = vim.trim(custom or "")
    if custom ~= "" then
        return custom
    end
    if root then
        local p = local_bin(root, "etf")
        if p then
            return p
        end
    end
    return "etf"
end

-- `ea`: an explicit setting, else the project's installed launcher, else nil.
-- The analyzer is a project tool, so (unlike the formatter) we never guess a
-- PATH binary; when neither is present the server simply stays off.
function M.analyzer_bin(root, custom)
    custom = vim.trim(custom or "")
    if custom ~= "" then
        return custom
    end
    if root then
        return local_bin(root, "ea")
    end
    return nil
end

return M
