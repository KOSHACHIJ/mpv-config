-- betterchapters2 ( refactor with ChatGPT )
-- Chapter navigation with circular playlist navigation.
-- Recommended with autoload.lua.
--
-- ] = next chapter / next playlist entry
-- [ = previous chapter / previous playlist entry


-- betterchapters.lua
-- Chapter navigation with explicit circular playlist navigation.
-- loop-playlist does not control boundary navigation.
--
-- ] = next chapter / next playlist entry
-- [ = previous chapter / previous playlist entry
-- Recommended with autoload.lua

local function chapter_seek(direction)
    local chapters = mp.get_property_number("chapters", 0)
    local chapter = mp.get_property_number("chapter", -1)

    -- Before the first chapter, ] selects the first chapter.
    if chapters > 0 and chapter < 0 and direction > 0 then
        mp.commandv("set", "chapter", 0)
        mp.commandv("script-message", "osc-chapterlist")
        return
    end

    -- Navigate within the current file if another chapter exists.
    if chapters > 0 and chapter >= 0 then
        local target_chapter = chapter + direction
        if target_chapter >= 0 and target_chapter < chapters then
            mp.commandv("add", "chapter", direction)
            mp.commandv("script-message", "osc-chapterlist")
            return
        end
    end

    -- Chapter boundary, or no chapters: wrap the playlist explicitly.
    local pos = mp.get_property_number("playlist-pos", -1)
    local count = mp.get_property_number("playlist-count", 0)

    if count < 2 or pos < 0 or pos >= count then
        mp.msg.warn(string.format(
            "betterchapters: invalid playlist position=%d count=%d",
            pos, count
        ))
        return
    end

    local target = (pos + direction) % count

    mp.msg.info(string.format(
        "betterchapters: playlist %d -> %d (count=%d)",
        pos, target, count
    ))

    mp.commandv("playlist-play-index", target)
    mp.commandv("script-message", "osc-playlist")
end

mp.add_key_binding("]", "chapter_next", function()
    chapter_seek(1)
end)

mp.add_key_binding("[", "chapter_prev", function()
    chapter_seek(-1)
end)
