-- render/frame.lua — пайплайн кадра виджетов
--
-- Кадр (порядок фиксирован, task.md §1):
--   0. flush dirty-списков: грязные узлы помечают RT-кэши предков устаревшими
--      (dirty-списки потребляет только пайплайн — иначе они не сбрасываются);
--   1. layout: рекурсивная пасса раскладки корней (flex/anchors);
--   2. render: рекурсивный обход с накоплением мировых координат;
--      каждый виджет рисует через spec.render(widget, canvas, wx, wy).
-- Развилки (scroll, clip) используют lay, проходя транзитом.
--
-- RT-кэш (§6.1): у виджета с cache=true поддерево растеризуется в текстуру
-- (backend.renderToTexture) и дальше в кадре — одна image-команда. Кэш
-- пересобирается при: грязном узле в поддереве (flush ниже), смене размера
-- (rtW/rtH), отсутствии текстуры. Вложенные кэши внутри кэша рисуются
-- напрямую (rtDepth > 0). Текстуры освобождаются остановкой ресурса MTA:
-- destroyElement вне whitelist (§2), ручного release нет.

local DXUI = _G.DXUI

local frame = {}
local roots = {}

local cacheBackend = nil  -- fn(w, h, sceneFn) -> texture | nil (тесты)
local mtaAdapter = nil    -- ленивая обёртка backend_mta (контракт (sceneFn,w,h))
local cacheCanvas = nil   -- ленивый scratch для перерастеризации
local rtDepth = 0         -- глубина вложенного RT (вложенные кэши — напрямую)

-- тесты подставляют фейк; в игре берётся DXUI.backend_mta.renderToTexture
function frame.setCacheBackend(fn)
    cacheBackend = fn
end

local function getCacheBackend()
    if cacheBackend then
        return cacheBackend
    end
    if mtaAdapter == nil then
        local b = DXUI.backend_mta
        if b == nil or b.renderToTexture == nil then
            return nil
        end
        mtaAdapter = function(w, h, sceneFn)
            return b.renderToTexture(sceneFn, w, h)
        end
    end
    return mtaAdapter
end

-- грязный узел помечает устаревшими кэши себя и всех предков
local function markCacheStale(node)
    local cur = node
    while cur do
        local inod = rawget(cur, "_")
        if inod == nil then return end
        if inod.data.cache == true then
            inod.rtStale = true
        end
        cur = inod.parent
    end
end

local function layoutNode(node)
    local inod = rawget(node, "_")
    if inod == nil or inod.lay == nil then
        return
    end
    -- у контейнерных виджетов пассу выполняет их собственный render-спека;
    -- здесь — универсальный флекс по lay
    local children = inod.children
    if children and #children > 0 then
        local pseudo = { lay = inod.lay, children = {} }
        for i = 1, #children do
            local c = children[i]
            if c ~= nil then
                local cinod = rawget(c, "_")
                pseudo.children[#pseudo.children + 1] = {
                    lay = cinod.lay,
                    children = cinod.children,
                    __child = c,
                }
            end
        end
        DXUI.flex.apply(pseudo)
        -- вернуть геометрию из pseudo обратно в детей (flex пишет прямо в их lay)
        for i = 1, #pseudo.children do
            -- nothing: lay общий по ссылке
        end
    end
    -- рекурсия в детей
    if children then
        for i = 1, #children do
            local c = children[i]
            if c ~= nil then
                layoutNode(c)
            end
        end
    end
end

local function renderNode(node, canvas, ox, oy)
    local inod = rawget(node, "_")
    if inod == nil then return end
    local spec = rawget(node, "_renderSpec")
    local l = inod.lay
    if l == nil then return end
    local wx = ox + (l.x or 0)
    local wy = oy + (l.y or 0)

    if inod.data.visible == false then
        return -- заморозка скрытых поддеревьев (task.md §6.1)
    end

    -- RT-кэш: чистое поддерево = одна image-команда вместо обхода
    if inod.data.cache == true and rtDepth == 0 and not inod.rtRendering then
        local backend = getCacheBackend()
        if backend then
            local rt = inod.rt
            if rt == nil or inod.rtStale or inod.rtW ~= l.w or inod.rtH ~= l.h then
                inod.rtStale = false
                inod.rtW, inod.rtH = l.w, l.h
                if cacheCanvas == nil then
                    cacheCanvas = DXUI.canvas.new()
                end
                cacheCanvas:clear()
                inod.rtRendering = true
                rtDepth = rtDepth + 1
                local ok, tex = pcall(backend, l.w, l.h, function()
                    renderNode(node, cacheCanvas, -wx, -wy)
                end)
                rtDepth = rtDepth - 1
                inod.rtRendering = false
                if ok and tex then
                    inod.rt = tex
                else
                    inod.rt = nil -- бэкенд не смог (видеопамять) — рисуем напрямую
                end
            end
            if inod.rt then
                canvas:image(inod.rt, wx, wy, l.w, l.h)
                return
            end
        end
    end

    if spec and spec.render then
        -- профилирование per-widget: единственный if в холодном пути
        local profiler = DXUI.profiler
        if profiler and profiler.isEnabled() then
            profiler.measure(inod.widgetType, spec.render, node, canvas, wx, wy)
        else
            spec.render(node, canvas, wx, wy)
        end
    end

    local children = inod.children
    if children then
        for i = 1, #children do
            local c = children[i]
            if c ~= nil then
                renderNode(c, canvas, wx, wy)
            end
        end
    end
end

function frame.add(root)
    roots[#roots + 1] = root
    return root
end

-- корни кадра (для input/dispatcher: сбор геометрии hit-test)
function frame.roots()
    return roots
end

function frame.remove(root)
    for i = 1, #roots do
        if roots[i] == root then
            table.remove(roots, i)
            return true
        end
    end
    return false
end

-- поднять корень наверх: Z-порядок корней = позиция в списке
-- (последний рисуется последним = поверх всех; hit-test берёт выше order)
function frame.bringToFront(root)
    local n = #roots
    for i = 1, n do
        if roots[i] == root then
            if i < n then
                table.remove(roots, i)
                roots[n] = root
            end
            return true
        end
    end
    return false
end

function frame.clear()
    for i = #roots, 1, -1 do
        roots[i] = nil
    end
end

-- полный кадр: flush dirty-списков -> раскладка корней -> отрисовка в canvas
function frame.run(canvas)
    -- грязные узлы помечают кэши предков устаревшими (§6.1); списки пустеют
    local prop = DXUI.prop
    prop.flush(prop.DIRTY.RENDER, markCacheStale)
    prop.flush(prop.DIRTY.LAYOUT, markCacheStale)
    for i = 1, #roots do
        layoutNode(roots[i])
    end
    for i = 1, #roots do
        renderNode(roots[i], canvas, 0, 0)
    end
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.frame = frame
return frame
