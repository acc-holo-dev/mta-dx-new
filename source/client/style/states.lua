-- style/states.lua — состояния виджета (task.md §5)
--
-- Цепочка состояний: base → hover → pressed → focused → disabled.
-- Значение свойства = первый найденный в цепочке приоритет (disabled
-- старше всех). Сами флаги состояний хранит виджет в свойствах
-- (hovered/pressed/focused/disabled — как в темах).

local states = {}

local CHAIN = { "disabled", "focused", "pressed", "hovered", "base" }

-- layered: { base = {...}, hover = {...}, ... }
-- state: { hovered = bool, pressed = bool, focused = bool, disabled = bool }
local function pick(layered, state, key)
    for i = 1, #CHAIN do
        local layer = layered[CHAIN[i]]
        if layer and layer[key] ~= nil then
            return layer[key]
        end
    end
    return nil
end

-- разрешить полный набор свойств по состоянию: { ключ = значение }
function states.resolve(layered, state)
    local out = {}
    -- базовые значения
    if layered.base then
        for k, v in pairs(layered.base) do
            out[k] = v
        end
    end
    -- наслоения по цепочке (disabled сильнее всех)
    for i = #CHAIN, 1, -1 do
        local name = CHAIN[i]
        if state[name] and layered[name] then
            local layer = layered[name]
            for k, v in pairs(layer) do
                out[k] = v
            end
        end
    end
    return out
end

states.pick = pick

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.states = states
return states
