-- render/backend_mta.lua — ЕДИНСТВЕННОЕ место dxDraw*/dxCreate* (whitelist §2)
--
-- Контракт цветов: весь фреймворк передаёт числа ARGB (AARRGGBB — так
-- записаны palette/tokens/темы). MTA ждёт ABGR (AABBGGRR) — R и B
-- поменяны; переводим ОДНОМ местом, здесь (colorArg).
--
-- Скругление: ленивый dxCreateShader из RAW-строки (без файлов, 1.5.6+);
-- цвет идёт через Diffuse dxDrawImage (тот же ABGR-путь, что у всего).
-- Фолбэк — прямоугольник без скругления; shaderTried гасит повторные попытки.
--
-- 9-slice: slice = { l, t, r, b, baseW, baseH } — рамка в пикселях
-- ИСХОДНИКА (baseW/baseH — его размер). Без размеров исходника
-- фолбэк — целая картинка (task.md §4.3).
--
-- renderToTexture: у MTA НЕТ чтения текущей цели (dxGetRenderTarget
-- не существует) — вызывать только когда цель — экран; восстановление
-- всегда dxSetRenderTarget() (§2 P5).

local type = type
local pcall = pcall
local rawget = rawget
local math_floor = math.floor
local DXUI = _G.DXUI -- Auto-LOD (§6.1): lod.dropRadius гасит скругления
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
        local a = math_floor(color / 0x1000000) % 0x100
        local r = math_floor(color / 0x10000) % 0x100
        local g = math_floor(color / 0x100) % 0x100
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

-- ---------------------------------------------------------------- скругление
-- SDF rounded-rect: p в прямоугольнике, q — выступ за скруглённые углы;
-- alpha = saturate(0.5 - dist) — ~1px антиалиасинг. Техника с фолбэком
-- на vs/ps 2.0 — есть на любой карте с MTA.
local ROUNDED_FX = [==[
float gRadius;
float2 gSize;

struct VSInput {
    float3 Position : POSITION;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput {
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

PSInput VS_Main(VSInput input) {
    PSInput output;
    output.Position = float4(input.Position.xy, 0.0, 1.0);
    output.Diffuse = input.Diffuse;
    output.TexCoord = input.TexCoord;
    return output;
}

float4 PS_Main(PSInput input) : COLOR0 {
    float2 halfSize = gSize * 0.5;
    float2 q = abs(input.TexCoord * gSize - halfSize)
             - (halfSize - float2(gRadius, gRadius));
    float dist = length(max(q, 0.0)) - gRadius;
    float edge = saturate(0.5 - dist);
    return input.Diffuse * float4(1.0, 1.0, 1.0, edge);
}

technique rounded_rect {
    pass P0 {
        VertexShader = compile vs_2_0 VS_Main();
        PixelShader = compile ps_2_0 PS_Main();
    }
}
]==]

local roundedShader = false -- false = не пробовали создать; nil = недоступен

local function getRoundedShader()
    if roundedShader == false then
        roundedShader = nil
        local create = rawget(_G, "dxCreateShader")
        if type(create) == "function" then
            local ok, sh = pcall(create, ROUNDED_FX)
            if ok and sh then
                roundedShader = sh
            end
        end
    end
    return roundedShader
end

function backend:rect(x, y, w, h, color, radius)
    local c = colorArg(color)
    -- Auto-LOD: долгой кадр -> рисуем без скругления (§6.1)
    if radius and radius > 0 and not (DXUI.lod and DXUI.lod.dropRadius) then
        local sh = getRoundedShader()
        if sh then
            -- радиус больше половины стороны не имеет смысла
            local maxR = w < h and w or h
            local r = radius * 2
            if r > maxR then
                r = maxR
            end
            dxSetShaderValue(sh, "gSize", w, h)
            dxSetShaderValue(sh, "gRadius", r * 0.5)
            -- цвет — через Diffuse (тот же ABGR colorArg, что и везде)
            dxDrawImage(x, y, w, h, sh, 0, 0, 0, c)
            return
        end
        -- фолбэк: без скругления (Auto-LOD сам отключает радиусы)
    end
    dxDrawRectangle(x, y, w, h, c, false)
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
    if slice then
        local bw, bh = slice.baseW, slice.baseH
        local l, t = slice.l or 0, slice.t or 0
        local r, b = slice.r or 0, slice.b or 0
        local iw, ih = w - l - r, h - t - b
        local isw, ish = bw and (bw - l - r) or 0, bh and (bh - t - b) or 0
        if bw and bh and iw > 0 and ih > 0 and isw > 0 and ish > 0 then
            -- 4 угла 1:1
            dxDrawImageSection(x, y, l, t, 0, 0, l, t, tex)
            dxDrawImageSection(x + w - r, y, r, t, bw - r, 0, r, t, tex)
            dxDrawImageSection(x, y + h - b, l, b, 0, bh - b, l, b, tex)
            dxDrawImageSection(x + w - r, y + h - b, r, b, bw - r, bh - b, r, b, tex)
            -- 4 ребра (тянутся)
            dxDrawImageSection(x + l, y, iw, t, l, 0, isw, t, tex)
            dxDrawImageSection(x + l, y + h - b, iw, b, l, bh - b, isw, b, tex)
            dxDrawImageSection(x, y + t, l, ih, 0, t, l, ish, tex)
            dxDrawImageSection(x + w - r, y + t, r, ih, bw - r, t, r, ish, tex)
            -- центр (тянется)
            dxDrawImageSection(x + l, y + t, iw, ih, l, t, isw, ish, tex)
            return
        end
        -- фолбэк: slice без размеров исходника — целиком
    end
    -- MTA: dxDrawImage(x, y, w, h, tex, sourceX, sourceY, sourceW, sourceH, rotate)
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

-- renderToTexture: растеризация сцены в текстуру (RT-кэш поддеревьев).
-- P5: текущую цель прочитать нельзя — вызывать, только когда цель — экран;
-- восстановление всегда через dxSetRenderTarget() (без аргументов).
function backend.renderToTexture(sceneFn, w, h)
    local crt = rawget(_G, "dxCreateRenderTarget")
    if type(crt) ~= "function" then
        return nil
    end
    local rt = crt(w, h, true)
    if not rt then
        return nil
    end
    dxSetRenderTarget(rt, true)
    local ok, err = pcall(sceneFn)
    dxSetRenderTarget() -- всегда возвращаем экран (см. выше)
    if not ok then
        return nil, err
    end
    return rt
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.backend_mta = backend
return backend
