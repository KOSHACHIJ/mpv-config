--[[
    fuzzydir-filtered.lua
    Based on fuzzydir.lua by sibwaf:
    https://github.com/sibwaf/mpv-scripts

    Expands "**" in sub-file-paths and audio-file-paths, but only with
    directories whose names match a configurable list of substrings
    (case-insensitive):
      subtitles: "sub"            e.g. "UA subs", "EN Sub", "Subtitles"
      audio:     "sound", "audio" e.g. "UA Sound", "EN audio"

    A matching directory and its descendants are included, so files may be
    nested inside it. Other directories are scanned (up to a limit) to find
    matching directories deeper in the tree.

    The scan is bounded (depth, number of directories read, number of
    resulting paths) so it can never stall file loading, and it is cached per
    video directory.

    Options (script-opts/fuzzydir-filtered.conf):
      enabled=yes
      sub_patterns=sub
      audio_patterns=sound,audio
      max_search_depth=3        levels scanned while looking for matches
      max_match_depth=4         levels followed inside a matching directory
      max_scanned_dirs=300      hard cap on directory reads per scan
      max_paths=200             cap on found paths per kind
      discovery_threshold=50    do not descend into non-matching directories
                                of a directory with more subdirectories than
                                this (0 = no limit); matches in that directory
                                are still found

    MIT license follows the original script's license.
]]

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

local o = {
    enabled = true,
    sub_patterns = "sub",
    audio_patterns = "sound,audio",
    max_search_depth = 3,
    max_match_depth = 4,
    max_scanned_dirs = 300,
    max_paths = 200,
    discovery_threshold = 50,
}
options.read_options(o, "fuzzydir-filtered")

local function parse_patterns(list)
    local patterns = {}
    for item in string.gmatch(list, "[^,]+") do
        item = string.lower(item:match("^%s*(.-)%s*$"))
        if item ~= "" then
            patterns[#patterns + 1] = item
        end
    end
    return patterns
end

local sub_patterns = parse_patterns(o.sub_patterns)
local audio_patterns = parse_patterns(o.audio_patterns)

local default_sub_paths = mp.get_property_native("options/sub-file-paths") or {}
local default_audio_paths = mp.get_property_native("options/audio-file-paths") or {}

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

local function matches(name, patterns)
    local lower = string.lower(name)
    for _, pattern in ipairs(patterns) do
        if string.find(lower, pattern, 1, true) then
            return true
        end
    end
    return false
end

-- Breadth-first scan. Returns a list of paths relative to search_path.
-- mdepth is nil outside a matching directory; 0 for a matching directory
-- itself and +1 for each level below it.
local function scan(search_path, start_rel, patterns, label)
    local found = {}
    local queue = { { rel = start_rel, level = 1, mdepth = nil } }
    local head = 1
    local budget = o.max_scanned_dirs

    while head <= #queue do
        if budget <= 0 then
            msg.warn(("fuzzydir-filtered: %s scan stopped, max_scanned_dirs=%d reached")
                :format(label, o.max_scanned_dirs))
            break
        end
        if #found >= o.max_paths then
            msg.warn(("fuzzydir-filtered: %s scan stopped, max_paths=%d reached")
                :format(label, o.max_paths))
            break
        end

        local item = queue[head]
        head = head + 1
        budget = budget - 1

        local dirs = utils.readdir(utils.join_path(search_path, item.rel), "dirs")
        if dirs then
            table.sort(dirs)
            local too_many = o.discovery_threshold > 0
                and #dirs > o.discovery_threshold

            for _, name in ipairs(dirs) do
                local rel = utils.join_path(item.rel, name)

                local mdepth
                if item.mdepth ~= nil then
                    mdepth = item.mdepth + 1
                elseif matches(name, patterns) then
                    mdepth = 0
                end

                if mdepth ~= nil then
                    if mdepth <= o.max_match_depth then
                        found[#found + 1] = rel
                        if mdepth < o.max_match_depth then
                            queue[#queue + 1] = { rel = rel, level = item.level + 1, mdepth = mdepth }
                        end
                    end
                elseif item.level < o.max_search_depth and not too_many then
                    queue[#queue + 1] = { rel = rel, level = item.level + 1, mdepth = nil }
                end
            end
        end
    end

    msg.debug(("fuzzydir-filtered: %s: %d dirs read, %d paths found")
        :format(label, o.max_scanned_dirs - budget, #found))
    return found
end

local function expand_kind(raw_paths, search_path, patterns, label)
    local result, seen = {}, {}

    local function add(path)
        local p = normalize(path)
        if p ~= "" and not seen[p] then
            seen[p] = true
            result[#result + 1] = p
        end
    end

    for _, raw in ipairs(raw_paths) do
        local parent, leftover = utils.split_path(raw)
        if leftover == "**" then
            add(parent)
            for _, p in ipairs(scan(search_path, parent, patterns, label)) do
                add(p)
            end
        else
            add(raw)
        end
    end

    return result
end

-- Cache for the last scanned video directory, so a whole season in one
-- folder is scanned only once.
local cache = { dir = nil, sub = nil, audio = nil }

local function expand_all()
    if not o.enabled then
        return
    end

    local video_path = mp.get_property("path")
    -- Skip URLs and empty paths.
    if not video_path or video_path == ""
        or string.match(video_path, "^%a[%w+.-]*://") then
        return
    end

    local search_path = utils.split_path(video_path)
    if not search_path or search_path == "" then
        search_path = "."
    end

    if cache.dir ~= search_path then
        local started = mp.get_time()
        cache.sub = expand_kind(default_sub_paths, search_path, sub_patterns, "subtitles")
        cache.audio = expand_kind(default_audio_paths, search_path, audio_patterns, "audio")
        cache.dir = search_path
        msg.verbose(("fuzzydir-filtered: scanned %s in %.0f ms")
            :format(search_path, (mp.get_time() - started) * 1000))
    end

    msg.debug("fuzzydir-filtered: sub paths: " .. table.concat(cache.sub, ":"))
    msg.debug("fuzzydir-filtered: audio paths: " .. table.concat(cache.audio, ":"))

    mp.set_property_native("options/sub-file-paths", cache.sub)
    mp.set_property_native("options/audio-file-paths", cache.audio)
end

mp.add_hook("on_load", 50, expand_all)
