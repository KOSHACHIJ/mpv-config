--[[
    fuzzydir-filtered.lua
    Based on fuzzydir.lua by sibwaf:
    https://github.com/sibwaf/mpv-scripts

    Expands ** in sub-file-paths and audio-file-paths, but only includes
    directories whose names indicate the relevant media type:
      subtitles: "sub" (case-insensitive)
      audio:     "sound" or "audio" (case-insensitive)

    When a matching directory is found, that directory and all its
    descendant directories are included, so files may be nested inside it.
    Other directories are still traversed to find matching directories
    deeper in the tree.

    MIT license follows the original script's license.
]]

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

local o = {
    enabled = true,
    max_search_depth = 3,
    -- 0 disables this limit and searches every directory encountered.
    discovery_threshold = 0,
}
options.read_options(o, "fuzzydir-filtered")

local default_audio_paths = mp.get_property_native("options/audio-file-paths") or {}
local default_sub_paths = mp.get_property_native("options/sub-file-paths") or {}

local function starts_with(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

local function ends_with(str, suffix)
    return suffix == "" or string.sub(str, -#suffix) == suffix
end

local function normalize(path)
    if path == "." then
        return ""
    end
    if starts_with(path, "./") or starts_with(path, ".\\") then
        path = string.sub(path, 3)
    end
    if ends_with(path, "/") or ends_with(path, "\\") then
        path = string.sub(path, 1, -2)
    end
    return path
end

local function contains(list, value)
    for _, element in ipairs(list) do
        if element == value then
            return true
        end
    end
    return false
end

local function add_all(to, from)
    for _, element in ipairs(from) do
        table.insert(to, element)
    end
end

local function directory_matches(name, kind)
    local lower = string.lower(name)
    if kind == "sub" then
        return string.find(lower, "sub", 1, true) ~= nil
    end
    return string.find(lower, "sound", 1, true) ~= nil
        or string.find(lower, "audio", 1, true) ~= nil
end

-- Traverse every directory to discover matching names. Once a matching
-- directory is entered, include all its descendants as well.
local function traverse(search_path, current_path, level, kind, inside_match, cache)
    -- Limit discovery depth in unrelated branches. Once a matching folder
    -- is entered, keep including its descendants even if they are nested
    -- deeper than max_search_depth.
    if level > o.max_search_depth and not inside_match then
        return {}
    end

    local cache_key = current_path .. "\0" .. kind .. "\0" .. tostring(inside_match)
    if cache[cache_key] ~= nil then
        return cache[cache_key]
    end

    local full_path = utils.join_path(search_path, current_path)
    local discovered = utils.readdir(full_path, "dirs")
    local result = {}

    if discovered == nil then
        msg.debug("fuzzydir-filtered: unable to scan " .. full_path)
        cache[cache_key] = result
        return result
    end

    if o.discovery_threshold > 0 and #discovered > o.discovery_threshold then
        msg.debug("fuzzydir-filtered: too many directories in " .. full_path
            .. " (" .. #discovered .. "), skipping")
        cache[cache_key] = result
        return result
    end

    for _, name in ipairs(discovered) do
        local new_path = utils.join_path(current_path, name)
        local matched = directory_matches(name, kind)
        local include = inside_match or matched

        if include then
            table.insert(result, new_path)
        end

        add_all(result, traverse(
            search_path,
            new_path,
            level + 1,
            kind,
            inside_match or matched,
            cache
        ))
    end

    cache[cache_key] = result
    return result
end

local function explode(raw_paths, search_path, kind, cache)
    local result = {}

    for _, raw_path in ipairs(raw_paths) do
        local parent, leftover = utils.split_path(raw_path)

        if leftover == "**" then
            -- Preserve an explicitly configured parent path, matching the
            -- behavior of the original fuzzydir.lua.
            if parent ~= "" then
                table.insert(result, parent)
            end

            add_all(result, traverse(search_path, parent, 1, kind, false, cache))
        else
            -- Paths without a trailing ** are left untouched.
            table.insert(result, raw_path)
        end
    end

    local normalized = {}
    for _, path in ipairs(result) do
        local normalized_path = normalize(path)
        if normalized_path ~= "" and not contains(normalized, normalized_path) then
            table.insert(normalized, normalized_path)
        end
    end

    return normalized
end

local function expand_all()
    if not o.enabled then
        return
    end

    local video_path = mp.get_property("path")
    if not video_path or video_path == "" then
        return
    end

    local search_path = utils.split_path(video_path)
    if not search_path or search_path == "" then
        search_path = "."
    end

    msg.debug("fuzzydir-filtered: search_path = " .. search_path)

    -- Separate caches because subtitle and audio directory matching differ.
    local sub_paths = explode(default_sub_paths, search_path, "sub", {})
    local audio_paths = explode(default_audio_paths, search_path, "audio", {})

    msg.debug("fuzzydir-filtered: subtitle search paths: " .. table.concat(sub_paths, ":"))
    msg.debug("fuzzydir-filtered: audio search paths: " .. table.concat(audio_paths, ":"))

    mp.set_property_native("options/sub-file-paths", sub_paths)
    mp.set_property_native("options/audio-file-paths", audio_paths)
end

mp.add_hook("on_load", 50, expand_all)
