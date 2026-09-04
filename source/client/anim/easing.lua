-- anim/easing.lua — функции облегчения (единый клок из core/time)

local easing = {}

function easing.linear(t) return t end

function easing.inQuad(t) return t * t end

function easing.outQuad(t) return t * (2 - t) end

function easing.inOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return -2 * t * t + 4 * t - 1
end

function easing.inCubic(t) return t * t * t end

function easing.outCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

function easing.outBack(t)
    local c = 1.70158
    local u = t - 1
    return 1 + (c + 1) * u * u * u + c * u * u
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.easing = easing
return easing
