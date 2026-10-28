
-- betterchapters2.lua
-- Chapter navigation with circular playlist navigation.
--
-- ] = next chapter / next playlist entry
-- [ = previous chapter / previous playlist entry
--
-- No text OSD notifications.
-- uosc timeline flashes on chapter/file changes.
-- Directories are excluded by autoload.conf (directory_mode=ignore).

local pending_entry_id = nil

local function flash_timeline()
    mp.commandv("script-message-to", "uosc", "flash-elements", "timeline")
end

local function playlist_entry_id(index)
    local playlist = mp.get_property_native("playlist", {})
    local entry = playlist[index + 1]
    return entry and entry.id
end

local function chapter_seek(direction)
    -- 1. Navigate chapters in the current file.
    local count = mp.get_property_number("chapters", 0)

    if count > 0 then
        local chapter = mp.get_property_number("chapter", -1)

        -- Playback is before the first chapter.
        if chapter < 0 and direction > 0 then
            mp.set_property_number("chapter", 0)
            flash_timeline()
            return
        end

        if chapter >= 0 then
            local target = chapter + direction

            if target >= 0 and target < count then
                mp.set_property_number("chapter", target)
                flash_timeline()
                return
            end
        end
    end

    -- 2. At a chapter boundary (or no chapters), move through
    --    the playlist, wrapping around independently of loop-playlist.
    local pos = mp.get_property_number("playlist-pos", -1)
    local total = mp.get_property_number("playlist-count", 0)

    if total < 2 or pos < 0 or pos >= total then
        return
    end

    for step = 1, total - 1 do
        local target = (pos + direction * step) % total
        local id = playlist_entry_id(target)

        if id ~= nil then
            pending_entry_id = id
            mp.commandv("playlist-play-index", target)
            return
        end
    end
end

-- Flash only when the requested playlist entry has loaded.
mp.register_event("file-loaded", function()
    if pending_entry_id == nil then
        return
    end

    local pos = mp.get_property_number("playlist-pos", -1)
    local id = pos >= 0 and playlist_entry_id(pos) or nil

    if id == pending_entry_id then
        pending_entry_id = nil
        flash_timeline()
    end
end)

-- Clear the pending request if its target fails to load.
mp.register_event("end-file", function(event)
    if pending_entry_id ~= nil
        and event
        and event.playlist_entry_id == pending_entry_id then
        pending_entry_id = nil
    end
end)

mp.add_key_binding("]", "chapter_next", function()
    chapter_seek(1)
end)

mp.add_key_binding("[", "chapter_prev", function()
    chapter_seek(-1)
end)
