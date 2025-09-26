local M = {}

-- State tracking
M.sources = {}
M.setup_completed = {}
M.setup_functions = {}

-- Utility functions
local function starts_with(str, prefix)
    return str:sub(1, #prefix) == prefix
end

local function normalize_github_url(source)
    if type(source) == "string" then
        return starts_with(source, "https://") and source or ("https://github.com/" .. source)
    end
    return source
end

local function extract_plugin_name_from_url(url)
    return url:gsub("https://.-/", "")
end

local function extract_plugins_recursive(source_spec)
    local plugins = {}

    if type(source_spec) == "string" then
        plugins[#plugins + 1] = normalize_github_url(source_spec)
    elseif type(source_spec) == "table" then
        if source_spec.src then
            -- Single plugin with configuration
            local plugin_config = { src = normalize_github_url(source_spec.src) }

            -- Copy other configuration options
            for key, value in pairs(source_spec) do
                if key ~= "src" then
                    plugin_config[key] = value
                end
            end

            plugins[#plugins + 1] = plugin_config
        else
            -- Array of plugins
            for _, item in ipairs(source_spec) do
                local extracted = extract_plugins_recursive(item)
                for _, plugin in ipairs(extracted) do
                    plugins[#plugins + 1] = plugin
                end
            end
        end
    end

    return plugins
end

local function get_plugin_src(plugin_spec)
    if type(plugin_spec) == "string" then
        return plugin_spec
    end
    return plugin_spec.src or plugin_spec[1] and (plugin_spec[1].src or plugin_spec[1])
end

local function get_plugin_key(plugin_spec)
    local source_url = get_plugin_src(plugin_spec)
    return source_url and extract_plugin_name_from_url(source_url) or nil
end

local function get_plugin_identifier(plugin_spec)
    if type(plugin_spec) == "string" then
        return extract_plugin_name_from_url(normalize_github_url(plugin_spec))
    elseif plugin_spec.src then
        return extract_plugin_name_from_url(normalize_github_url(plugin_spec.src))
    elseif plugin_spec.name then
        return plugin_spec.name
    end
    return nil
end

local function get_plugin_repo_name(plugin_spec)
    local identifier = get_plugin_identifier(plugin_spec)
    if identifier then
        -- Extract just the repo name (after the last /)
        return identifier:match("([^/]+)$")
    end
    return nil
end

-- Add a plugin source
M.src = function(source)
    M.sources[#M.sources + 1] = source
end

-- Require modules and collect their sources
M.require = function(module_path)
    local config_path = vim.fn.stdpath("config") .. "/lua/" .. module_path:gsub("%.", "/")

    local is_file = vim.fn.filereadable(config_path .. ".lua") == 1
    local is_directory = vim.fn.isdirectory(config_path) == 1

    if is_file then
        M._load_module(module_path)
    elseif is_directory then
        M._load_directory_modules(config_path, module_path)
    else
        vim.notify("Path " .. config_path .. " is neither a file nor a directory", vim.log.levels.ERROR)
    end
end

-- Private helper functions
M._load_module = function(module_path)
    local ok, module = pcall(require, module_path)
    if ok and type(module) == "table" and module.src then
        M.src(module)
    end
end

M._load_directory_modules = function(config_path, base_module_path)
    local lua_files = vim.fn.readdir(config_path, [[v:val =~ '\.lua$']])

    for _, file in ipairs(lua_files) do
        local module_name = file:gsub("%.lua$", "")
        local full_module_path = base_module_path .. "." .. module_name
        M._load_module(full_module_path)
    end
end

-- Setup a plugin with dependency resolution
local function setup_plugin(setup_config, plugin_name, dependency_chain)
    if setup_config == nil then
        return true
    end

    -- Mark as being processed to detect circular dependencies
    dependency_chain[get_plugin_key(plugin_name)] = true
    -- Setup dependencies first
    if setup_config.deps then
        local list = setup_config.deps.src and { setup_config.deps } or setup_config.deps
        for _, dependency in ipairs(list) do
            if not M.setup_completed[dependency] then
                -- Check for circular dependency
                if dependency_chain[dependency] then
                    vim.notify("Circular dependency detected for " .. plugin_name .. " -> " .. dependency,
                        vim.log.levels.ERROR)
                    return false
                end

                -- Recursively setup dependency
                local key = get_plugin_key(dependency)
                if not setup_plugin(M.setup_functions[key], key, dependency_chain) then
                    return false
                end
            else
            end
        end
    end

    -- Setup the plugin when event triggers
    if type(setup_config.setup) == "function" and not M.setup_completed[plugin_name] then
        local events = setup_config.event
        if events then
            if type(events) == "string" then
                events = { events }
            end

            vim.api.nvim_create_autocmd(events, {
                callback = function(args)
                    if args.event ~= "VimEnter" and args.file:match("^oil://") then
                        return
                    end
                    vim.defer_fn(function()
                        if not M.setup_completed[plugin_name] then
                            setup_config.setup()
                            M.setup_completed[plugin_name] = true
                        end
                    end, 10)
                end,
            })
        else
            -- No event: setup immediately
            setup_config.setup()
            M.setup_completed[plugin_name] = true
        end
    end

    return true
end

local function prepare_plugin(source, all_plugins, parent_event)
    source = source.src and source or { src = source }
    local extracted_plugins = extract_plugins_recursive(source.src and source.src or source)

    -- Handle setup function and dependencies
    if source.setup then
        local setup_config = { setup = source.setup, deps = source.deps, event = source.event or parent_event }

        -- Process dependencies
        if source.deps then
            local list = type(source.deps) == "table" and source.deps or { source.deps }
            for _, dep in ipairs(list) do
                prepare_plugin(dep, all_plugins, source.event or parent_event)
            end
        end

        -- Register setup function
        local plugin_key = get_plugin_key(extracted_plugins)
        if plugin_key then
            M.setup_functions[plugin_key] = setup_config
        end
    end

    -- Add main plugins to installation list
    for _, plugin in ipairs(extracted_plugins) do
        all_plugins[#all_plugins + 1] = plugin
    end
end

M.cleanup_unused_plugins = function(required_plugins)
    local installed_packs = vim.pack.get()
    local required_repo_names = {}

    -- Build set of required plugin repo names
    for _, plugin in ipairs(required_plugins) do
        local repo_name = get_plugin_repo_name(plugin)
        if repo_name then
            required_repo_names[repo_name] = true
        end
    end

    -- Find plugin names to remove
    local plugin_names_to_remove = {}
    for _, pack in ipairs(installed_packs) do
        local pack_repo_name = pack.spec.name
        if pack_repo_name and not required_repo_names[pack_repo_name] then
            table.insert(plugin_names_to_remove, pack_repo_name)
        end
    end

    -- Remove unused plugins
    if #plugin_names_to_remove > 0 then
        vim.notify("Removing " .. #plugin_names_to_remove .. " unused plugins", vim.log.levels.INFO)

        -- Remove plugins by name
        vim.pack.del(plugin_names_to_remove)

        vim.notify("Removed " .. #plugin_names_to_remove .. " unused plugins", vim.log.levels.INFO)
    end
end

-- List installed plugins
M.list = function()
    local installed_packs = vim.pack.get()

    if #installed_packs == 0 then
        vim.notify("No plugins installed", vim.log.levels.INFO)
        return
    end

    vim.notify("Installed plugins (" .. #installed_packs .. "):", vim.log.levels.INFO)

    for _, pack in ipairs(installed_packs) do
        local status = pack.active and "[ACTIVE]" or "[INACTIVE]"
        local version = pack.spec.version or "unknown"
        vim.notify(string.format("  %s %s (%s)", status, pack.spec.name, version), vim.log.levels.INFO)
    end
end

-- Update a specific plugin
M.update = function(plugin_name)
    if not plugin_name or plugin_name == "" then
        vim.notify("Please specify a plugin name to update", vim.log.levels.ERROR)
        return
    end

    -- Check if plugin is installed
    local installed_packs = vim.pack.get()
    local found = false

    for _, pack in ipairs(installed_packs) do
        if pack.spec.name == plugin_name then
            found = true
            break
        end
    end

    if not found then
        vim.notify("Plugin '" .. plugin_name .. "' is not installed", vim.log.levels.ERROR)
        return
    end

    vim.notify("Updating plugin: " .. plugin_name, vim.log.levels.INFO)
    vim.pack.update({ plugin_name })
    vim.notify("Plugin '" .. plugin_name .. "' update completed", vim.log.levels.INFO)
end

-- Update all installed plugins
M.update_all = function()
    local installed_packs = vim.pack.get()

    if #installed_packs == 0 then
        vim.notify("No plugins installed to update", vim.log.levels.INFO)
        return
    end

    vim.notify("Updating all " .. #installed_packs .. " installed plugins...", vim.log.levels.INFO)

    -- Collect all plugin names
    local plugin_names = {}
    for _, pack in ipairs(installed_packs) do
        table.insert(plugin_names, pack.spec.name)
    end

    -- Update all plugins
    vim.pack.update(plugin_names)
    vim.notify("All plugins update completed", vim.log.levels.INFO)
end

-- Get all required plugins from sources
M.get_required_plugins = function()
    local all_plugins = {}

    -- Process all sources
    for _, source in ipairs(M.sources) do
        prepare_plugin(source, all_plugins, nil)
    end

    return all_plugins
end

-- Main installation function
M.install = function()
    local all_plugins = M.get_required_plugins()

    -- Install all plugins
    vim.pack.add(all_plugins)

    -- Run setup functions for all plugins
    for plugin_name, setup_config in pairs(M.setup_functions) do
        setup_plugin(setup_config, plugin_name, {})
    end
end

-- Cleanup unused plugins
M.cleanup = function()
    local required_plugins = M.get_required_plugins()
    M.cleanup_unused_plugins(required_plugins)
end

-- Completion function for PackUpdate command
local function pack_update_completion(arg_lead, cmd_line, cursor_pos)
    local installed_packs = vim.pack.get()
    local completions = {}

    for _, pack in ipairs(installed_packs) do
        if pack.spec.name:lower():find(arg_lead:lower(), 1, true) then
            table.insert(completions, pack.spec.name)
        end
    end

    table.sort(completions)
    return completions
end

-- Create user commands
vim.api.nvim_create_user_command("PackList", function()
    M.list()
end, {
    desc = "List all installed plugins"
})

vim.api.nvim_create_user_command("PackUpdate", function(opts)
    M.update(opts.args)
end, {
    desc = "Update a specific plugin",
    nargs = 1,
    complete = pack_update_completion
})

vim.api.nvim_create_user_command("PackUpdateAll", function()
    M.update_all()
end, {
    desc = "Update all installed plugins"
})

vim.api.nvim_create_user_command("PackCleanup", function()
    M.cleanup()
end, {
    desc = "Remove unused plugins"
})

return M;
