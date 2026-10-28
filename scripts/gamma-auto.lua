
-- gamma-auto.lua
-- Ambient-light gamma adjustment for SDR.
-- Keep gamma-factor at 1.0 for HDR PQ/HLG content.

local function lux_to_gamma(lux)
    if not lux or lux <= 16 then
        return 1.0
    end

    if lux >= 256 then
        return 1.2
    end

    local t = (math.log(lux, 10) - math.log(16, 10)) /
              (math.log(256, 10) - math.log(16, 10))

    return 1.0 + 0.2 * t
end

local ambient_lux
local transfer

local function update_gamma()
    if transfer == "pq" or transfer == "hlg" then
        mp.set_property_number("gamma-factor", 1.0)
        return
    end

    mp.set_property_number("gamma-factor", lux_to_gamma(ambient_lux))
end

mp.observe_property("ambient-light", "number", function(_, value)
    ambient_lux = value
    update_gamma()
end)

mp.observe_property("video-params/gamma", "string", function(_, value)
    transfer = value
    update_gamma()
end)
