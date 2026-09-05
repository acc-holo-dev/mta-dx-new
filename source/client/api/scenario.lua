-- api/scenario.lua — сценарий экрана как данные (task.md §3.8)
--
-- spec — чистая таблица (переживает сериализацию, может прийти с сервера
-- событием):
--   { type = "Window",
--     props = { title = "Инвентарь", x = 100, width = 300 },
--     children = {
--       { type = "Button", props = { text = "OK", onPress = "close" } },
--     } }
--
-- scenario.build(spec) -> node — рекурсивная сборка через registry.create.
-- props.onPress бывает строкой-именем обработчика: handlers = { close = fn }
-- подставляется при сборке (функции через границу событий не ходят — имена да).
-- Дерево можно собрать и НЕ прикреплять к кадру — владение узлом у вызывающего.

local DXUI = _G.DXUI

local scenario = {}

local function buildNode(spec, handlers, path)
    if type(spec) ~= "table" then
        error(("dxui: scenario: узел '%s' — не таблица"):format(path), 3)
    end
    local wtype = spec.type
    if type(wtype) ~= "string" then
        error(("dxui: scenario: узлу '%s' нужен строковой type"):format(path), 3)
    end
    if DXUI.registry.get(wtype) == nil then
        error(("dxui: scenario: неизвестный виджет '%s' (узел '%s')")
            :format(wtype, path), 3)
    end
    local props = {}
    for k, v in pairs(spec.props or {}) do
        props[k] = v
    end
    -- строковый onPress — имя в handlers
    if type(props.onPress) == "string" then
        local fn = handlers and handlers[props.onPress]
        if type(fn) ~= "function" then
            error(("dxui: scenario: обработчик '%s' не найден (узел '%s')")
                :format(props.onPress, path), 3)
        end
        props.onPress = fn
    end
    local node = DXUI.registry.create(wtype, props)
    local children = spec.children
    if children then
        for i = 1, #children do
            node:addChild(buildNode(children[i], handlers, path .. "/" .. wtype .. "[" .. i .. "]"))
        end
    end
    return node
end

-- spec -> узел; handlers = { имя = fn } для строковых onPress (опционально)
function scenario.build(spec, handlers)
    return buildNode(spec, handlers, "root")
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.scenario = scenario
return scenario
