-- style/theme.lua — темы поверх токенов (task.md §5)
--
-- Тема — таблица переопределений поверх токенов. Смена — батчевое
-- обновление: одна запись на ключ, без аллокаций на виджет (300 виджетов
-- ≤ 5 мс по бюджету §6.2).
--
-- Дефолты схем виджетов, аннотированные token = "<имя>", обновляются
-- вместе с палитрой: явная установка свойства пользователем не страдает.

local pairs = pairs
local ipairs = ipairs
local rawget = rawget

local theme = {}

local themes = {}   -- name -> overrides

-- callback смены темы (инспектор/anim слушают)
theme.onChanged = nil

function theme.define(name, overrides)
    themes[name] = overrides
    return overrides
end

function theme.get(name)
    return themes[name]
end

-- батчевое применение: мутирует палитру и дефолты аннотированных схем
function theme.apply(overrides)
    local DXUI = _G.DXUI
    local palette = DXUI.palette
    for k, v in pairs(overrides) do
        palette[k] = v
    end
    -- дефолты свойств, привязанные к токенам
    local registry = DXUI.registry
    for _, name in ipairs(registry.names()) do
        local cls = registry.get(name)
        local schema = rawget(cls, "_compiledSchema")
        if schema then
            for _, entry in pairs(schema) do
                local tk = entry.token
                if tk and overrides[tk] ~= nil then
                    entry.default = overrides[tk]
                end
            end
        end
    end
    if theme.onChanged then
        theme.onChanged(overrides)
    end
    return overrides
end

function theme.applyNamed(name)
    local overrides = themes[name]
    if overrides == nil then
        error(("theme: '%s' is not defined"):format(tostring(name)), 2)
    end
    return theme.apply(overrides)
end

-- hot-reload (dev): reader() -> таблица переопределений (перечитал — применил)
function theme.reload(reader)
    local ok, overrides = pcall(reader)
    if not ok or type(overrides) ~= "table" then
        return false
    end
    theme.apply(overrides)
    return true
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.theme = theme
return theme
