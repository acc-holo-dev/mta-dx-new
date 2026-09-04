-- core/time.lua — единый клок фреймворка
--
-- Правило task.md §5: «единый клок из core/time — никаких таймеров в виджетах».
-- Источник времени подключается один раз: boot.lua решает, живём ли мы в MTA
-- (getTickCount + dxui-настройки) или в headless-тестах (os.clock монотонного
-- источника). Все остальные модули читают только time.now().

local type = type

local nowFn = function() return 0 end

-- возвращает ms с фиксированной точки отсчёта (монотонно)
local function now()
    return nowFn()
end

-- подключение источника: boot.lua / тестовый раннер
local function setSource(fn)
    if type(fn) ~= "function" then
        error("time.setSource: fn must be a function", 2)
    end
    nowFn = fn
end

-- глава зоопарка: производные утилиты
local function seconds(sec)
    return sec * 1000
end

local function minutes(min)
    return min * 60000
end

return {
    now     = now,
    setSource = setSource,
    seconds = seconds,
    minutes = minutes,
}
