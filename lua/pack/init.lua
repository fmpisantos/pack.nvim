local M = {}
M.srcs = {}
M.alreadySetup = {}
M.installed = {}
M.setupFunctions = {}

M.src = function(src)
    M.srcs[#M.srcs + 1] = src
end

M.require = function(path)
    local config_path = vim.fn.stdpath("config") .. "/lua/" .. path:gsub("%.", "/")

    local is_file = vim.fn.filereadable(config_path .. ".lua") == 1
    local is_dir = vim.fn.isdirectory(config_path) == 1

    if is_file then
        local ok, mod = pcall(require, path)
        if ok and type(mod) == "table" and mod.src then
            M.src(mod)
        end
    elseif is_dir then
        for _, file in ipairs(vim.fn.readdir(config_path, [[v:val =~ '\.lua$']])) do
            local mod_name = file:gsub("%.lua$", "")
            local full_mod_name = path .. "." .. mod_name

            local ok, mod = pcall(require, full_mod_name)
            if ok and type(mod) == "table" and mod.src then
                M.src(mod)
            end
        end
    else
        vim.notify("Path " .. config_path .. " is neither a file nor a directory", vim.log.levels.ERROR)
    end
end

local setup = function(setup, name, origin)
    if M.installed[name] ~= true then
        print(name .. " was not installed.")
        return false
    end
    origin[name] = true
    if type(setup.setup) == "function" then
        if setup.deps ~= nil then
            for _, dep in ipairs(setup.deps) do
                if M.alreadySetup[dep] ~= true then
                    if origin[dep] == true then
                        vim.notify("Loop dependency list for " .. name .. "(" .. dep .. ")")
                        return false
                    end
                    if setup(M.setupFunctions[dep], dep, origin) == false then
                        return false
                    end
                end
            end
        end
        if M.alreadySetup[name] ~= true then
            setup.setup()
            M.alreadySetup[name] = true
        end
    end
end


M.install = function()
    local function starts_with(str, prefix)
        return str:sub(1, #prefix) == prefix
    end

    local function normalize_url(src)
        if type(src) == "string" then
            if starts_with(src, "https://") then
                return src
            else
                return "https://github.com/" .. src
            end
        end
        return src
    end

    local function get_name_from_url(str)
        return str:gsub("https://.-/", "")
    end

    local function remove_prefix(str, prefix)
        if str:sub(1, #prefix) == prefix then
            return str:sub(#prefix + 1)
        else
            return str
        end
    end

    local function extract_plugins(src)
        local plugins = {}

        if type(src) == "string" then
            plugins[#plugins + 1] = normalize_url(src)
        elseif type(src) == "table" then
            if src.src then
                local plugin_spec = {
                    src = normalize_url(src.src)
                }
                for key, value in pairs(src) do
                    if key ~= "src" then
                        plugin_spec[key] = value
                    end
                end
                plugins[#plugins + 1] = plugin_spec
            else
                for _, item in ipairs(src) do
                    if type(item) == "string" then
                        plugins[#plugins + 1] = normalize_url(item)
                    elseif type(item) == "table" and item.src then
                        local plugin_spec = {
                            src = normalize_url(item.src)
                        }
                        for key, value in pairs(item) do
                            if key ~= "src" then
                                plugin_spec[key] = value
                            end
                        end
                        plugins[#plugins + 1] = plugin_spec
                    elseif type(item) == "table" then
                        local nested_plugins = extract_plugins(item)
                        for _, nested_plugin in ipairs(nested_plugins) do
                            plugins[#plugins + 1] = nested_plugin
                        end
                    end
                end
            end
        end

        return plugins
    end

    local allPlugins = {}
    local nSetupFunctions = 0

    local extract_key = function(extracted)
        local key = extracted.src
        if key == nil then
            key = extracted[1].src
            if key == nil then
                key = extracted[1]
            end
        end
        return get_name_from_url(key)
    end

    for _, plugin in ipairs(M.srcs) do
        local extracted = extract_plugins(plugin.src)

        if plugin.setup then
            local _setup = { setup = plugin.setup }
            if plugin.deps then
                local extracted_deps = extract_plugins(plugin.deps)
                local deps = {}
                for _, dep in ipairs(extracted_deps) do
                    allPlugins[#allPlugins + 1] = dep
                    deps[#deps] = extract_key(dep)
                end
                _setup["deps"] = deps
            end
            nSetupFunctions = nSetupFunctions + 1
            M.setupFunctions[extract_key(extracted)] = _setup
        end

        for _, extracted_plugin in ipairs(extracted) do
            allPlugins[#allPlugins + 1] = extracted_plugin
        end
    end

    vim.pack.add(allPlugins)

    local _installed = vim.pack.get()
    for _, pack in ipairs(_installed) do
        M.installed[extract_key(pack.spec)] = true
    end

    for key, value in pairs(M.setupFunctions) do
        setup(value, key, {})
    end

    -- local insertions = 1
    --
    -- repeat
    --     if #alreadySetup == nSetupFunctions then
    --         return
    --     else
    --         insertions = 0
    --     end
    --     for key, setup in ipairs(setupFunctions) do
    --         local continue = false
    --         if type(setup.setup) == "function" then
    --             if setup.deps ~= nil then
    --                 for _, dep in ipairs(setup.deps) do
    --                     if continue == true then
    --                         if alreadySetup[dep] ~= true then
    --                             continue = true
    --                         end
    --                     end
    --                 end
    --             end
    --             if continue == false then
    --                 vim.print(key)
    --                 setup.setup()
    --                 alreadySetup[key] = true
    --                 insertions = insertions + 1
    --             end
    --         end
    --     end
    -- until insertions == 0
end

return M
