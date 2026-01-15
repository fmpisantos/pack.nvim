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

### `pack.update()` / `:PackUpdate`

Checks all installed packages for available updates and displays them in a Telescope picker.

**Behavior:**
- Fetches from origin for all installed packages (parallelized for speed)
- Compares local HEAD with remote HEAD to detect available updates
- Shows progress notifications during the check process
- If no updates are available, shows a notification and exits
- If updates are found, opens a Telescope picker with selectable packages
- Calls `vim.pack.update()` for selected packages

**Telescope Picker Controls:**
- `<Enter>` - Update the selected package (or all packages if "Update All" is selected)
- `<Tab>` - Toggle selection for multi-select
- `<C-q>` - Confirm and update all selected packages

**Example:**
```lua
-- Programmatic usage
require("pack").update()

-- Or use the command
:PackUpdate
```

**Note:** Telescope is required for the update picker interface.

### `pack.config`

Configuration options for pack.nvim behavior.

**Options:**
- `parallel_check_count` (number): Number of packages to check in parallel during `:PackUpdate` (default: 4)

**Example:**
```lua
local pack = require("pack")

-- Increase parallel checks for faster updates with many plugins
pack.config.parallel_check_count = 8

-- Queue and install plugins
pack.require("plugins")
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

#### Plugin with Event Triggering
```lua
-- plugins/ui/statusline.lua
return {
  src = "nvim-lualine/lualine.nvim",
  event = "VimEnter", -- Load on VimEnter event
  setup = function()
    require("lualine").setup()
  end
}
```

#### Plugin with Multiple Events
```lua
-- plugins/editor/completion.lua
return {
  src = "hrsh7th/nvim-cmp",
  event = {"InsertEnter", "CmdlineEnter"}, -- Load on multiple events
  deps = {
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path"
  },
  setup = function()
    local cmp = require("cmp")
    cmp.setup({
      -- configuration here
    })
  end
}
```

#### Supported `src` Formats

Since pack.nvim uses `vim.pack.add()` internally, your `src` field can use any format supported by `vim.pack.add()`:

- **String format**: `src = "owner/repo"`
- **Table format**: `src = { src = "owner/repo" }`
- **Array of plugins**: `src = { "plugin1", "plugin2", { src = "plugin3" } }`

All standard `vim.pack.add()` options are supported. See |vim.pack.Spec| for the complete specification of available options.

#### Plugin Event Loading

You can control when plugins are loaded using the `event` option:

**Parameters:**
- `event` (string|table): Autocmd event(s) that trigger plugin loading
  - Single event: `event = "BufRead"`
  - Multiple events: `event = {"BufRead", "BufNewFile"}`

**Important Notes:**
- **Oil Files Limitation**: Autocmd events are not available when working with oil files
- **VimEnter Recommendation**: If you need plugins to load in oil file contexts, use `event = "VimEnter"` as it's the only event that reliably triggers for oil files

**Examples:**
```lua
-- Load on file read
return {
  src = "nvim-treesitter/nvim-treesitter",
  event = "BufRead"
}

-- Load on multiple events
return {
  src = "telescope.nvim",
  event = {"VimEnter", "BufWinEnter"}
}

-- For oil file compatibility
return {
  src = "oil.nvim",
  event = "VimEnter" -- Only event that works reliably with oil files
}
```

## Benefits

- **Organized Configuration**: Keep related plugins grouped in logical files and directories
- **Batch Installation**: Install multiple plugins with a single confirmation prompt
- **Easy Updates**: Check and update packages interactively with `:PackUpdate`
- **Flexible Loading**: Load plugins conditionally or in separate groups, with event-based triggering
- **Simple API**: Just a few functions to learn and use
- **Path Flexibility**: Use directory paths or specific file paths as needed
- **Event Control**: Fine-tune when plugins load using autocmd events

## Tips

1. **Group Related Plugins**: Keep similar functionality together (LSP, UI, editor tools)
2. **Use Descriptive Paths**: Make your plugin organization self-documenting
3. **Separate Optional Plugins**: Use multiple `install()` calls to separate essential from optional plugins
4. **Leverage Conditionals**: Only load plugins when needed based on project type or environment
5. **Choose Events Wisely**: Use specific events to optimize startup time and plugin loading
6. **Oil File Consideration**: When working with oil files, prefer `VimEnter` for reliable plugin loading
7. **Regular Updates**: Run `:PackUpdate` periodically to keep your plugins up to date

## Troubleshooting

- Ensure all required paths exist and contain valid Lua modules
- Check that plugin files return proper configuration tables
- Verify paths use dot notation correctly (dots instead of slashes)
- Make sure `pack.install()` is called after all `pack.require()` calls for each group
- When using events, verify the event names are valid autocmd events
- For oil file compatibility issues, try using `event = "VimEnter"` instead of other events
- `:PackUpdate` requires Telescope to be installed for the picker interface
