-- render/backend_headless.lua — исполнение команд в счётчики; бенчмарки для CI
--
-- Единственный бэкенд, живущий БЕЗ MTA: команды не рисуются, а считаются.
-- Используется тестовым раннером (unit) и CI-бюджетами (task.md §6.2):
--   * backend.execute проверяет invariants команд;
--   * backend.benchmark(fn, opts) — медиана 120 «кадров» после прогрева.

local type = type
local os_clock = os.clock
local table_sort = table.sort

local backend = {}

local counters = {
    rect = 0,
    text = 0,
    image = 0,
    clipPush = 0,
    clipPop = 0,
}

local errors = 0
local last = {}

-- ---------------------------------------------------------------- execute

function backend.reset()
    counters.rect = 0
    counters.text = 0
    counters.image = 0
    counters.clipPush = 0
    counters.clipPop = 0
    errors = 0
end

function backend.counters()
    return counters
end

-- валидация команд в headless: плохая команда не падает, но считается ошибкой
local function validNumber(v)
    return type(v) == "number"
end

function backend:rect(x, y, w, h, color, radius)
    if not (validNumber(x) and validNumber(y) and validNumber(w) and validNumber(h)) then
        errors = errors + 1
        return
    end
    if color ~= nil and type(color) ~= "number" and type(color) ~= "table" then
        errors = errors + 1
        return
    end
    last.kind = "rect"
    last.x, last.y, last.w, last.h, last.color, last.radius = x, y, w, h, color, radius
    counters.rect = counters.rect + 1
end

function backend:text(str, x, y, font, color)
    if type(str) ~= "string" then
        errors = errors + 1
        return
    end
    if not (validNumber(x) and validNumber(y)) then
        errors = errors + 1
        return
    end
    last.kind = "text"
    last.str, last.x, last.y, last.font, last.color = str, x, y, font, color
    counters.text = counters.text + 1
end

function backend:image(tex, x, y, w, h, rotate, slice)
    if tex == nil then
        errors = errors + 1
        return
    end
    if not (validNumber(x) and validNumber(y) and validNumber(w) and validNumber(h)) then
        errors = errors + 1
        return
    end
    last.kind = "image"
    last.tex, last.x, last.y, last.w, last.h = tex, x, y, w, h
    last.rotate, last.slice = rotate, slice
    counters.image = counters.image + 1
end

function backend:clipPush(x, y, w, h)
    if not (validNumber(x) and validNumber(y) and validNumber(w) and validNumber(h)) then
        errors = errors + 1
        return
    end
    last.kind = "clipPush"
    counters.clipPush = counters.clipPush + 1
end

function backend:clipPop()
    last.kind = "clipPop"
    counters.clipPop = counters.clipPop + 1
end

function backend:getErrors()
    return errors
end

-- ---------------------------------------------------------------- benchmark

-- медиана кадров; одна «frame» = inner прогонов fn подряд (разрешение os.clock)
-- opts: { frames = 120, warmup = 30, inner = 10 }
function backend.benchmark(fn, opts)
    opts = opts or {}
    local frames = opts.frames or 120
    local warmup = opts.warmup or 30
    local inner = opts.inner or 10

    -- прогрев
    for _ = 1, warmup do
        fn()
    end

    local times = {}
    for _ = 1, frames do
        local t0 = os_clock()
        for _ = 1, inner do
            fn()
        end
        times[#times + 1] = (os_clock() - t0) * 1000 / inner
    end

    table_sort(times)
    local mid = math.floor(#times / 2) + 1
    return times[mid]
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.backend_headless = backend
return backend
