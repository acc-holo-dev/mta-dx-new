-- api/exports.lua — фасад import(2) (task.md §9.1, P2/P3)
--
-- Контракт:
--   local ui = loadstring(exports.dxui:import(2))()
--
-- Клиентские ресурсы MTA живут в РАЗДЕЛЬНЫХ Lua VM, поэтому функции и
-- таблицы через границу экспортов не проходят (P3) — только код-строка.
-- import(2) возвращает код, который СОДЕРЖИТ ВЕСЬ фреймворк (bundle из
-- api/bundle.lua, генерируется `python dxui.py build`) + мост платформы +
-- фасад ui. Потребитель исполняет строку ОДИН РАЗ (повторное исполнение
-- в той же VM — ошибка схемы виджетов) и получает готовый API.
--
-- В кадре — ноль exports (P2): после исполнения все ссылки локальны.

local BUNDLE = _G.DXUIBundle

local VERSION = 2

if BUNDLE == nil then
    error("dxui: api/bundle.lua не сгенерирован — выполните `python dxui.py build`", 2)
end

local api = {}

-- Мост платформы + фасад. Исполняется в VM потребителя ПОСЛЕ bundle:
-- к этому моменту _G.DXUI собран полностью.
local GLUE = [==[
local DXUI = _G.DXUI
local registry = DXUI.registry
local frame = DXUI.frame

-- клок
DXUI.time.setSource(function()
    return getTickCount()
end)

-- мост ввода: очередь событий платформы
addEventHandler("onClientClick", root, function(button, state, x, y)
    DXUI.dispatcher.enqueue("click", button, state, x, y)
end)
addEventHandler("onClientCursorMove", function(_, _, x, y)
    DXUI.dispatcher.enqueue("move", x, y)
end)
addEventHandler("onClientKey", function(key, down)
    DXUI.dispatcher.enqueue("key", key, down)
end)
addEventHandler("onClientCharacter", root, function(ch)
    DXUI.dispatcher.enqueue("char", ch)
end)
addEventHandler("onClientMouseWheel", function(dx, dy)
    DXUI.dispatcher.enqueue("wheel", dx, dy)
end)

-- кадр потребителя: ввод → твины → раскладка → холст
local canvas = DXUI.canvas.new()
addEventHandler("onClientRender", root, function()
    DXUI.dispatcher.dispatch(frame.roots())
    DXUI.tween.tick()
    frame.run(canvas)
    canvas:drain(DXUI.backend_mta)
end)

-- фасад: ui.<Widget> { ... } — корень кадра
local ui = { version = 2 }

local function make(name)
    return function(props)
        props = props or {}
        local node = registry.create(name, props)
        frame.add(node)
        return node
    end
end

for _, name in ipairs(registry.names()) do
    ui[name] = make(name)
end

ui.animation = DXUI.tween
ui.theme = DXUI.theme
ui.registry = registry

return ui
]==]

function api.import(version)
    if version ~= VERSION then
        error(("dxui: import(%s): поддерживается версия %d")
            :format(tostring(version), VERSION), 2)
    end
    return BUNDLE .. "\n" .. GLUE
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.api = api

-- экспортируемая из meta.xml функция ресурса
function import(version)
    return _G.DXUI.api.import(version)
end

return api
