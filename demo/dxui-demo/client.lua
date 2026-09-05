-- demo/dxui-demo/client.lua — переключатель сценариев (task.md §9.2)
--
-- Внешний потребитель: НИ ОДНОГО внутреннего файла dxui.
-- Только фасад: local ui = loadstring(exports.dxui:import(2))()

local ui = loadstring(exports.dxui:import(2))()

local scenarios = {
    login = DemoLogin,
    inventory = DemoInventory,
    hud = DemoHud,
    bank = DemoBank,
    themes = DemoThemes,
    screens = DemoScreens,
}

local active = nil

local function close()
    if active ~= nil then
        active:destroy()
        active = nil
    end
end

local SCENARIO_NAMES = { "login", "inventory", "hud", "bank", "themes", "screens" }

addCommandHandler("dxuidemo", function(_, name)
    if name == nil or name == "" then
        outputChatBox("dxui-demo: /dxuidemo <" .. table.concat(SCENARIO_NAMES, "|") .. "|off>")
        return
    end
    if name == "off" then
        close()
        outputChatBox("dxui-demo: сценарий закрыт")
        return
    end
    local builder = scenarios[name]
    if builder == nil then
        outputChatBox("dxui-demo: неизвестный сценарий '" .. tostring(name) .. "'")
        return
    end
    close()
    active = builder(ui)
    outputChatBox("dxui-demo: '" .. name .. "' запущен")
end)
