-- Markup highlighting for tpl`...` templates.
--
-- A port of the VS Code TextMate grammar
-- (packages/vscode/syntaxes/elemix-tpl.tmLanguage.json), driven by a lexical
-- state machine rather than a parser - so elemix's `:prop`/`@event`/`~model`
-- directives and arbitrary `${...}` expressions never break it (a real HTML
-- tree-sitter parser cannot handle those).
--
-- It paints extmarks at priority 200, above tree-sitter (100), so it shows even
-- though tree-sitter captures the whole template as a string. `${...}` interiors
-- are left untouched: the injection query colours them as TypeScript.

local M = {}

local ns = vim.api.nvim_create_namespace("elemix_tpl_highlight")
local PRIORITY = 200

-- Highlight groups, linked to tree-sitter captures so colours match the buffer.
-- `elemixDirective` is deliberately distinct (Special) - override to taste.
local LINKS = {
    elemixTemplateDelim = "@punctuation.special",
    elemixTagName = "@tag",
    elemixTagDelim = "@tag.delimiter",
    elemixAttr = "@tag.attribute",
    elemixDirective = "Special",
    elemixString = "@string",
    elemixInterpDelim = "@punctuation.special",
    elemixComment = "@comment",
    elemixEntity = "@character.special",
}

local GROUP = {
    templatedelim = "elemixTemplateDelim",
    tagname = "elemixTagName",
    delim = "elemixTagDelim",
    attr = "elemixAttr",
    directive = "elemixDirective",
    string = "elemixString",
    interp = "elemixInterpDelim",
    comment = "elemixComment",
    entity = "elemixEntity",
}

function M.setup_hl()
    for name, link in pairs(LINKS) do
        vim.api.nvim_set_hl(0, name, { link = link, default = true })
    end
end

-- Byte offset (0-based, into the newline-joined text) -> (row, col), both 0-based.
local function pos_lookup(starts)
    return function(offset)
        -- linear-ish binary search over line-start offsets
        local lo, hi = 1, #starts
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            if starts[mid] <= offset then
                lo = mid
            else
                hi = mid - 1
            end
        end
        return lo - 1, offset - starts[lo]
    end
end

-- Find every `tpl` `...` ` region, honouring `${...}` nesting and `\` escapes so
-- a backtick inside an interpolation or an escape does not end it early. Returns
-- 1-based [content_start, content_end] plus the backtick positions.
local function tpl_regions(text)
    local regions = {}
    local n = #text
    local i = 1
    while true do
        local s = text:find("tpl`", i, true)
        if not s then
            break
        end
        local before = s > 1 and text:sub(s - 1, s - 1) or ""
        if before == "" or not before:match("[%w_$]") then
            local open_bt = s + 3 -- position of the backtick (1-based)
            local j = open_bt + 1
            local depth = 0
            local close_bt = nil
            while j <= n do
                local ch = text:sub(j, j)
                if ch == "\\" then
                    j = j + 2
                elseif ch == "$" and text:sub(j + 1, j + 1) == "{" then
                    depth = depth + 1
                    j = j + 2
                elseif ch == "}" and depth > 0 then
                    depth = depth - 1
                    j = j + 1
                elseif ch == "`" and depth == 0 then
                    close_bt = j
                    break
                else
                    j = j + 1
                end
            end
            regions[#regions + 1] = {
                open_bt = open_bt,
                cstart = open_bt + 1,
                cend = (close_bt and close_bt - 1) or n,
                close_bt = close_bt,
            }
            -- Continue just past THIS opening backtick (not the whole region) so a
            -- nested tpl`` inside a ${...} interpolation is found and highlighted
            -- too. Its markup lands inside the outer region's ${} - which the outer
            -- scan leaves bare - so the two never conflict.
            i = open_bt + 1
        else
            i = s + 3
        end
    end
    return regions
end

-- Skip a `${...}` starting at i (text:sub(i,i+1)=="${"); emit the delimiters,
-- leave the interior for the TypeScript injection. Returns the index after `}`.
local function skip_interp(text, i, cend, emit)
    emit(i, i + 1, "interp") -- ${
    local depth = 1
    local j = i + 2
    while j <= cend and depth > 0 do
        local c = text:sub(j, j)
        if c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
        end
        j = j + 1
    end
    if depth == 0 then
        emit(j - 1, j - 1, "interp") -- closing }
    end
    return j
end

-- A quoted attribute value, emitted as string pieces around any interpolations.
local function scan_string(text, i, cend, emit)
    local q = text:sub(i, i)
    local seg = i -- start of the current string segment
    local j = i + 1
    while j <= cend do
        local c = text:sub(j, j)
        if c == "$" and text:sub(j + 1, j + 1) == "{" then
            emit(seg, j - 1, "string")
            j = skip_interp(text, j, cend, emit)
            seg = j
        elseif c == q then
            emit(seg, j, "string")
            return j + 1
        else
            j = j + 1
        end
    end
    emit(seg, cend, "string")
    return cend + 1
end

-- Inside a tag: attributes, directives, quoted values, interpolation, until the
-- closing `>` or `/>`.
local function scan_tag_body(text, i, cend, emit)
    while i <= cend do
        local c = text:sub(i, i)
        if c == ">" then
            emit(i, i, "delim")
            return i + 1
        elseif c == "/" and text:sub(i + 1, i + 1) == ">" then
            emit(i, i + 1, "delim")
            return i + 2
        elseif c == "$" and text:sub(i + 1, i + 1) == "{" then
            i = skip_interp(text, i, cend, emit)
        elseif c == '"' or c == "'" then
            i = scan_string(text, i, cend, emit)
        elseif c:match("[:@~]") then
            local _, de = text:find("^[:@~][%a][%w._-]*", i)
            -- a directive only when it names an attribute (followed by `=`)
            if de and text:find("^%s*=", de + 1) then
                emit(i, de, "directive")
                i = de + 1
            else
                i = i + 1
            end
        elseif c:match("[%a_]") then
            local _, ae = text:find("^[%a_][%w:._-]*", i)
            emit(i, ae, "attr")
            i = (ae or i) + 1
        else
            i = i + 1
        end
    end
    return i
end

-- Tokenise a template body [cstart, cend].
local function scan_body(text, cstart, cend, emit)
    local i = cstart
    while i <= cend do
        local c = text:sub(i, i)
        if text:sub(i, i + 3) == "<!--" then
            local e = text:find("-->", i + 4, true)
            local last = e and (e + 2) or cend
            emit(i, math.min(last, cend), "comment")
            i = math.min(last, cend) + 1
        elseif c == "$" and text:sub(i + 1, i + 1) == "{" then
            i = skip_interp(text, i, cend, emit)
        elseif c == "<" and text:sub(i + 1, i + 1):match("[%a/]") then
            local slash = text:sub(i + 1, i + 1) == "/"
            local nstart = slash and i + 2 or i + 1
            local _, ne = text:find("^[%a][%w:_-]*", nstart)
            emit(i, nstart - 1, "delim") -- < or </
            if ne then
                emit(nstart, ne, "tagname")
                i = scan_tag_body(text, ne + 1, cend, emit)
            else
                i = nstart
            end
        elseif c == "&" then
            local _, ee = text:find("^&[%w#]+;", i)
            if ee then
                emit(i, ee, "entity")
                i = ee + 1
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

-- Repaint one buffer.
function M.apply(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    if vim.bo[bufnr].filetype ~= "typescript" then
        return
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")
    if not text:find("tpl`", 1, true) then
        return
    end

    local starts = {}
    local off = 0
    for idx, l in ipairs(lines) do
        starts[idx] = off
        off = off + #l + 1
    end
    local to_pos = pos_lookup(starts)

    local marks = {}
    for _, r in ipairs(tpl_regions(text)) do
        local emit = function(a, b, kind)
            marks[#marks + 1] = { a - 1, b, GROUP[kind] }
        end
        emit(r.open_bt, r.open_bt, "templatedelim")
        if r.close_bt then
            emit(r.close_bt, r.close_bt, "templatedelim")
        end
        scan_body(text, r.cstart, r.cend, emit)
    end

    for _, m in ipairs(marks) do
        local sr, sc = to_pos(m[1])
        local er, ec = to_pos(m[2])
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, sr, sc, {
            end_row = er,
            end_col = ec,
            hl_group = m[3],
            priority = PRIORITY,
        })
    end
end

return M
