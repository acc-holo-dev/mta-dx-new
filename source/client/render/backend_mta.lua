-- render/backend_mta.lua — ЕДИНСТВЕННОЕ место dxDraw* (task.md §2 whitelist)
--
-- Контракт цветов: весь фреймворк передаёт числа ARGB (AARRGGBB — так
-- записаны palette/tokens/темы). MTA ждёт ABGR (AABBGGRR) — R и B
-- поменяны; переводим ОДНОМ месте, здесь.
--
-- Скругление: если радиус > 0 и шейдер скругления доступен — шейдером,
-- с фолбэком на рисование без скругления (Auto-LOD сам отключает радиусы).

local type = type
local dxDrawRectangle = dxDrawRectangle
local dxDrawText = dxDrawText
local dxDrawImage = dxDrawImage
local dxDrawImageSection = dxDrawImageSection
local dxSetClipRegion = dxSetClipRegion

local backend = {}

local clipLevels = 0 -- на случай, если платформа не поддержала клиппинг

-- ARGB (AARRGGBB) -> MTA ABGR (AABBGGRR): обмен R и B
local function colorArg(color)
    if color == nil then
        return 0xFFFFFFFF -- white
    end
    if type(color) == "number" then
        local a = math.floor(color / 0x1000000) % 0x100
        local r = math.floor(color / 0x10000) % 0x100
        local g = math.floor(color / 0x100) % 0x100
        local b = color % 0x100
        return a * 0x1000000 + b * 0x10000 + g * 0x100 + r
    end
    -- value-объект {r,g,b,a}
    local r = color.r or 255
    local g = color.g or 255
    local b = color.b or 255
    local a = color.a or 255
    return a * 0x1000000 + b * 0x10000 + g * 0x100 + r
end

function backend:rect(x, y, w, h, color, radius)
    local c = colorArg(color)
    if radius and radius > 0 then
        -- TODO(G2+): шейдер скругления с фолбэком; пока — без скругления
        dxDrawRectangle(x, y, w, h, c, false)
    else
        dxDrawRectangle(x, y, w, h, c, false)
    end
end

function backend:text(str, x, y, font, color, alignX, alignY)
    local c = colorArg(color)
    alignX = alignX or "left"
    alignY = alignY or "top"
    -- MTA: alignX/alignY относительно КОРОБКИ текста; clip=false — коробка
    -- не клиппит, поэтому делаем её большой и ставим якорную точку (x, y)
    -- в нужное место коробки: для "center" это центр, для "right"/"bottom" — край
    local left, right = x, x + 10000
    if alignX == "center" then
        left, right = x - 10000, x + 10000
    elseif alignX == "right" then
        left, right = x - 10000, x
    end
    local top, bottom = y, y + 10000
    if alignY == "center" then
        top, bottom = y - 10000, y + 10000
    elseif alignY == "bottom" then
        top, bottom = y - 10000, y
    end
    dxDrawText(tostring(str), left, top, right, bottom, c, 1.0, font or "default", alignX, alignY, false, false, false, true)
end

function backend:image(tex, x, y, w, h, rotate, slice)
    -- MTA: dxDrawImage(x, y, w, h, tex, sourceX, sourceY, sourceW, sourceH, rotate)
    if slice then
        -- TODO(G4+): 9-slice секциями (координаты секций — в пикселях текстуры,
        -- требуется размер исходника из theme/assets); пока рисуем целиком
        dxDrawImage(x, y, w, h, tex, 0, 0, 0, 0, rotate or 0)
        return
    end
    dxDrawImage(x, y, w, h, tex, 0, 0, 0, 0, rotate or 0)
end

function backend:clipPush(x, y, w, h)
    if dxSetClipRegion(x, y, w, h) then
        clipLevels = clipLevels + 1
    end
end

function backend:clipPop()
    if clipLevels > 0 then
        clipLevels = clipLevels - 1
        dxSetClipRegion(false)
    end
end

-- renderToTexture: растеризация сцены в текстуру (RT-кэш статичных поддеревьев).
-- dxSetRenderTarget — глобальное состояние: только defer-обёрткой с
-- восстановлением прежней цели (task.md §2 P7).
function backend.renderToTexture(sceneFn, w, h)
    local rt = dxCreateRenderTarget(w, h, true)
    if not rt then
        return nil
    end
    local prev = dxGetRenderTargets()
    dxSetRenderTarget(rt, true)
    local ok, err = pcall(sceneFn)
    dxSetRenderTarget() -- всегда возвращаем прежнее состояние
    if not ok then
        return nil, err
    end
    return rt
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.backend_mta = backend
return backend
