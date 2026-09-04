-- style/transitions.lua — переходы состояний (task.md §5)
--
-- Схема свойства может объявить переход:
--   x = { type = "number", ..., transition = { duration = 0.15, easing = "outQuad" } }
--
-- Запись node.x = v в этом случае не прыгает: prop.set ставит твин
-- (anim/tween), и интерполяция идёт через ту же систему свойств —
-- конвейер переиспользуется. Твин пишет через prop.forceSet (мимо
-- планирования), поэтому рекурсии нет.

local transitions = {}

-- валидация описателя перехода на этапе компиляции схемы
function transitions.validate(owner, key, spec)
    if spec.duration == nil then
        error(("transitions[%s.%s]: duration required"):format(owner, tostring(key)), 2)
    end
    return true
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.transitions = transitions
return transitions
