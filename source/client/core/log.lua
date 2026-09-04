-- core/log.lua — уровневый лог с категориями и rate-limit (zero-dependency)
--
--   * log.level("warn") — глобальный порог; ниже порога сообщения отбрасываются.
--   * log.emit(level, category, fmt, ...) — форматирование только если
--     сообщение реально пишется ( горячий путь не платит за __tostring).
--   * log.setSink(f) — приёмщик: f(level, category, msg, timeMs); по умолчанию — io.stderr.
--   * log.rateLimit(category, msg, n) — не более n повторов подряд.
--
-- boot.lua подменяет sink на outputConsoleBox/outputDebugString.

local type = type
local pairs = pairs
local select = select
local tostring = tostring
local format = string.format
local tconcat = table.concat

local LEVELS = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, off = 99 }
local current = LEVELS.info
local sink = nil
local counters = {}
local rateN = 10

local function ensure(level)
    local l = LEVELS[level]
    if not l then error(("log: unknown level %q"):format(tostring(level)), 2) end
    return l
end

local function emit(level, category, fmt, ...)
    local lv = LEVELS[level]
    if not lv then
        error(("log: unknown level %q"):format(tostring(level)), 2)
    end
    if lv < current then return end
    local msg
    if select("#", ...) == 0 then
        msg = fmt
    else
        local ok, res = pcall(format, fmt, ...)
        msg = ok and res or tostring(fmt)
    end
    if sink == nil then
        sink = function(_level, _cat, m)
            io.stderr:write(("[%s][%s] %s\n"):format(_level, _cat, m))
        end
    end
    sink(level, category, msg)
end

local Log = {}

for name, lv in pairs(LEVELS) do
    if name ~= "off" then
        Log[name] = function(category, fmt, ...)
            if lv >= current then
                emit(name, category, fmt, ...)
            end
        end
    end
end

function Log.setLevel(level)
    ensure(level)
    current = LEVELS[level]
end

function Log.setSink(f)
    if type(f) ~= "function" then
        error("log.setSink: sink must be a function", 2)
    end
    sink = f
end

-- rate-limit: категория+ключ не более n сообщений подряд, дальше глушим
function Log.rateLimit(category, key, n)
    local k = category .. "\0" .. tostring(key)
    local c = counters[k]
    if c == nil then
        counters[k] = 1
        return true
    end
    if c >= (n or rateN) then
        return false
    end
    counters[k] = c + 1
    return true
end

function Log.resetCounters()
    counters = {}
end

-- тестовый доступ
function Log._test()
    return LEVELS, current
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.log = Log
return Log
