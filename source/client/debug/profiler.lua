-- debug/profiler.lua — per-widget стоимость кадра + статистика (task.md §8)
--
-- Замер выполняется через единый клок (core/time). Инструментация стоит
-- только при включённом профилировании: в холодном пути — один if.
-- Overlay рисует инспектор (dxui:stats), выборка берётся здесь.

local profiler = {}

local enabled = false
local samples = {}   -- widgetType -> { total, count, worst }
local lastFrameCost = 0
local frameCount = 0

local frameCosts = {}      -- кольцевой буфер, медиана
local FRAME_HISTORY = 120

local function now()
    return _G.DXUI.time.now()
end

function profiler.enable(on)
    enabled = on == true
    return enabled
end

function profiler.isEnabled()
    return enabled
end

-- обёртка замера вокруг одного вызова; возврат значения fn
function profiler.measure(widgetType, fn, ...)
    if not enabled then
        return fn(...)
    end
    local t0 = now()
    local result = fn(...)
    local dt = now() - t0
    local rec = samples[widgetType]
    if rec == nil then
        rec = { total = 0, count = 0, worst = 0 }
        samples[widgetType] = rec
    end
    rec.total = rec.total + dt
    rec.count = rec.count + 1
    if dt > rec.worst then rec.worst = dt end
    return result
end

-- фиксация стоимости кадра (boot: начало/конец onFrame)
function profiler.frameStart()
    frameCount = frameCount + 1
    return now()
end

function profiler.frameEnd(t0)
    lastFrameCost = now() - t0
    frameCosts[frameCount % FRAME_HISTORY + 1] = lastFrameCost
end

-- статистика для overlay/инспектора
function profiler.stats()
    local out = {}
    for widgetType, rec in pairs(samples) do
        out[#out + 1] = {
            type = widgetType,
            calls = rec.count,
            avg = rec.count > 0 and rec.total / rec.count or 0,
            worst = rec.worst,
        }
    end
    return out
end

-- меданные последних кадров (медиана 120 кадров после прогрева)
function profiler.medianFrameCost()
    local costs = {}
    for i = 1, FRAME_HISTORY do
        if frameCosts[i] then costs[#costs + 1] = frameCosts[i] end
    end
    if #costs == 0 then return 0 end
    table.sort(costs)
    local mid = math.floor(#costs / 2) + 1
    if #costs % 2 == 0 then
        return (costs[mid - 1] + costs[mid]) / 2
    end
    return costs[mid]
end

-- сброс (тесты)
function profiler.reset()
    samples = {}
    frameCosts = {}
    frameCount = 0
    lastFrameCost = 0
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.profiler = profiler
return profiler
