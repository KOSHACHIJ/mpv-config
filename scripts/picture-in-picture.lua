-- Put MPV in picture-in-picture mode
local opt = require "mp.options"

local states = {
    windowed = "windowed",
    picture_in_picture = "picture-in-picture",
    fullscreen = "fullscreen"
}

-- x/y percentages (for use in a geometry string's position component) for
-- each supported options.position value.
local positions = {
    ["top-left"] = { x = 0, y = 0 },
    ["top-right"] = { x = 100, y = 0 },
    ["bottom-left"] = { x = 0, y = 100 },
    ["bottom-right"] = { x = 100, y = 100 },
    ["left-center"] = { x = 0, y = 50 },
    ["right-center"] = { x = 100, y = 50 },
    ["top-center"] = { x = 50, y = 0 },
    ["bottom-center"] = { x = 50, y = 100 },
    ["center"] = { x = 50, y = 50 }
}

local current_state = states.windowed
local previous_state = nil
local previous_geometry = nil

-- Set right before this script changes the "fullscreen" property itself, so
-- the observer below can tell its own writes apart from the user (or the
-- OSC, or another script) toggling fullscreen directly, and only react to
-- the latter. Without this, toggle_pip()'s own fullscreen on/off calls would
-- re-run the observer's state machine on top of toggle_pip()'s own -
-- two independent authorities racing over the same state.
local suppress_fullscreen_observer = false

local messages = {
    windowed = "Windowed mode activated",
    picture_in_picture = "Picture-in-Picture mode activated",
    fullscreen = "Fullscreen mode activated"
}
local options = {
    resolution = "854x480",
    position = "bottom-right"
}

opt.read_options(options, "picture-in-picture")

-- Forward-declared so toggle_pip (defined first, since it's the entry
-- point) can reference the functions defined further down.
local toggle_pip, resolve_position, apply_geometry, save_geometry, restore_geometry, transition_state, set_fullscreen_silently

function toggle_pip()
    if current_state == states.windowed or current_state == states.fullscreen then
        mp.osd_message(messages.picture_in_picture, 2)

        -- Store the current geometry - unconditionally, since PIP can be
        -- entered from fullscreen too (osd-width/osd-height still reflect
        -- the real pre-fullscreen pixel size while fullscreen, so this is
        -- always safe).
        save_geometry()

        mp.set_property("ontop", "yes")
        set_fullscreen_silently(false)

        -- Resize and move the window to the configured PIP size/corner
        apply_geometry(options.resolution, resolve_position(options.position))

        transition_state(states.picture_in_picture)
    else
        restore_geometry()

        mp.osd_message(messages.windowed, 2)
        transition_state(states.windowed)
    end
end

-- Looks up the x/y percentages for a configured position name, falling back
-- to bottom-right (with a warning) for an unrecognized one.
function resolve_position(name)
    local pos = positions[name]

    if not pos then
        mp.osd_message("Invalid position option. Defaulting to bottom-right.", 2)
        pos = positions["bottom-right"]
    end

    return pos
end

-- Builds and applies a "WxH+X%+Y%" geometry string. This is the one
-- property mpv documents as reliably live-adjustable at runtime (unlike
-- "autofit", which only affects initial window sizing) - see save_geometry
-- for why "geometry" itself isn't read back for restoring later.
function apply_geometry(size, pos)
    mp.set_property("geometry", string.format("%s+%d%%+%d%%", size, pos.x, pos.y))
end

function save_geometry()
    -- osd-width/osd-height reflect the window's real, live pixel size.
    -- Deliberately NOT using mp.get_property("geometry")/("autofit") here:
    -- both are write-mostly - reading them back just echoes whatever string
    -- was last explicitly set into them (empty, since this config never
    -- sets either), not the window's actual current size/position. mpv also
    -- has no property exposing the window's live on-screen X/Y position at
    -- all (checked against `mpv --list-properties`), so position can't be
    -- captured/restored the same way - see restore_geometry.
    previous_geometry = {
        w = mp.get_property_number("osd-width"),
        h = mp.get_property_number("osd-height"),
        ontop = mp.get_property("ontop")
    }
end

function restore_geometry()
    if previous_geometry then
        mp.set_property("ontop", previous_geometry.ontop)

        if previous_geometry.w and previous_geometry.h then
            -- Restore the real captured size. Position can't be restored to
            -- where it originally was - mpv exposes no way to read a
            -- window's live position back - so re-center instead, same
            -- fallback mpv.conf.original's own "#geometry=50%:50%" example
            -- uses for this exact situation.
            apply_geometry(string.format("%dx%d", previous_geometry.w, previous_geometry.h), positions["center"])
        end
    end

    -- PIP always exits back to windowed - not whatever state (windowed or
    -- fullscreen) it was entered from - matching the "Windowed mode
    -- activated" message toggle_pip() shows right after calling this.
    set_fullscreen_silently(false)
end

function transition_state(target_state)
    previous_state = current_state
    current_state = target_state
end

-- Sets "fullscreen" without letting the observer below treat it as an
-- external toggle. Only actually touches the property (and the suppress
-- flag) when the value is really changing - mpv doesn't fire property
-- observers on a same-value set, so arming the flag unconditionally could
-- leave it stuck "on" and cause the next real external toggle to be
-- ignored.
function set_fullscreen_silently(value)
    local target = value and "yes" or "no"
    if mp.get_property("fullscreen") == target then
        return
    end

    suppress_fullscreen_observer = true
    mp.set_property("fullscreen", target)
end

-- Transition states when the user (or the OSC, or another script) toggles
-- fullscreen directly, independent of the i/toggle_pip binding above.
mp.observe_property("fullscreen", "bool", function(name, value)
    if suppress_fullscreen_observer then
        suppress_fullscreen_observer = false
        return
    end

    if value then
        mp.osd_message(messages.fullscreen, 2)
        mp.set_property("ontop", "no")
        transition_state(states.fullscreen)
    elseif previous_state == states.windowed then
        mp.osd_message(messages.windowed, 2)
        transition_state(states.windowed)
    elseif previous_state == states.picture_in_picture then
        mp.osd_message(messages.picture_in_picture, 2)
        mp.set_property("ontop", "yes")
        transition_state(states.picture_in_picture)
    end

    if previous_geometry == nil then
        save_geometry()
    end
end)

-- Activate PIP when pressing i
mp.add_key_binding("i", "toggle_pip", toggle_pip)
