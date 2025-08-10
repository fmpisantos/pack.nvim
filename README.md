# pack.nvim (nvim@0.12.0)

A lightweight Neovim plugin manager that simplifies plugin organization and batch installation with interactive prompts.

## Installation

Add pack.nvim to your Neovim configuration:

```lua
vim.pack.add({"https://github.com/fmpisantos/pack.nvim"})
```

## Quick Start

```lua
local pack = require("pack")

-- Add plugins from a directory
pack.require("plugins")

-- Add a specific plugin file
pack.require("plugins.example.init")

-- Install all queued plugins with a single prompt
pack.install()
```

## API Reference

### `pack.require(path)`

Adds plugin sources to the installation queue.

**Parameters:**
- `path` (string): The module path to require
  - Use folder paths to include all files in a directory
  - Use dot notation for file paths (e.g., `"plugins.example.init"`)
  - Dots (`.`) represent directory separators (`/`)

**Examples:**
```lua
-- Add all plugins from the plugins/ directory
pack.require("plugins")

-- Add a specific plugin configuration file
pack.require("plugins.lsp.init")
pack.require("plugins.ui.statusline")
```

### `pack.install()`

Executes the installation process for all queued plugin sources.

**Behavior:**
- Runs `vim.pack.add()` for each queued source
- Calls `.setup()` on each installed plugin
- Groups all queued sources into a single installation prompt
- Clears the queue after installation

**Example:**
```lua
-- Queue multiple plugins
pack.require("plugins.editor")
pack.require("plugins.git")
pack.require("plugins.lsp")

-- Install all queued plugins with one prompt
pack.install()
```

## Usage Patterns

### Basic Plugin Organization

Organize your plugins in separate files and directories:

```
lua/
├── plugins/
│   ├── init.lua          -- Core plugins
│   ├── editor.lua        -- Editor enhancements
│   ├── lsp/
│   │   ├── init.lua      -- LSP configuration
│   │   └── servers.lua   -- Server configs
│   └── ui/
│       ├── colorscheme.lua
│       └── statusline.lua
```

```lua
local pack = require("pack")

-- Load core plugins
pack.require("plugins")

-- Load LSP configuration
pack.require("plugins.lsp")

-- Install everything in one go
pack.install()
```

### Grouped Installation

You can create separate installation groups for different types of plugins:

```lua
local pack = require("pack")

-- Group 1: Essential plugins
pack.require("plugins.core")
pack.require("plugins.editor")
pack.install() -- First installation prompt

-- Group 2: Optional enhancements
pack.require("plugins.ui")
pack.require("plugins.extras")
pack.install() -- Second installation prompt
```

### Conditional Plugin Loading

```lua
local pack = require("pack")

-- Always load core plugins
pack.require("plugins.core")

-- Conditionally load development plugins
if vim.fn.isdirectory(".git") == 1 then
  pack.require("plugins.git")
  pack.require("plugins.dev")
end

pack.install()
```

## File Structure Examples

### Plugin Configuration Files

Each plugin file should return a configuration table. The `src` field follows the same specification as `vim.pack.add()`, supporting all the same options and formats.

#### Simple Plugin Configuration
```lua
-- plugins/editor.lua
return {
    src = "nvim-treesitter/nvim-treesitter",
    deps = {
        "windwp/nvim-autopairs",
        {src = "numToStr/Comment.nvim"} 
    }
}
```

#### Plugin with Setup Function
```lua
-- plugins/lsp/init.lua
return {
  "neovim/nvim-lspconfig",
  "hrsh7th/nvim-cmp",
  setup = function()
    -- LSP setup code here
  end
}
```
#### Supported `src` Formats

Since pack.nvim uses `vim.pack.add()` internally, your `src` field can use any format supported by `vim.pack.add()`:

- **String format**: `src = "owner/repo"`
- **Table format**: `src = { src = "owner/repo" }`
- **Array of plugins**: `src = { "plugin1", "plugin2", { src = "plugin3" } }`

All standard `vim.pack.add()` options are supported. See |vim.pack.Spec| for the complete specification of available options.

## Benefits

- **Organized Configuration**: Keep related plugins grouped in logical files and directories
- **Batch Installation**: Install multiple plugins with a single confirmation prompt
- **Flexible Loading**: Load plugins conditionally or in separate groups
- **Simple API**: Just two main functions to learn and use
- **Path Flexibility**: Use directory paths or specific file paths as needed

## Tips

1. **Group Related Plugins**: Keep similar functionality together (LSP, UI, editor tools)
2. **Use Descriptive Paths**: Make your plugin organization self-documenting
3. **Separate Optional Plugins**: Use multiple `install()` calls to separate essential from optional plugins
4. **Leverage Conditionals**: Only load plugins when needed based on project type or environment

## Troubleshooting

- Ensure all required paths exist and contain valid Lua modules
- Check that plugin files return proper configuration tables
- Verify paths use dot notation correctly (dots instead of slashes)
- Make sure `pack.install()` is called after all `pack.require()` calls for each group
