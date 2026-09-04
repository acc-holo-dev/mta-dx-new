-- registry/base.lua — базовый виджет: свойства геометрии + проекция в lay
--
-- Базовая схема (x/y/width/height/visible) есть у всех виджетов; запись
-- геометрии зеркалируется в node._.lay — раскладка (layout/) читает только lay.

local DXUI = _G.DXUI

local base = {}

-- базовая схема геометрии: у каждого виджета, расширяется спецификацией
function base.schema()
    local prop = DXUI.prop
    local DIRTY = prop.DIRTY
    return {
        x = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Позиция X относительно родителя",
        },
        y = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Позиция Y относительно родителя",
        },
        width = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Ширина виджета в пикселях",
        },
        height = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Высота виджета в пикселях",
        },
        visible = {
            type = "boolean", default = true, invalidates = { DIRTY.RENDER },
            doc = "Видимость виджета",
        },
    }
end

-- словарь свойств -> поле lay для зеркалирования
function base.layMirror()
    return {
        x = "x",
        y = "y",
        width = "w",
        height = "h",
    }
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.base = base
return base
