-- Work around an nvim tree-sitter bug that crashes the highlighter.
--
-- While resolving injections, `LanguageTree:_get_injections` can be handed a
-- query match whose captured node is nil; computing its range then throws
-- `attempt to call method 'range' (a nil value)` (treesitter.lua). Because it
-- runs inside the highlighter's decoration provider it takes down ALL
-- highlighting for the buffer.
--
-- Observed with `lang = markdown`: an LSP hover popup renders as a markdown
-- buffer, markdown injects the fenced ```code``` block's language, and that
-- injection hits the nil node - so every hover over a typed symbol crashes. It
-- is not elemix-specific, but elemix users hover constantly, so we neutralise it.
--
-- We wrap the shared LanguageTree method in a pcall and skip injections for that
-- pass on error. Patching the class method fixes every parser (any language, any
-- buffer, any load order) - which query-level or per-buffer fixes could not.

local M = {}

function M.apply()
    local ok, LT = pcall(require, "vim.treesitter.languagetree")
    if not ok or type(LT) ~= "table" or type(LT._get_injections) ~= "function" then
        return false
    end
    -- Guard on the class table so it is wrapped exactly once.
    if LT.__elemix_injection_patched then
        return true
    end
    LT.__elemix_injection_patched = true
    local original = LT._get_injections
    LT._get_injections = function(self, ...)
        local safe, result = pcall(original, self, ...)
        if safe then
            return result
        end
        -- Injection resolution threw (the nil-node bug). Skip injections for this
        -- pass rather than crash the highlighter; the next parse will retry.
        return {}
    end
    return true
end

return M
