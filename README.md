<img src="https://raw.githubusercontent.com/neuralfog/elemix/main/.readme/elemix-banner.svg" alt="elemix - Reactive Elements" width="100%" />

# Elemix extension for neovim

## Features

- Syntax highlighting for `tpl` templates.
- Prop typechecking diagnostics: prop type mismatches, missing required props, unknown props, duplicated props.
- Completion: `:prop`, `@event`, `~model`/`~onmodel`.
- Completion: compiler hints `// #...`.
- Completion: components tags with default props inlined.
- Hover: compiler hints docs.
- Hover: component tags listing props.
- Code actions: auto-import a used-but-unimported component.
- Code actions: format templates.
- Resolves `elemix-analyzer` and `elemix-template-formatter` from your project's `node_modules`.

## Commands

- `:ElemixFormat` - format elemix file.
- `:ElemixRestart` - restart lsp server.

## Installation

Needs Neovim 0.10+. If you already have a Neovim config, skip to [With an existing config](#with-an-existing-config).

### From scratch (no config yet)

1. Create the config file:

   - Linux/macOS: `~/.config/nvim/init.lua`
   - Windows: `~/AppData/Local/nvim/init.lua`

2. Paste this into it. It bootstraps the [lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager, then installs this plugin and Treesitter:

   ```lua
   -- Bootstrap the lazy.nvim plugin manager.
   local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
   if not (vim.uv or vim.loop).fs_stat(lazypath) then
     vim.fn.system({
       'git', 'clone', '--filter=blob:none',
       'https://github.com/folke/lazy.nvim.git', '--branch=stable', lazypath,
     })
   end
   vim.opt.rtp:prepend(lazypath)

   -- Install plugins.
   require('lazy').setup({
     { 'nvim-treesitter/nvim-treesitter', build = ':TSUpdate' },
     {
       'neuralfog/elemix.nvim',
       dependencies = { 'nvim-treesitter/nvim-treesitter' },
     },
   })
   ```

3. Start Neovim. lazy.nvim clones and installs everything on first launch.

4. Install the Treesitter parsers used for highlighting:

   ```vim
   :TSInstall typescript html
   ```

Open a `.ts` file with a `tpl` template and the plugin is active.

### With an existing config

Add the plugin to your lazy.nvim spec (e.g. a new file `lua/plugins/elemix.lua`):

```lua
return {
  {
    'neuralfog/elemix.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
  },
}
```

Then install the parsers once: `:TSInstall typescript html`.

### Configuration (optional)

No `setup` call is required. To change a default:

```lua
require('elemix').setup({
  analyzer = { path = '' },        -- override the `ea` binary; empty uses node_modules/.bin/ea
  formatter = {
    path = '',                     -- override `etf`; empty uses node_modules/.bin/etf, then PATH
  },
  completion = 'auto',             -- native completion fallback: 'auto' | true | false
})
```

### Formatter config

Formatter config is read from an `elemix.toml` file at your project root, not from editor settings. Create one to change the defaults:

```toml
[formatter]
enabled = true           # false turns the formatter off entirely
indent_style = "space"   # "space" (default) or "tab"
indent_width = 4         # columns per indent level
line_width = 80          # max line width
format_on_save = false   # format tpl templates on save
```
