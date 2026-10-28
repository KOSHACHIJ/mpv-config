-- gamma-auto.lua
-- Ambient-light gamma adjustment for SDR (gamma-factor 1.0 .. 1.2).
-- HDR PQ/HLG content always gets gamma-factor 1.0.
-- Does nothing until both the ambient light and the video transfer
-- function are known, so it never touches gamma-factor on machines
-- without a light sensor and never flashes SDR gamma on HDR video.

local LUX_MIN, LUX_MAX = 16, 256
local GAMMA_MIN, GAMMA_MAX = 1.0, 1.2

local LOG_MIN = math.log(LUX_MIN, 10)
local LOG_RANGE = math.log(LUX_MAX, 10) - LOG_MIN

local ambient_lux
local transfer

local function lux_to_gamma(lux)
    if lux <= LUX_MIN then
        return GAMMA_MIN
    end
    if lux >= LUX_MAX then
        return GAMMA_MAX
    end
    local t = (math.log(lux, 10) - LOG_MIN) / LOG_RANGE
    return GAMMA_MIN + (GAMMA_MAX - GAMMA_MIN) * t
end

local function update_gamma()
    if not ambient_lux or not transfer then
        return
    end

    local gamma = (transfer == "pq" or transfer == "hlg")
        and 1.0
        or lux_to_gamma(ambient_lux)

    if math.abs(mp.get_property_number("gamma-factor", 1.0) - gamma) > 0.001 then
        mp.set_property_number("gamma-factor", gamma)
    end
end

mp.observe_property("ambient-light", "number", function(_, value)
    ambient_lux = value
    update_gamma()
end)

mp.observe_property("video-params/gamma", "string", function(_, value)
    transfer = value
    update_gamma()
end)
