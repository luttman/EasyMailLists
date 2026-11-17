-- Run: lua test_ui_smoke.lua game   (also: ellesmere, modern)
-- Builds the whole window against a fake game API and runs every script handler once.
-- It can't check how anything looks. It catches Lua errors such as calling a function that
-- doesn't exist yet, which the game otherwise hides.

unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

-- A mock object: any field is another mock, and any call returns a mock, except a few
-- methods where the addon needs a real value back.
local scripted = {} -- every mock that had a script set, in order
local mockMeta = {}
local function Mock(name)
	return setmetatable({ _name = name }, mockMeta)
end
local returns = {
	GetText = "", GetName = "Mock", GetHeight = 0, GetWidth = 0, GetVerticalScroll = 0,
	GetStringWidth = 0, GetChecked = true, IsShown = true, IsVisible = true,
}
-- Game methods and template children start with an uppercase letter (SetPoint, ScrollBar).
-- The addon's own fields on a frame are lowercase (row.entry, menu.row), and those stay nil
-- until the addon sets them, as in the game.
mockMeta.__index = function(self, key)
	if type(key) == "string" and key:match("^%u") then
		return Mock(key)
	end
end
mockMeta.__call = function(self, owner, a, b)
	local name = self._name
	if name == "SetScript" or name == "HookScript" then
		if not rawget(owner, "_scripts") then
			rawset(owner, "_scripts", {})
			scripted[#scripted+1] = owner
		end
		owner._scripts[a] = b
		return
	elseif name == "GetScript" then
		return rawget(owner, "_scripts") and owner._scripts[a]
	elseif returns[name] ~= nil then
		return returns[name]
	end
	return Mock(name)
end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__unm" }) do
	mockMeta[op] = function() return 0 end
end
mockMeta.__concat = function() return "mock" end
mockMeta.__lt = function() return false end
mockMeta.__le = function() return false end

-- the parts of the game API that need real values
local item = { itemName = "Linen Cloth", itemID = 1, quality = 1, isBound = false, stackCount = 5, hyperlink = "[Linen Cloth]", iconFileID = 1 }
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
	GetContainerItemInfo = function() return item end,
	GetContainerNumFreeSlots = function() return 1, 0 end,
	GetContainerFreeSlots = function() return { 1 } end,
	SplitContainerItem = function() end, PickupContainerItem = function() end,
}
C_Item = {
	GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 7 end,
	GetItemCount = function() return 5 end,
	GetItemInfo = function() end,
}
function GetUnitName() return "Me" end
function UnitFactionGroup() return "Horde" end
function GetCursorInfo() end
function IsShiftKeyDown() return false end
function ChatEdit_GetActiveWindow() end
function IsModifiedClick() return true end
local hooks = {}
function hooksecurefunc(name, fn)
	if type(name) == "string" then hooks[#hooks+1] = fn end -- hooks on a frame's method are not run
end
StaticPopupDialogs, UISpecialFrames, SlashCmdList = {}, {}, {}
-- the theme to build comes from the command line: game, ellesmere or modern (default: game)
local theme = arg and arg[1] or "game"
assert(theme == "game" or theme == "ellesmere" or theme == "modern", "unknown theme " .. tostring(theme))
if theme == "ellesmere" then
	EllesmereUI = {
		ACCENT_COLOR = { r = 0.05, g = 0.82, b = 0.62 },
		GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
		GetFontOutlineFlag = function() return "" end,
	}
else
	EllesmereUI = false
end

-- the dropdown library, with the behaviors that matter: Initialize runs the menu function at
-- once (this caught a real bug), and opening a menu runs it again
local menuButtons = {}
local LibDD = {
	Create_UIDropDownMenu = function() return Mock("menu") end,
	UIDropDownMenu_Initialize = function(self, frame, init) rawset(frame, "_init", init); init(frame, 1) end,
	UIDropDownMenu_CreateInfo = function() return {} end,
	UIDropDownMenu_AddButton = function(self, info) menuButtons[#menuButtons+1] = info end,
	ToggleDropDownMenu = function(self, level, value, frame) frame._init(frame, 1) end,
	CloseDropDownMenus = function() end,
}
LibStub = { GetLibrary = function() return LibDD end }

-- everything else in the game API is a mock
-- (kept once made, so a global frame such as MailFrame is the same object every time)
setmetatable(_G, { __index = function(globals, key)
	local mock = Mock(key)
	rawset(globals, key, mock)
	return mock
end })

local group = { name = "Bank", faction = "Horde", list = "Linen Cloth\n=5 Raw Fish\nRaw *\n+20 Runecloth\n-1 Silk Cloth" }
EasyMailListsSave = {
	groups = { group }, lastGroupShown = "Bank", enabled = false, requireShift = true, sendEquipmentHere = false,
	gearQuality = 2, itemIDs = {},
	characters = { Me = { faction = "Horde", realm = "Here" }, Alt = { faction = "Horde", realm = "Elsewhere" } },
	theme = theme,
}

local Shared = {}
assert(loadfile("EasyMailLists/EasyMailLists.lua"))("EasyMailLists", Shared)
assert(loadfile("EasyMailLists/Settings.lua"))("EasyMailLists", Shared)
Shared.UpdateItemList()

-- theme resolution rules (run before the window is built)
do
	local savedUI, savedTheme = EllesmereUI, EasyMailListsSave.theme
	local fake = { ACCENT_COLOR = { r = 0, g = 0, b = 0 } }
	local function Resolve(setting, ui)
		EasyMailListsSave.theme, EllesmereUI = setting, ui
		return Shared.ResolveTheme()
	end
	assert(Resolve(nil, fake) == "ellesmere", "nil with EllesmereUI -> ellesmere")
	assert(Resolve(nil, false) == "game", "nil without EllesmereUI -> game")
	assert(Resolve("ellesmere", false) == "modern", "ellesmere without EllesmereUI -> modern")
	assert(Resolve("ellesmere", fake) == "ellesmere")
	assert(Resolve("modern", fake) == "modern")
	assert(Resolve("game", fake) == "game")
	assert(Resolve("bogus", false) == "game", "an unknown value counts as unset")
	EasyMailListsSave.theme, EllesmereUI = savedTheme, savedUI
end

local errors, seen = 0, {}
local menuEntriesRun = 0
local function Run(what, fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok and not seen[err] then
		seen[err] = true
		errors = errors + 1
		print("ERROR in " .. what .. ":\n" .. err .. "\n")
	end
end

-- open the mailbox: this builds the window
for i = 1, #scripted do
	local onEvent = scripted[i]._scripts.OnEvent
	if onEvent then Run("OnEvent MAIL_SHOW", onEvent, scripted[i], "MAIL_SHOW") end
end
assert(#scripted > 10, "the window was built")

-- run every handler twice: the second pass runs with the rows and buttons the first pass created
local handlerArgs = { OnMouseWheel = 1, OnUpdate = 2, OnEvent = "BAG_UPDATE_DELAYED" }
for pass = 1, 2 do
	local i = 1
	while i <= #scripted do
		for name, fn in pairs(scripted[i]._scripts) do
			if name ~= "OnHide" then
				Run(name, fn, scripted[i], handlerArgs[name] or "LeftButton")
			end
			-- a click may have opened a menu: run every entry it shows (menu buttons carry a func)
			if name == "OnClick" and not rawget(scripted[i], "func") then
				for j = 1, #scripted do
					if rawget(scripted[j], "func") then
						menuEntriesRun = menuEntriesRun + 1
						Run("menu entry", scripted[j]._scripts.OnClick, scripted[j], "LeftButton")
					end
				end
			end
		end
		i = i + 1
	end
	for _, info in ipairs(menuButtons) do
		if info.func then Run("menu: " .. tostring(info.text), info.func) end
	end
	for name, dialog in pairs(StaticPopupDialogs) do
		local data = name:find("AMOUNT") and { key = "linen cloth", item = "Linen Cloth", sign = "=" } or group
		for _, handler in ipairs({ "OnShow", "OnAccept", "OnCancel" }) do
			if dialog[handler] then Run(name .. " " .. handler, dialog[handler], Mock("popup"), data) end
		end
	end
	for _, hook in ipairs(hooks) do
		Run("shift-click hook", hook, "|cffffffff|Hitem:1|h[Wool Cloth]|h|r")
	end
end

assert(errors == 0, errors .. " error(s), see above")
assert(menuEntriesRun > 20, "menu entries were exercised")
print("UI smoke test ok (" .. theme .. "): " .. #scripted .. " frames with scripts, " .. menuEntriesRun .. " menu entry clicks")
