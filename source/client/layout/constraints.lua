-- layout/constraints.lua — ограничения размеров
--
-- clamp(lay): возвращает w/h узла, зажатые min/max (и aspect, если задан).

local math = math
local type = type

local constraints = {}

function constraints.clamp(lay)
    local w = lay.w or 0
    local h = lay.h or 0

    if lay.minW then w = math.max(w, lay.minW) end
    if lay.maxW then w = math.min(w, lay.maxW) end
    if lay.minH then h = math.max(h, lay.minH) end
    if lay.maxH then h = math.min(h, lay.maxH) end

    if lay.aspect then
        -- сохранение пропорций: приоритет у главного измерения
        if lay.dir == "row" then
            h = w / lay.aspect
            if h > (lay.maxH or math.huge) then h = lay.maxH end
            if h < (lay.minH or 0) then h = lay.minH end
            w = h * lay.aspect
        else
            w = h * lay.aspect
            if w > (lay.maxW or math.huge) then w = lay.maxW end
            if w < (lay.minW or 0) then w = lay.minW end
            h = w / lay.aspect
        end
    end

    lay.w = w
    lay.h = h
    return w, h
end

-- публикация в глобальный namespace
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.constraints = constraints
return constraints
