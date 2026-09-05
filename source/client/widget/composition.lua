-- widget/composition.lua — слоты виджетов (task2.md T20)
--
-- Спека может объявить slots = { icon = true, trailing = true } — именованные
-- зоны для детей. Слот — это МЕТКА на ребёнке (inod.slot), а не геометрия:
-- виджет-хозяин сам решает, где рисовать каждый слот (читая детей по
-- childBySlot в render). composes = { "Label", "Icon" } — декларация,
-- из каких виджетов собрана спека (документация для treeShake, T19).

local composition = {}

-- прикрепить child к widget и пометить слотом; вернуть child
function composition.setSlot(widget, name, child)
    widget:addChild(child)
    rawget(child, "_").slot = name
    return child
end

-- первый ребёнок с таким слотом (nil — нет)
function composition.childBySlot(widget, name)
    local children = rawget(widget, "_").children
    for i = 1, #children do
        local c = children[i]
        if c and rawget(c, "_").slot == name then
            return c
        end
    end
    return nil
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.composition = composition
return composition
