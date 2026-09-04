-- api/exports.lua — фасад import(2) (task.md §9.1, P2/P3)
--
-- Контракт:
--   local ui = loadstring(exports.dxui:import(2))()
--
-- Экспорт возвращает КОД-СТРОКУ один раз (P3: функции не сериализуются
-- через границу экспортов). Клиентские ресурсы MTA живут в одном Lua VM,
-- поэтому исполненная строка собирает фасад поверх _G.DXUI: потребитель
-- не получает ни одного внутреннего файла, только стабильную поверхность.
--
-- Стабильность: с G7 — 0 нарушающих изменений возвращаемой строки
-- (контрактный тест: test_api_debug.lua).

local registry = _G.DXUI.registry
local frame = _G.DXUI.frame

local VERSION = 2

local api = {}

local SCHEMA = [==[
local DXUI = _G.DXUI
local registry = DXUI.registry
local frame = DXUI.frame

local ui = { version = %d }

-- конструктор-фабрика: ui.Window { ... } — корень кадра
local function make(name)
    return function(props)
        props = props or {}
        local node = registry.create(name, props)
        frame.add(node)
        return node
    end
end

-- ребёнок: ui.Window { children = { ui.Button{...} } } — addChild
-- детьми прямо из конструктора (registry.create), в кадр добавлять нельзя.
local function child(name)
    return function(props)
        return registry.create(name, props or {})
    end
end

local function exportAll()
    local out = {}
    for _, name in ipairs(registry.names()) do
        out[name] = make(name)
    end
    return out
end

for name, factory in pairs(exportAll()) do
    ui[name] = factory
end

-- производные API поверх стабильной поверхности
ui.animation = DXUI.tween        -- to/timeline/after (единый клок)
ui.theme = DXUI.theme            -- apply/applyNamed/define
ui.registry = registry           -- advanced: define для новых виджетов

return ui
]==]

function api.import(version)
    if version ~= VERSION then
        error(("dxui: import(%s): поддерживается версия %d")
            :format(tostring(version), VERSION), 2)
    end
    return SCHEMA:format(VERSION)
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.api = api

-- экспортируемая из meta.xml функция ресурса
function import(version)
    return _G.DXUI.api.import(version)
end

return api
