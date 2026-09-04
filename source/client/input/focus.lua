-- input/focus.lua — фокус и клавиатурная навигация (task.md §3.5)
--
-- Таблица решений:
--   * стрелки между элементами: обход по дереву раскладки, не по пикселям;
--   * Tab входит в редактирование, стрелка вправо — нет (иначе из поля не выйти);
--   * контейнер прокрутки в фокус-обходе пропускается;
--   * модальные окна: навигация заперта внутри верхней модали (ловушка);
--   * виртуализированный список: стрелка = следующая строка (dispatcher
--     подставляет строки как узлы через focus.addProxy).
--
-- Состояние editing: true, пока пользователь редактирует текст; в этом
-- режиме стрелки уходят в text/-ядро, а не в навигацию.

local rawget = rawget
local table_insert = table.insert

local focus = {}

local focused = nil
local editing = false
local modalStack = {}

-- rebuildable список фокусируемых узлов (лениво; инвалидация списком)
local listVersion = 0

local function markDirty()
    listVersion = listVersion + 1
end

-- ---------------------------------------------------------------- modal

-- ловушка: навигация и ввод заперты в поддереве node
function focus.pushModal(node)
    modalStack[#modalStack + 1] = node
    if focused ~= nil and not focus.isInsideModal(focused, node) then
        focused = nil
    end
    markDirty()
end

function focus.popModal()
    local node = table.remove(modalStack)
    if node then markDirty() end
    return node
end

function focus.getModal()
    return modalStack[#modalStack]
end

function focus.isInsideModal(node, modal)
    if modal == nil then return true end
    local cur = node
    while cur do
        if cur == modal then return true end
        cur = rawget(cur, "_").parent
    end
    return false
end

-- ---------------------------------------------------------------- состояние

function focus.get()
    return focused
end

-- вызывается без node при уничтожении узла
function focus.set(node)
    if focused == node then return end
    local prev = focused
    focused = node
    editing = false
    markDirty()
    if prev then prev:emit("blur") end
    if node then node:emit("focus") end
end

function focus.clear()
    focus.set(nil)
end

function focus.isEditing()
    return editing
end

-- Tab вошёл в поле / Tab вышел из поля (двигаемся дальше)
function focus.setEditing(on)
    editing = on == true
    return editing
end

-- узел способен к редактированию (Edit, Memo)
function focus.isEditable(node)
    local spec = rawget(node, "_renderSpec")
    return spec ~= nil and spec.editable == true
end

-- ---------------------------------------------------------------- обход

-- собирает все фокусируемые узлы: дерево раскладки, pre-order.
-- Контейнеры прокрутки сами не фокусируются (spec.focusable false).
-- roots — таблица корней (frame.roots()).
local function buildList(roots)
    local list = {}
    local modal = focus.getModal()
    local function walk(node, insideModal)
        if not insideModal and modal ~= nil then
            -- вне модали ничего не фокусируется
            return
        end
        local inod = rawget(node, "_")
        if inod == nil then return end
        if inod.data.visible == false then return end
        local spec = rawget(node, "_renderSpec")
        if spec and spec.focusable then
            list[#list + 1] = node
        end
        local children = inod.children
        for i = 1, #children do
            walk(children[i], insideModal)
        end
    end
    if modal == nil then
        for i = 1, #roots do
            walk(roots[i], true)
        end
    else
        walk(modal, true)
    end
    return list
end

-- dir: 1 = вперёд (Tab), -1 = назад (Shift+Tab)
-- возвращает новый сфокусированный узел (или nil)
function focus.navigate(roots, dir)
    local list = buildList(roots)
    local n = #list
    if n == 0 then
        focus.set(nil)
        return nil
    end
    if focused == nil then
        focus.set(list[1])
        return focused
    end
    local at = 0
    for i = 1, n do
        if list[i] == focused then
            at = i
            break
        end
    end
    local next
    if at == 0 then
        -- сфокусированный вне списка (модаль) — начинаем сначала
        next = list[1]
    else
        local idx = at + dir
        if idx > n then idx = 1 end
        if idx < 1 then idx = n end
        next = list[idx]
    end
    focus.set(next)
    return next
end

-- уничтожение узла: сбросить фокус, если он был здесь
function focus.onNodeDestroyed(node)
    if focused == node then
        focused = nil
        editing = false
    end
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.focus = focus
return focus
