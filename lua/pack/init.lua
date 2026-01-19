local M = {}

-- State tracking
M.sources = {}
M.setup_completed = {}
M.setup_functions = {}
M.plugin_versions = {} -- Track configured version/branch for each plugin

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

local function extract_plugins_recursive(source_spec, root_branch)
    local plugins = {}

    if type(source_spec) == "string" then
        plugins[#plugins + 1] = normalize_github_url(source_spec)
    elseif type(source_spec) == "table" then
        if source_spec.src then
            -- Single plugin with configuration
            local plugin_config = { src = normalize_github_url(source_spec.src), branch = source_spec.version or root_branch }

            -- Copy other configuration options
            for key, value in pairs(source_spec) do
                if key ~= "src" then
                    plugin_config[key] = value
                end
            end

            -- Track version/branch for update checking
            if source_spec.version then
                local plugin_name = extract_plugin_name_from_url(plugin_config.src)
                M.plugin_versions[plugin_name] = source_spec.version
            end

            plugins[#plugins + 1] = plugin_config
        else
            -- Array of plugins
            for _, item in ipairs(source_spec) do
                local extracted = extract_plugins_recursive(item, root_branch)
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
    local extracted_plugins = extract_plugins_recursive(source.src and source.src or source, source.version)

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

-- Main installation function
M.install = function()
    local all_plugins = {}

    -- Process all sources
    for _, source in ipairs(M.sources) do
        prepare_plugin(source, all_plugins, nil)
    end

    -- Install all plugins
    vim.pack.add(all_plugins)

    -- Run setup functions for all plugins
    for plugin_name, setup_config in pairs(M.setup_functions) do
        setup_plugin(setup_config, plugin_name, {})
    end
end

-- Helper function to run git commands asynchronously
local function git_cmd_async(args, cwd, callback)
    local cmd = vim.list_extend({ "git" }, args)
    vim.system(cmd, { cwd = cwd, text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                local err_msg = result.stderr or ("git command failed with code " .. tostring(result.code))
                callback(nil, err_msg)
            else
                callback(result.stdout or "", nil)
            end
        end)
    end)
end

-- Helper function to run git commands synchronously
local function git_cmd(args, cwd)
    local cmd = vim.list_extend({ "git" }, args)
    local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then
        return nil, result.stderr
    end
    return (result.stdout or ""):gsub("\n+$", "")
end

-- Get local HEAD commit hash
local function get_local_head(path)
    return git_cmd({ "rev-parse", "--short", "HEAD" }, path)
end

-- Async version: Get local HEAD commit hash
local function get_local_head_async(path, callback)
    git_cmd_async({ "rev-parse", "--short", "HEAD" }, path, callback)
end

-- Async version: Get default branch name
local function get_default_branch_async(path, callback)
    git_cmd_async({ "rev-parse", "--abbrev-ref", "origin/HEAD" }, path, function(result, err)
        if err or not result or result == "" then
            callback(nil, err or "No default branch")
        else
            callback(result:gsub("\n+$", ""), nil)
        end
    end)
end

-- Async version: Get the current branch's upstream tracking ref
local function get_upstream_ref_async(path, callback)
    git_cmd_async({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }, path, function(result, err)
        if err or not result or result == "" then
            callback(nil, err or "No upstream tracking branch")
        else
            callback(result:gsub("\n+$", ""), nil)
        end
    end)
end

-- Async version: Get remote HEAD commit hash
-- If configured_branch is provided, use that branch for comparison
local function get_remote_head_async(path, callback, configured_branch) -- Entry point for Branch/version-configured remote
    -- If a specific branch/version was configured, use it directly
    if configured_branch then
        local remote_ref = "origin/" .. configured_branch
        git_cmd_async({ "rev-parse", "--short", remote_ref }, path, function(result, err)
            if result and result ~= "" then
                callback(result:gsub("\n+$", ""), nil)
            else
                -- Fallback to trying the configured branch name as a tag
                git_cmd_async({ "rev-parse", "--short", configured_branch }, path, function(tag_result, tag_err)
                    if tag_result and tag_result ~= "" then
                        callback(tag_result:gsub("\n+$", ""), nil)
                    else
                        callback(nil, err or "Could not find configured branch/tag: " .. configured_branch)
                    end
                end)
            end
        end)
        return
    end

    -- First try to get the upstream tracking branch (most reliable)
    get_upstream_ref_async(path, function(upstream_ref, err)
        if upstream_ref then
            -- Got upstream ref, get its HEAD
            git_cmd_async({ "rev-parse", "--short", upstream_ref }, path, callback)
        else
            -- Fallback: try to get the default branch
            get_default_branch_async(path, function(default_branch, default_err)
                if default_branch then
                    -- Got default branch, get its HEAD
                    git_cmd_async({ "rev-parse", "--short", default_branch }, path, callback)
                else
                    -- Fallback: try common branch names
                    local function try_branch(branches, index)
                        if index > #branches then
                            callback(nil, "Could not determine default branch")
                            return
                        end

                        git_cmd_async({ "rev-parse", "--short", branches[index] }, path, function(result, branch_err)
                            if result and result ~= "" then
                                callback(result:gsub("\n+$", ""), nil)
                            else
                                try_branch(branches, index + 1)
                            end
                        end)
                    end

                    try_branch({ "origin/main", "origin/master" }, 1)
                end
            end)
        end
    end)
end

-- Fetch updates from remote for a package
local fetch_remote_async = function(path, callback)
    git_cmd_async({ "fetch" }, path, function(result, err)
        if err then
            callback(false, err)
        else
            callback(true, nil)
        end
    end)
end

-- Check for updates on all installed packages (fetches from remote first, then compares local vs remote HEAD)
M.check_updates = function(callback)
    local packages = vim.pack.get()
    local updates_available = {}
    local total = #packages
    local fetch_completed = 0
    local check_completed = 0

    if total == 0 then
        callback({})
        return
    end

    vim.notify(string.format("Fetching updates... (0/%d)", total), vim.log.levels.INFO)

    -- First, fetch all remotes
    for _, pkg in ipairs(packages) do
        fetch_remote_async(pkg.path, function(success, fetch_err)
            if fetch_err then
                vim.notify("Error fetching " .. pkg.spec.name .. ": " .. fetch_err, vim.log.levels.WARN)
            end

            fetch_completed = fetch_completed + 1

            vim.notify(
                string.format("Fetching updates... (%d/%d)", fetch_completed, total),
                vim.log.levels.INFO
            )

            if fetch_completed == total then
                -- After all fetches complete, check for updates
                vim.notify(string.format("Checking for updates... (0/%d)", total), vim.log.levels.INFO)

                for _, pkg in ipairs(packages) do
                    get_local_head_async(pkg.path, function(local_head, local_err)
                        if local_err then
                            vim.notify("Error checking " .. pkg.spec.name .. ": " .. local_err, vim.log.levels.WARN)
                            check_completed = check_completed + 1
                            if check_completed == total then
                                callback(updates_available)
                            end
                            return
                        end

                        -- Look up the configured version/branch for this plugin
                        local configured_version = M.plugin_versions[pkg.spec.name]

                        get_remote_head_async(pkg.path, function(remote_head, remote_err) -- Use branch if defined
                            if remote_err then
                                vim.notify("Error checking " .. pkg.spec.name .. ": " .. remote_err, vim.log.levels.WARN)
                            elseif local_head ~= remote_head then
                                table.insert(updates_available, {
                                    name = pkg.spec.name,
                                    src = pkg.spec.src,
                                    path = pkg.path,
                                    local_rev = local_head,
                                    remote_rev = remote_head,
                                })
                            end

                            check_completed = check_completed + 1

                            vim.notify(
                                string.format("Checking for updates... (%d/%d)", check_completed, total),
                                vim.log.levels.INFO
                            )

                            if check_completed == total then
                                callback(updates_available)
                            end
                        end, configured_version)
                    end)
                end
            end
        end)
    end
end

-- Show telescope picker for package updates
M.show_update_picker = function(updates)
    local ok, _ = pcall(require, "telescope")
    if not ok then
        vim.notify("Telescope is required for :PackUpdate", vim.log.levels.ERROR)
        return
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    -- Prepend "Update All" option
    local entries = { { name = ">> Update All <<", is_update_all = true } }
    for _, update in ipairs(updates) do
        table.insert(entries, update)
    end

    -- Use vim.schedule to ensure picker opens in a clean context
    vim.schedule(function()
        pickers
            .new({
                sorting_strategy = "ascending",
                layout_strategy = "vertical",
                layout_config = {
                    height = 0.9,
                    width = 0.8,
                    preview_cutoff = 20,
                },
            }, {
                prompt_title = "Package Updates Available",
                finder = finders.new_table({
                    results = entries,
                    entry_maker = function(entry)
                        if entry.is_update_all then
                            return {
                                value = entry,
                                display = entry.name,
                                ordinal = entry.name,
                            }
                        end
                        return {
                            value = entry,
                            display = string.format("%s (%s -> %s)", entry.name, entry.local_rev, entry.remote_rev),
                            ordinal = entry.name,
                        }
                    end,
                }),
                sorter = conf.generic_sorter({}),
                attach_mappings = function(prompt_bufnr, map)
                    -- Helper to process multi-selection
                    local function handle_multi_selection()
                        local picker = action_state.get_current_picker(prompt_bufnr)
                        local multi_selections = picker:get_multi_selection()

                        if #multi_selections > 0 then
                            local names = {}
                            local has_update_all = false
                            for _, sel in ipairs(multi_selections) do
                                if sel.value.is_update_all then
                                    has_update_all = true
                                    break
                                end
                                table.insert(names, sel.value.name)
                            end

                            if has_update_all then
                                names = {}
                                for _, update in ipairs(updates) do
                                    table.insert(names, update.name)
                                end
                            end

                            actions.close(prompt_bufnr)
                            M._do_update(names)
                            return true
                        end
                        return false
                    end

                    -- Handle single selection (Enter)
                    actions.select_default:replace(function()
                        local selection = action_state.get_selected_entry()
                        if not selection then
                            actions.close(prompt_bufnr)
                            return
                        end

                        actions.close(prompt_bufnr)

                        if selection.value.is_update_all then
                            local names = {}
                            for _, update in ipairs(updates) do
                                table.insert(names, update.name)
                            end
                            M._do_update(names)
                        else
                            M._do_update({ selection.value.name })
                        end
                    end)

                    -- Handle multi-selection (Tab to select, Enter to confirm)
                    map("i", "<Tab>", actions.toggle_selection + actions.move_selection_worse)
                    map("n", "<Tab>", actions.toggle_selection + actions.move_selection_worse)

                    -- Handle confirming multi-selection
                    map("i", "<C-q>", handle_multi_selection)
                    map("n", "<C-q>", handle_multi_selection)

                    return true
                end,
            })
            :find()
    end)
end

-- Perform the actual update
M._do_update = function(names)
    if #names == 0 then
        return
    end

    vim.notify("Updating " .. #names .. " package(s)...", vim.log.levels.INFO)
    vim.pack.update(names)
end

-- Main update command
M.update = function()
    M.check_updates(function(updates)
        if #updates == 0 then
            vim.notify("All packages are up to date!", vim.log.levels.INFO)
            return
        end

        vim.notify("Found " .. #updates .. " package(s) with updates", vim.log.levels.INFO)
        M.show_update_picker(updates)
    end)
end

-- Register commands on module load
vim.api.nvim_create_user_command("PackUpdate", function()
    M.update()
end, { desc = "Check and update packages via telescope picker" })

return M;
