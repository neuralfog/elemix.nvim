-- Persistent per-project editor state, the nvim analog of a VS Code workspace
-- setting. Currently just the format-on-save toggle. Stored as JSON under the
-- Neovim data dir, keyed by project root, so a toggle survives restarts and is
-- scoped to the project (matching the VS Code `elemix.formatter.formatOnSave`
-- workspace setting).

local M = {}

local function dir()
    return vim.fn.stdpath("data") .. "/elemix"
end

local function file()
    return dir() .. "/state.json"
end

-- Roots that resolve to nil (an unsaved buffer) share one global slot.
local function key(root)
    return root or "__global__"
end

local function read_all()
    local fd = io.open(file(), "r")
    if not fd then
        return {}
    end
    local content = fd:read("*a")
    fd:close()
    local ok, parsed = pcall(vim.json.decode, content)
    if not ok or type(parsed) ~= "table" then
        return {}
    end
    return parsed
end

local function write_all(tbl)
    vim.fn.mkdir(dir(), "p")
    local fd = io.open(file(), "w")
    if not fd then
        return
    end
    fd:write(vim.json.encode(tbl))
    fd:close()
end

-- Is format-on-save enabled for `root`? Defaults to false.
function M.format_on_save(root)
    local entry = read_all()[key(root)]
    return type(entry) == "table" and entry.format_on_save == true
end

-- Persist the format-on-save flag for `root`.
function M.set_format_on_save(root, value)
    local all = read_all()
    local k = key(root)
    all[k] = all[k] or {}
    all[k].format_on_save = value and true or false
    write_all(all)
end

return M
