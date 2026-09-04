-- layout/lay.lua — параметры раскладки узла
--
-- Раскладка оперяет интерфейсом: node.children (список) и node.lay (эта таблица).
-- G4 (widget/base) будет проектировать свои свойства в lay; виджеты-владельцы
-- живут своей жизнью, layout ни от кого кроме core не зависит.
--
-- Поля lay:
--   x, y, w, h      — геометрия (w/h — собственный размер; flex может менять)
--   dir             — "column" | "row" (направление главной оси)
--   gap             — интервал между детьми
--   align           — выравнивание по поперечной оси: "start"|"center"|"end"|"stretch"
--   grow, shrink    — доли в главном направлении
--   basis           — фиксированный размер в главном направлении (до grow)
--   padding         — {l, t, r, b} внутренние отступы контейнера
--   minW, maxW, minH, maxH — ограничения (constraints.lua)
--   anchor          — привязка к краям родителя { left|right|top|bottom = n, centerX, centerY }
--   scrollX, scrollY — смещение содержимого (ScrollPanel)
--   skipLayout      — true: ребёнок раскладкой не управляется (anchor/absolute)

local type = type
local pairs = pairs

local lay = {}

local DEFAULTS = {
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    dir = "column",
    gap = 0,
    align = "start",
    grow = 0,
    shrink = 1,
    minW = 0,
    minH = 0,
    maxW = math.huge,
    maxH = math.huge,
    scrollX = 0,
    scrollY = 0,
    skipLayout = false,
}

-- создать lay-таблицу поверх переопределений
function lay.new(opts)
    local t = {}
    for k, v in pairs(DEFAULTS) do
        t[k] = v
    end
    t.padding = nil
    t.anchor = nil
    t.basis = nil
    if opts then
        for k, v in pairs(opts) do
            t[k] = v
        end
    end
    -- padding приходит числом или списком — нормализуем один раз при создании
    if t.padding ~= nil then
        t.padding = lay.normalizePadding(t.padding)
    end
    return t
end

function lay.valid(l)
    if type(l) ~= "table" then
        error("lay: expected a lay table", 2)
    end
end

local PAD_KEYS = { "l", "t", "r", "b" }

-- нормализация padding: число | {10} | {10,20} | {10,20,30,40} | {l=,t=,r=,b=}
function lay.normalizePadding(p)
    if p == nil then
        return nil
    end
    if type(p) == "number" then
        return { l = p, t = p, r = p, b = p }
    end
    -- уже нормализованная форма
    if p.l ~= nil or p.t ~= nil or p.r ~= nil or p.b ~= nil then
        return {
            l = p.l or 0, t = p.t or 0, r = p.r or 0, b = p.b or 0,
        }
    end
    local out = { l = 0, t = 0, r = 0, b = 0 }
    local n = #p
    if n == 1 then
        out.l, out.t, out.r, out.b = p[1], p[1], p[1], p[1]
    elseif n == 2 then
        out.t, out.b, out.l, out.r = p[1], p[1], p[2], p[2]
    elseif n >= 4 then
        out.l, out.t, out.r, out.b = p[1], p[2], p[3], p[4]
    end
    return out
end

-- публикация в глобальный namespace
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.lay = lay
return lay
