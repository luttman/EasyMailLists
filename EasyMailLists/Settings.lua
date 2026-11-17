local _, Shared = ...

-- The addon's own flat menu. It keeps the function names of LibUIDropDownMenu, which the addon
-- used before, so the code that builds menus didn't have to change. Filled in below the skin.
local LibDD = {}

local ShowGroup -- forward declaration for function

----------------------------------------------------------------------------------------------------
-- helper functions
----------------------------------------------------------------------------------------------------
-- return a group's settings table, or nil if the group wasn't found
function Shared.GetGroupSettings(name)
	for i=1,#EasyMailListsSave.groups do
		if EasyMailListsSave.groups[i].name == name then
			return EasyMailListsSave.groups[i]
		end
	end
end
local GetGroupSettings = Shared.GetGroupSettings

-- split a list line into its optional rule prefix and the item name. The prefixes:
--   +N  send only when you have N or more     -N  keep N stacks     =N  keep N items
-- (digits without a sign belong to the name, like "17 Pound Catfish")
local function ParseLine(line)
	local sign, amount, item = line:match("^%s*([%+%-=])(%d+)%s*(.-)%s*$")
	if not sign then
		item = line:match("^%s*(.-)%s*$")
	end
	return sign, amount, item
end

-- the lowercase item name of a list line, used to compare and sort lines
local function LineKey(line)
	local _, _, item = ParseLine(line)
	return item:lower()
end

-- true for a list line whose item is only *, which would mail every unbound item
function Shared.MatchesEverything(line)
	return LineKey(line):match("^[%*%s]+$") ~= nil
end

-- Ready-made groups for the Patterns menu: { menu text, description, item names }. Without names the menu
-- text is a * line. A line with a group's menu text (like "Flowers") on a list stands for all of its names.
-- ponytail: these match English item names. Use item classes if other languages matter.
-- A * line is only used where nothing unwanted shares the name: "* Stone" also caught sharpening stones.
-- One entry per profession and reagent type. The names are Classic items plus the new WoW Forever
-- herbs. Other WoW Forever reagents aren't confirmed yet, so they aren't listed.
Shared.PATTERNS = {
	{ "Flowers",   "herbalism: every herb", {
		"Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
		"Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker",
		"Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
		"Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
		-- new in WoW Forever; Frilled Lichen, Rosecap and Stranglevine are Scarce (found while picking other herbs)
		"Marefoil", "Demonsage", "Death Lotus", "Frilled Lichen", "Rosecap", "Stranglevine" }, nil, { 7, 9 } },
	{ "Ore",       "mining: every ore", nil, "* Ore" },
	{ "Bars",      "mining: every metal bar", nil, "* Bar" },
	-- Scarce: found while mining other veins. The new ore and bars (Heavy Thorium, Azerothium, Legionite) match * Ore and * Bar.
	{ "Scarce ores", "mining: pyrite, bauxite, pitchblende", { "Pyrite", "Bauxite", "Pitchblende" } },
	{ "Stone",     "mining: rough to dense", { "Rough Stone", "Coarse Stone", "Heavy Stone", "Solid Stone", "Dense Stone" } },
	{ "Gems",      "mining: every gem", {
		"Malachite", "Tigerseye", "Shadowgem", "Moss Agate", "Lesser Moonstone", "Jade", "Citrine", "Aquamarine",
		"Star Ruby", "Blue Sapphire", "Large Opal", "Azerothian Diamond", "Huge Emerald", "Black Diamond", "Arcane Crystal" } },
	{ "Leather",   "skinning: every leather", nil, "* Leather" },
	{ "Hides",     "skinning: light to rugged hide", { "Light Hide", "Medium Hide", "Heavy Hide", "Thick Hide", "Rugged Hide", "Fel Hide", "Pristine Hide" } },
	{ "Scales",    "skinning: scales and dragonscales", {
		"Scorpid Scale", "Turtle Scale", "Deviate Scale", "Red Dragonscale", "Green Dragonscale",
		"Blue Dragonscale", "Black Dragonscale", "Pristine Scale" } },
	{ "Dyes",      "alchemy and leatherworking: new dyes", { "Cerulean Dye", "Magenta Dye", "Viridian Dye" } },
	{ "Herb Seeds", "herbalism: greenhouse seeds", { "Commonplace Herb Seeds", "Uncommon Herb Seeds", "Unusual Herb Seeds", "Scarce Herb Seeds" } },
	{ "Cloth",     "tailoring: linen to runecloth", { "Linen Cloth", "Wool Cloth", "Silk Cloth", "Mageweave Cloth", "Runecloth" } },
	{ "Dusts",     "enchanting: every dust", { "Strange Dust", "Soul Dust", "Vision Dust", "Dream Dust", "Illusion Dust" } },
	{ "Essences",  "enchanting: lesser and greater", {
		"Lesser Magic Essence", "Greater Magic Essence", "Lesser Astral Essence", "Greater Astral Essence",
		"Lesser Mystic Essence", "Greater Mystic Essence", "Lesser Nether Essence", "Greater Nether Essence",
		"Lesser Eternal Essence", "Greater Eternal Essence" } },
	{ "Shards",    "enchanting: every shard", {
		"Small Glimmering Shard", "Large Glimmering Shard", "Small Glowing Shard", "Large Glowing Shard",
		"Small Radiant Shard", "Large Radiant Shard", "Small Brilliant Shard", "Large Brilliant Shard" } },
	{ "Elementals", "alchemy: elemental reagents", {
		"Elemental Fire", "Elemental Air", "Elemental Earth", "Elemental Water", "Essence of Fire", "Essence of Air",
		"Essence of Earth", "Essence of Water", "Essence of Undeath", "Heart of Fire", "Breath of Wind",
		"Core of Earth", "Globe of Water", "Ichor of Undeath", "Fiery Core", "Lava Core", "Living Essence" } },
	{ "Smelting",  "mining: coal and flux", { "Coal", "Elemental Flux" } },
	{ "Pearls",    "fishing: pearls", { "Iridescent Pearl", "Black Pearl", "Golden Pearl" } },
	-- Cooking: every ingredient, no herbs (they're in Flowers) and no vendor food or water. "Raw *" and the
	-- Trade Goods meat type catch raw fish and meat that isn't named here.
	{ "Cooking",   "cooking: meat, fish, eggs, spices", {
		-- meat
		"Stringy Wolf Meat", "Chunk of Boar Meat", "Meaty Bat Wing", "Kodo Meat", "Bear Meat", "Coyote Meat",
		"Soft Frenzy Flesh", "Goretusk Liver", "Strider Meat", "Boar Intestines", "Stringy Vulture Meat",
		"Goretusk Snout", "Crocolisk Meat", "Boar Ribs", "Crag Boar Rib", "Big Bear Meat", "Stag Meat",
		"Tender Crocolisk Meat", "Tough Condor Meat", "Crisp Spider Meat", "Dig Rat", "Raptor Flesh", "Lean Wolf Flank",
		"Thunder Lizard Tail", "Tender Wolf Meat", "Red Wolf Meat", "Heavy Kodo Meat", "Lion Meat", "Mystery Meat",
		"Tiger Meat", "Turtle Meat", "White Spider Meat", "Sandworm Meat", "Chimaerok Tenderloin", "Buzzard Wing",
		-- fish and seafood (Raw * adds the rest)
		"Deviate Fish", "Murloc Fin", "Whimsyfin", "Clam Meat", "Giant Clam Meat", "Tangy Clam Meat", "Zesty Clam Meat",
		"Darkclaw Lobster", "Tender Crab Meat", "Large Raw Mightfish",
		-- eggs and parts
		"Small Egg", "Raptor Egg", "Giant Egg", "Small Spider Leg", "Gooey Spider Leg", "Spider Ichor", "Scorpid Stinger",
		"Small Venom Sac", "Crawler Claw", "Crawler Meat", "Deeprock Salt",
		-- spices
		"Mild Spices", "Hot Spices", "Soothing Spices", "Exquisite Spices" }, "Raw *", { 7, 8 } },
}

function Shared.IsGroup(name)
	for _, pattern in ipairs(Shared.PATTERNS) do
		if (pattern[3] or pattern[4]) and pattern[1]:lower() == name:lower() then return true end
	end
end

-- go through all recipient lists to set up the item list
function Shared.UpdateItemList()
	Shared.itemList = {}
	Shared.wildcards = {}
	Shared.idList = {}
	local faction = (UnitFactionGroup("player"))

	local groups = {} -- [lowercase menu text] = item names, for the Patterns entries that have names
	local wildGroups = {} -- [lowercase menu text] = the * line it stands for, like "Ore" for "* Ore"
	local classGroups = {} -- [lowercase menu text] = "classID/subclassID": any item of that type counts, even one not named in the group
	Shared.classRules = {}
	for _, pattern in ipairs(Shared.PATTERNS) do
		if pattern[5] then classGroups[pattern[1]:lower()] = pattern[5][1] .. "/" .. pattern[5][2] end
		if pattern[3] then groups[pattern[1]:lower()] = pattern[3] end
		if pattern[4] then wildGroups[pattern[1]:lower()] = pattern[4] end
	end

	local fromGroup = {} -- [lowercase name] = true while the entry in itemList came from a group line
	local sign, amount, item
	local minimum, keepStacks
	for i=1,#EasyMailListsSave.groups do
		if EasyMailListsSave.groups[i].faction == faction then
			local recipient = EasyMailListsSave.groups[i].name
			for line in EasyMailListsSave.groups[i].list:gmatch("[^\r\n]+") do
				sign, amount, item = ParseLine(line)
				if item and item ~= "" then
					minimum = sign == "+" and tonumber(amount)
					keepStacks = sign == "-" and tonumber(amount)
					local info = {
						recipient = recipient,
						minimum = minimum,
						keepStacks = keepStacks,
						keepItems = sign == "=" and tonumber(amount),
					}
					if Shared.MatchesEverything(line) and not EasyMailListsSave.groups[i].allowAll then
						-- a line with only * is ignored until the user confirms it (see OnEditFocusLost)
					elseif groups[item:lower()] then
						-- a group line like "Flowers": every name in the group gets this rule
						info.wildcard = item -- shown in the preview as the reason an item is sent
						if wildGroups[item:lower()] then -- a group can also have a * line, like Cooking with "Raw *"
							local wild = wildGroups[item:lower()]:lower():gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*")
							table.insert(Shared.wildcards, { pattern = "^" .. wild .. "$", info = info })
						end
						local classKey = classGroups[item:lower()]
						if classKey and not Shared.classRules[classKey] then
							Shared.classRules[classKey] = info
						end
						-- a line for one item always beats the group, whatever the order of the lines
						for _, name in ipairs(groups[item:lower()]) do
							local key = name:lower()
							if not Shared.itemList[key] or fromGroup[key] then
								Shared.itemList[key] = info
								fromGroup[key] = true
								local itemID = EasyMailListsSave.itemIDs[key]
								if itemID then
									Shared.idList[itemID] = info
								end
							end
						end
					elseif item:find("*", 1, true) or wildGroups[item:lower()] then
						-- "raw *" -> "^raw .*$": escape Lua pattern characters, then * matches anything
						info.wildcard = item -- shown in the preview as the reason an item is sent
						local pattern = (wildGroups[item:lower()] or item):lower():gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*")
						table.insert(Shared.wildcards, { pattern = "^" .. pattern .. "$", info = info })
					else
						Shared.itemList[item:lower()] = info
						fromGroup[item:lower()] = nil
						local itemID = EasyMailListsSave.itemIDs[item:lower()]
						if itemID then
							Shared.idList[itemID] = info
						end
					end
				end
			end
		end
	end
end

local editboxInput -- forward declaration

----------------------------------------------------------------------------------------------------
-- Look - three themes share one layout (the same idea as VendorProfit):
--   game       the game's own window, buttons, checkboxes and fonts, with gold accents
--   ellesmere  flat, with EllesmereUI's accent color and font
--   modern     flat, with the blue-grey palette
----------------------------------------------------------------------------------------------------
-- the theme in use: the saved choice, or ellesmere / game when nothing is saved. The automatic
-- choice is not written back, so installing or removing EllesmereUI later still changes it.
function Shared.ResolveTheme()
	local theme = EasyMailListsSave and EasyMailListsSave.theme
	if theme ~= "game" and theme ~= "ellesmere" and theme ~= "modern" then
		return EllesmereUI and "ellesmere" or "game"
	end
	if theme == "ellesmere" and not EllesmereUI then
		return "modern" -- the choice needs EllesmereUI, which isn't loaded
	end
	return theme
end

-- the modern palette; ApplySkin overrides it for the other themes
local colors = {
	background = { 0.075, 0.085, 0.095 },
	panel      = { 0.045, 0.05, 0.055 },
	button     = { 0.13, 0.15, 0.17 },
	border     = { 0.22, 0.25, 0.28 },
	accent     = { 0.33, 0.77, 1 },
	text       = { 0.94, 0.95, 0.97 },
	muted      = { 0.66, 0.71, 0.76 },
}
local fontFile, fontFlags -- nil in the game theme, which uses the game's font objects
local theme, game -- game: true in the game theme, where Blizzard templates replace the flat widgets

-- ponytail: the theme is read once, when the window is built, so a theme change needs /reload.
local function ApplySkin()
	if theme then return end
	theme = Shared.ResolveTheme()
	game = theme == "game"
	fontFile, fontFlags = ChatFontNormal:GetFont(), ""
	if game then
		fontFile, fontFlags = nil, ""
		-- only panels and menus are filled with color; the templates draw the rest
		colors.background = { 0.06, 0.06, 0.07, 0.95 }
		-- Panels are see-through, so the border color also shows behind the panel. Both are dark:
		-- a light border turned the whole panel grey and made the muted text hard to read.
		colors.panel      = { 0, 0, 0, 0.45 }
		colors.button     = { 0, 0, 0, 0 }
		colors.border     = { 0, 0, 0, 0.45 }
		colors.accent     = { 1, 0.82, 0 }
		colors.text       = { 1, 1, 1 }
		colors.muted      = { 0.62, 0.62, 0.62 }
	elseif theme == "ellesmere" then
		local accent = EllesmereUI.ACCENT_COLOR or EllesmereUI.ELLESMERE_GREEN or { r = 12 / 255, g = 210 / 255, b = 157 / 255 }
		local ok, path = pcall(EllesmereUI.GetFontPath)
		local flagged, flags = pcall(EllesmereUI.GetFontOutlineFlag)
		if ok and type(path) == "string" and path ~= "" then fontFile = path end
		if flagged and type(flags) == "string" then fontFlags = flags end
		colors.background = { 0.08, 0.08, 0.08 }
		colors.panel      = { 0.04, 0.04, 0.04 }
		colors.button     = { 0.11, 0.11, 0.11 }
		colors.border     = { 0.20, 0.20, 0.20 }
		colors.accent     = { accent.r, accent.g, accent.b }
		colors.text       = { 1, 1, 1 }
		colors.muted      = { 0.6, 0.6, 0.6 }
	end
end

-- a solid color filling the parent, pulled in by <inset> pixels on every side
local function Fill(parent, layer, color, inset)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	texture:SetColorTexture(unpack(color))
	return texture
end

local function Label(parent, size, color)
	local text = parent:CreateFontString(nil, "OVERLAY",
		game and (size >= 15 and "GameFontNormalLarge" or size >= 12 and "GameFontHighlight") or "GameFontHighlightSmall")
	if fontFile then text:SetFont(fontFile, size, fontFlags) end
	text:SetTextColor(unpack(color))
	return text
end

local function Button(parent, text, width)
	if game then
		local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		button:SetSize(width, 22)
		button:SetText(text)
		button.label = button:GetFontString() -- so callers can recolor and move the text in every theme
		return button
	end
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 22)
	Fill(button, "BACKGROUND", colors.border, 0)
	Fill(button, "BORDER", colors.button, 1)
	Fill(button, "HIGHLIGHT", colors.accent, 1):SetAlpha(0.15)
	button.label = Label(button, 12, colors.text)
	button.label:SetPoint("CENTER")
	button.label:SetText(text)
	return button
end

-- a hint that shows while the mouse is over a control. Call it after the control's own scripts are set.
local function Tip(widget, text)
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

----------------------------------------------------------------------------------------------------
-- Menu - one flat popup list, shared by every menu in the window
----------------------------------------------------------------------------------------------------
-- A menu is a table with an init function. Opening it runs init, which adds entries with
-- UIDropDownMenu_AddButton({ text, func, checked }).
local menuFrame, menuEntries

function LibDD:Create_UIDropDownMenu()
	return {}
end

function LibDD:UIDropDownMenu_Initialize(menu, init)
	menu.init = init
end

function LibDD:UIDropDownMenu_CreateInfo()
	return {}
end

function LibDD:UIDropDownMenu_AddButton(info)
	menuEntries[#menuEntries+1] = info
end

function LibDD:CloseDropDownMenus()
	if menuFrame then
		menuFrame:Hide()
	end
end

-- open the menu under the anchor, or close it if it's already open there
function LibDD:ToggleDropDownMenu(_, _, menu, anchor)
	if menuFrame and menuFrame:IsShown() and menuFrame.anchor == anchor then
		menuFrame:Hide()
		return
	end

	if not menuFrame then
		menuFrame = CreateFrame("Frame", nil, UIParent)
		menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
		menuFrame:SetClampedToScreen(true)
		menuFrame:EnableMouse(true)
		Fill(menuFrame, "BACKGROUND", colors.border, 0)
		Fill(menuFrame, "BORDER", colors.background, 1)
		menuFrame.buttons = {}
		-- an invisible button over the whole screen, below the menu: a click anywhere else closes the menu
		local catcher = CreateFrame("Button", nil, menuFrame)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN")
		catcher:RegisterForClicks("AnyUp")
		catcher:SetScript("OnClick", function() menuFrame:Hide() end)
	end

	menuEntries = {}
	menu.init()

	local width = anchor:GetWidth()
	for i, info in ipairs(menuEntries) do
		local button = menuFrame.buttons[i]
		if not button then
			button = CreateFrame("Button", nil, menuFrame)
			button:SetHeight(20)
			button:SetPoint("TOPLEFT", 1, -(i - 1) * 20 - 2)
			button:SetPoint("RIGHT", -1, 0)
			Fill(button, "HIGHLIGHT", colors.accent, 0):SetAlpha(0.15)
			button.label = Label(button, 12, colors.text)
			button.label:SetPoint("LEFT", 8, 0)
			button:SetScript("OnClick", function(self)
				menuFrame:Hide()
				self.func()
			end)
			menuFrame.buttons[i] = button
		end
		button.func = info.func
		button.label:SetText(info.text)
		button.label:SetTextColor(unpack(info.checked and colors.accent or colors.text)) -- the current choice
		button:Show()
		width = math.max(width, button.label:GetStringWidth() + 16)
	end
	for i = #menuEntries + 1, #menuFrame.buttons do
		menuFrame.buttons[i]:Hide()
	end

	menuFrame.anchor = anchor
	menuFrame:SetSize(width, #menuEntries * 20 + 4)
	menuFrame:ClearAllPoints()
	menuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menuFrame:Show()
end

-- a bordered panel whose content (box.content) scrolls with the mouse wheel
-- ponytail: mouse wheel only, no scroll bar. Add one if lists get long.
local function ScrollBox(parent)
	local box = CreateFrame("ScrollFrame", nil, parent)
	Fill(box, "BACKGROUND", colors.border, 0)
	Fill(box, "BORDER", colors.panel, 1)
	box.content = CreateFrame("Frame", nil, box)
	box.content:SetSize(264, 1)
	box:SetScrollChild(box.content)
	box:EnableMouseWheel(true)
	-- scroll by a number of pixels and stay inside the content; ScrollBy(0) only clamps
	function box:ScrollBy(amount)
		local range = math.max(0, self.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() + amount)))
	end
	box:SetScript("OnMouseWheel", function(self, delta) self:ScrollBy(-delta * 36) end)
	return box
end

local function Check(parent, text)
	local check = CreateFrame("CheckButton", nil, parent, game and "UICheckButtonTemplate" or nil)
	check:SetSize(game and 24 or 22, game and 24 or 22)
	if not game then -- the game's template has its own box and check mark
		-- a flat box with an accent square inside when checked
		local function Square(layer, size, color)
			local texture = check:CreateTexture(nil, layer)
			texture:SetSize(size, size)
			texture:SetPoint("CENTER")
			texture:SetColorTexture(unpack(color))
			return texture
		end
		Square("BACKGROUND", 14, colors.border)
		Square("BORDER", 12, colors.panel)
		Square("HIGHLIGHT", 12, colors.accent):SetAlpha(0.2)
		local mark = Square("ARTWORK", 8, colors.accent)
		-- PostClick and the SetChecked hook, so the scripts that callers set with OnClick don't replace this
		local function UpdateMark() mark:SetShown(check:GetChecked()) end
		check:SetScript("PostClick", UpdateMark)
		hooksecurefunc(check, "SetChecked", UpdateMark)
		UpdateMark()
	end
	local label = Label(check, 12, colors.text)
	label:SetPoint("LEFT", check, "RIGHT", 1, 0)
	label:SetText(text)
	check:SetHitRectInsets(0, -label:GetStringWidth() - 2, 0, 0) -- the label is clickable too
	return check
end

----------------------------------------------------------------------------------------------------
-- GUI - most widget scripts set up after the layout
----------------------------------------------------------------------------------------------------
local window
local docked -- true while the window is attached to the mailbox
local mailOpen -- true between MAIL_SHOW and the mailbox closing
local skipped = {} -- [plan entry key] = true: left out of the next send; forgotten when the mailbox closes

local function CreateGUI()
	if window then
		return
	end
	ApplySkin()
	-- the game's window frame has a title bar of its own; everything below it moves down by this much
	local top = game and 22 or 0

	--------------------------------------------------
	-- main window
	--------------------------------------------------
	window = CreateFrame("Frame", "EasyMailListsFrame", UIParent, game and "BasicFrameTemplate" or nil) -- not WithInset: its inner border would cut through the content
	window:SetSize(280, 424 + top)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function(self)
		if not docked then self:StartMoving() end -- locked in place at the mailbox
	end)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetScript("OnHide", function(self)
		self:StopMovingOrSizing()
		LibDD:CloseDropDownMenus()
		editboxInput:ClearFocus() -- saves the list
	end)
	UISpecialFrames[#UISpecialFrames + 1] = "EasyMailListsFrame" -- escape closes it

	--------------------------------------------------
	-- title bar: flat themes: [title version] ... [Theme] [?] [X]
	--            game theme:  its own title bar with the title and X, then a row [version] ... [Theme] [?]
	--------------------------------------------------
	local buttonHelp = Button(window, "?", 25)
	if game then
		window.TitleText:SetText("EasyMail Lists")
		-- the template's close button does what the flat X button does
		window.CloseButton:SetScript("OnClick", function() Shared.ToggleWindow() end)
		buttonHelp:SetPoint("TOPRIGHT", -8, -7 - top)
	else
		local edge = window:CreateTexture(nil, "BACKGROUND", nil, -8)
		edge:SetPoint("TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", 1, -1)
		edge:SetColorTexture(unpack(colors.border))
		Fill(window, "BACKGROUND", colors.background, 0):SetDrawLayer("BACKGROUND", -7)

		local textHeader = Label(window, 16, colors.accent)
		textHeader:SetPoint("TOPLEFT", 10, -10)
		textHeader:SetText("EasyMail Lists")

		local buttonClose = Button(window, "X", 25)
		buttonClose:SetPoint("TOPRIGHT", -8, -7)
		buttonClose:SetScript("OnClick", function() Shared.ToggleWindow() end)
		buttonHelp:SetPoint("RIGHT", buttonClose, "LEFT", -4, 0)
	end
	-- the version is in the help tooltip: the title bar has no room for it next to the buttons
	local version = "EasyMail Lists " .. tostring(C_AddOns.GetAddOnMetadata("EasyMailLists", "Version"))
	buttonHelp:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText("|cff999999" .. version .. "|r\n\n" ..
[[|cffffff00Tips:|r
|cffffffffHover over any button to see what it does.
Shift-click an item or drag it onto the list to add it.
To keep one item out of gear mailing, add it to that character's own list.|r

|cffffff00Text view:|r
|cffffffffWrite one item name per line. Names aren't case sensitive.|r
|cffcccc00Raw *|r|cffffffff  * matches any text|r
|cffcccc00+20 Runecloth|r|cffffffff  send only when you have 20 or more|r
|cffcccc00-1 Silk Cloth|r|cffffffff  keep 1 stack, send the rest|r
|cffcccc00=20 Rockscale Cod|r|cffffffff  keep 20, send the rest|r]], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	buttonHelp:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- the theme menu; the look is read when the window is built, so a pick asks for a reload
	StaticPopupDialogs["EASYMAILLISTS_POPUP_RELOAD"] = {
		text = "The theme changes after a reload. Reload now?",
		button1 = YES,
		button2 = NO,
		timeout = 0,
		whileDead = true,
		preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
		OnAccept = function() ReloadUI() end,
	}
	local buttonTheme = Button(window, "Theme", 50)
	buttonTheme:SetPoint("RIGHT", buttonHelp, "LEFT", -4, 0)
	local themeMenu = LibDD:Create_UIDropDownMenu("EasyMailListsThemeMenu", window)
	LibDD:UIDropDownMenu_Initialize(themeMenu, function()
		local current = Shared.ResolveTheme()
		for _, choice in ipairs({
			{ "game", "Default" },
			{ "ellesmere", EllesmereUI and "EllesmereUI" or "EllesmereUI (not installed)" },
			{ "modern", "Modern" },
		}) do
			local info = LibDD:UIDropDownMenu_CreateInfo()
			info.text = choice[2]
			info.checked = choice[1] == current
			info.func = function()
				if choice[1] == current or (choice[1] == "ellesmere" and not EllesmereUI) then
					return
				end
				EasyMailListsSave.theme = choice[1]
				StaticPopup_Show("EASYMAILLISTS_POPUP_RELOAD")
			end
			LibDD:UIDropDownMenu_AddButton(info)
		end
	end, "MENU")
	buttonTheme:SetScript("OnClick", function(self)
		LibDD:ToggleDropDownMenu(1, nil, themeMenu, self, 0, 0)
	end)

	--------------------------------------------------
	-- tabs: [Send] [Lists] - each shows one page below the tab row
	--------------------------------------------------
	local pageSend = CreateFrame("Frame", nil, window)
	local pageLists = CreateFrame("Frame", nil, window)
	for _, page in ipairs({ pageSend, pageLists }) do
		page:SetPoint("TOPLEFT", 0, -26 - top)
		page:SetPoint("BOTTOMRIGHT")
	end

	local tabSend = Button(window, "Send", 130)
	tabSend:SetPoint("TOPLEFT", 8, -38 - top)
	local tabLists = Button(window, "Lists", 130)
	tabLists:SetPoint("LEFT", tabSend, "RIGHT", 4, 0)

	-- the selected tab gets an accent line along its bottom edge
	for _, tab in ipairs({ tabSend, tabLists }) do
		tab.selected = tab:CreateTexture(nil, "OVERLAY")
		tab.selected:SetPoint("BOTTOMLEFT", 1, 1)
		tab.selected:SetPoint("BOTTOMRIGHT", -1, 1)
		tab.selected:SetHeight(2)
		tab.selected:SetColorTexture(unpack(colors.accent))
	end

	function window.ShowTab(send)
		editboxInput:ClearFocus() -- saves the list
		pageSend:SetShown(send)
		pageLists:SetShown(not send)
		tabSend.selected:SetShown(send)
		tabLists.selected:SetShown(not send)
		tabSend.label:SetTextColor(unpack(send and colors.accent or colors.muted))
		tabLists.label:SetTextColor(unpack(send and colors.muted or colors.accent))
		Shared.RefreshPreview()
	end
	tabSend:SetScript("OnClick", function() window.ShowTab(true) end)
	tabLists:SetScript("OnClick", function() window.ShowTab(false) end)

	--------------------------------------------------
	-- recipient row: [recipient v] [faction]
	--------------------------------------------------
	local buttonGroup = Button(pageLists, "", 238)
	buttonGroup:SetPoint("TOPLEFT", 8, -38)
	buttonGroup.label:ClearAllPoints()
	buttonGroup.label:SetPoint("LEFT", 8, 0)
	local arrow = buttonGroup:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -6, -3)
	arrow:SetVertexColor(unpack(colors.muted))

	local buttonFaction = CreateFrame("Button", nil, pageLists)
	buttonFaction:SetSize(22, 22)
	buttonFaction:SetPoint("LEFT", buttonGroup, "RIGHT", 4, 0)

	-- the list of recipients opens as a menu under the recipient button
	local dropdownGroup = LibDD:Create_UIDropDownMenu("EasyMailListsDropdownGroup", window)
	LibDD:UIDropDownMenu_Initialize(dropdownGroup, function()
		for i=1,#EasyMailListsSave.groups do
			local name = EasyMailListsSave.groups[i].name
			local info = LibDD:UIDropDownMenu_CreateInfo()
			info.text    = name
			info.checked = name == EasyMailListsSave.lastGroupShown
			info.func    = function() ShowGroup(name) end
			LibDD:UIDropDownMenu_AddButton(info)
		end
	end, "MENU")
	buttonGroup:SetScript("OnClick", function(self)
		LibDD:ToggleDropDownMenu(1, nil, dropdownGroup, self, 0, 0)
	end)

	--------------------------------------------------
	-- recipient buttons: [new] [rename] [delete]
	--------------------------------------------------
	local buttonNew = Button(pageLists, "New", 86)
	buttonNew:SetPoint("TOPLEFT", buttonGroup, "BOTTOMLEFT", 0, -4)
	local buttonRename = Button(pageLists, "Rename", 85)
	buttonRename:SetPoint("LEFT", buttonNew, "RIGHT", 4, 0)
	local buttonDelete = Button(pageLists, "Delete", 85)
	buttonDelete:SetPoint("LEFT", buttonRename, "RIGHT", 4, 0)

	local textNoGroup = Label(pageLists, 12, colors.muted)
	textNoGroup:SetPoint("TOP", 0, -110)
	textNoGroup:SetWidth(230)
	textNoGroup:SetJustifyH("LEFT")
	textNoGroup:SetText("Get started\n\n"
		.. "1. Click New and choose who gets your items.\n\n"
		.. "2. Add items: shift-click them, drag them onto the list, or click Add from bags.\n\n"
		.. "3. Open a mailbox and click Send.")

	--------------------------------------------------
	-- BoE options
	--------------------------------------------------
	local checkboxSendEquipmentHere = Check(pageLists, "Send unbound gear here")
	checkboxSendEquipmentHere:SetPoint("TOPLEFT", buttonNew, "BOTTOMLEFT", -2, -4)

	-- the lowest gear quality to send; click to step through the choices
	local QUALITIES = {
		[2] = { text = "Green+", color = { 0.12, 1, 0 } },
		[3] = { text = "Blue+",  color = { 0, 0.44, 0.87 } },
		[4] = { text = "Epic",   color = { 0.64, 0.21, 0.93 } },
	}
	local buttonQuality = Button(pageLists, "", 85)
	buttonQuality:SetPoint("TOPRIGHT", buttonDelete, "BOTTOMRIGHT", 0, -4)
	function buttonQuality:Update()
		local quality = QUALITIES[EasyMailListsSave.gearQuality] or QUALITIES[2]
		self.label:SetText(quality.text)
		self.label:SetTextColor(unpack(quality.color))
	end
	buttonQuality:SetScript("OnClick", function(self)
		EasyMailListsSave.gearQuality = QUALITIES[(EasyMailListsSave.gearQuality or 2) + 1] and EasyMailListsSave.gearQuality + 1 or 2
		self:Update()
	end)
	buttonQuality:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText("The lowest quality of unbound weapons and armor to send.\nClick to change.")
		GameTooltip:Show()
	end)
	buttonQuality:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local checkboxDoNotSendEquipment = Check(pageLists, "Never send gear from this character")
	checkboxDoNotSendEquipment:SetPoint("TOPLEFT", checkboxSendEquipmentHere, "BOTTOMLEFT", 0, 2)

	--------------------------------------------------
	-- global options along the bottom
	--------------------------------------------------
	local checkboxEnabled = Check(window, "Auto-send")
	checkboxEnabled:SetPoint("BOTTOMLEFT", 6, 7)
	checkboxEnabled:SetScript("OnClick", function(self) EasyMailListsSave.enabled = self:GetChecked() or false end)

	local checkboxRequireShift = Check(window, "Only with Shift")
	checkboxRequireShift:SetPoint("BOTTOMLEFT", 112, 7) -- short labels: the game's font is wider than the flat one
	checkboxRequireShift:SetScript("OnClick", function(self) EasyMailListsSave.requireShift = self:GetChecked() or false end)

	--------------------------------------------------
	-- item list area: a toolbar, then one of three views of the same list
	--   rows: one row per item (the default)   text: the edit box   bags: pick items from your bags
	--------------------------------------------------
	local listArea = CreateFrame("Frame", nil, pageLists)
	listArea:SetPoint("TOPLEFT", checkboxDoNotSendEquipment, "BOTTOMLEFT", 2, -2)
	listArea:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 34)

	local buttonAddBags = Button(listArea, "Add from bags", 130)
	buttonAddBags:SetPoint("TOPLEFT")
	local buttonMode = Button(listArea, "Text", 60)
	buttonMode:SetPoint("TOPRIGHT")

	local mode = "rows" -- the view that is showing
	local RefreshRows, RefreshBags -- set up further down, with the views they fill

	local function CurrentGroup()
		return GetGroupSettings(EasyMailListsSave.lastGroupShown)
	end

	-- Every view edits the list text in the recipient's settings, so the text box, the rows, and
	-- old saved lists all stay the same format.
	-- replace the line for an item (key: its lowercase name) with newLine, or remove it when newLine is nil
	local function EditLine(key, newLine)
		local group = CurrentGroup()
		if not group then
			return
		end
		local lines = {}
		for line in group.list:gmatch("[^\r\n]+") do
			if LineKey(line) ~= key then
				lines[#lines+1] = line
			elseif newLine then
				lines[#lines+1] = newLine
				newLine = nil -- a duplicate line further down is dropped
			end
		end
		group.list = table.concat(lines, "\n")
		Shared.UpdateItemList()
		ShowGroup(group.name)
	end

	-- add an item by name unless it's already on the list. itemID is optional and only remembered.
	local function AddItem(name, itemID)
		local group = CurrentGroup()
		if not group or not listArea:IsVisible() then
			return
		end
		if tonumber(itemID) then
			EasyMailListsSave.itemIDs[name:lower()] = tonumber(itemID)
		end
		editboxInput:ClearFocus() -- saves anything typed in the text view first
		for line in group.list:gmatch("[^\r\n]+") do
			if LineKey(line) == name:lower() then
				UIErrorsFrame:AddMessage(name .. " is already on this list.", 1, 0.82, 0)
				return
			end
		end
		local separator = (group.list == "" or group.list:sub(-1) == "\n") and "" or "\n"
		group.list = group.list .. separator .. name
		Shared.UpdateItemList()
		ShowGroup(group.name)
	end

	--------------------------------------------------
	-- editbox (the text view)
	--------------------------------------------------
	local editbox = CreateFrame("Frame", "EasyMailListsEdit", listArea)
	editboxInput = CreateFrame("EditBox", "EasyMailListsEditInput", editbox) -- local not used because of forward declaration
	local editboxScroll = CreateFrame("ScrollFrame", "EasyMailListsEditScroll", editbox, "UIPanelScrollFrameTemplate")

	-- editbox - main container
	editbox:SetPoint("TOPLEFT", 0, -26)
	editbox:SetPoint("BOTTOMRIGHT")
	Fill(editbox, "BACKGROUND", colors.border, 0)
	Fill(editbox, "BORDER", colors.panel, 1)

	-- editboxInput
	editboxInput:SetMultiLine(true)
	editboxInput:SetAutoFocus(false)
	editboxInput:EnableMouse(true)
	if fontFile then
		editboxInput:SetFont(fontFile, 12, fontFlags)
	else
		editboxInput:SetFontObject(ChatFontNormal) -- the game theme keeps to the game's fonts
	end
	editboxInput:SetTextColor(unpack(colors.text))
	editboxInput:SetSize(232, 1) -- the height grows with the text
	editboxInput:SetScript("OnEscapePressed", function() editboxInput:ClearFocus() end)

	-- editboxScroll - the template's scroll bar sits to its right and hides while the list fits
	editboxScroll:SetPoint("TOPLEFT", editbox, "TOPLEFT", 6, -6)
	editboxScroll:SetPoint("BOTTOMRIGHT", editbox, "BOTTOMRIGHT", -26, 6)
	editboxScroll.scrollBarHideable = true
	local scrollBar = editboxScroll.ScrollBar or _G["EasyMailListsEditScrollScrollBar"]
	if scrollBar then scrollBar:Hide() end
	editboxScroll:EnableMouse(true)
	editboxScroll:SetScript("OnMouseDown", function() editboxInput:SetFocus() end)
	editboxScroll:SetScrollChild(editboxInput)

	editbox:EnableMouse(true)
	editbox:SetScript("OnMouseDown", function() editboxInput:SetFocus() end)

	editboxInput:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, self:GetParent()) end)
	editboxInput:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, self:GetParent()) end)
	editboxInput:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)

	--------------------------------------------------
	-- Send page: a preview of what will be mailed, and the button that mails it
	--------------------------------------------------
	local ROW_HEIGHT = 18

	local previewBox = ScrollBox(pageSend)
	previewBox:SetPoint("TOPLEFT", 8, -38)
	previewBox:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 62)
	local previewContent = previewBox.content

	local textPreview = Label(pageSend, 12, colors.muted)
	textPreview:SetPoint("CENTER", previewBox)
	textPreview:SetWidth(230)

	local buttonSend = Button(pageSend, "Send", 264)
	buttonSend:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 36)
	buttonSend:SetScript("OnClick", function()
		Shared.StartSending(skipped)
		Shared.RefreshPreview()
	end)

	-- one line in the preview: a heading, an item to send (clickable), or an item that is kept
	local previewRows = {}
	local function SetRow(i, text, color, icon, right, link, entry)
		local row = previewRows[i]
		if not row then
			row = CreateFrame("Button", nil, previewContent)
			row:SetSize(262, ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 1, -(i - 1) * ROW_HEIGHT - 3)
			row.hover = Fill(row, "HIGHLIGHT", colors.accent, 0)
			row.hover:SetAlpha(0.12)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(14, 14)
			row.icon:SetPoint("LEFT", 5, 0)
			row.right = Label(row, 11, colors.muted)
			row.right:SetPoint("RIGHT", -6, 0)
			row.text = Label(row, 12, colors.text)
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(false)
			row:SetScript("OnClick", function(self)
				if self.entry then
					skipped[self.entry.key] = not skipped[self.entry.key] or nil
					Shared.RefreshPreview()
				end
			end)
			row:SetScript("OnEnter", function(self)
				if not self.link then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(self.link)
				if self.entry then
					GameTooltip:AddLine(skipped[self.entry.key] and "Click to send it after all." or "Click to skip it this time.", 0.6, 0.6, 0.6)
				end
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			previewRows[i] = row
		end
		row.link, row.entry = link, entry
		row.icon:SetTexture(icon)
		row.icon:SetShown(icon ~= nil)
		row.right:SetText(right or "")
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", icon and 24 or 6, 0)
		row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
		row.text:SetText(text)
		row.text:SetTextColor(unpack(color or colors.text))
		row.hover:SetShown(entry ~= nil)
		row:SetAlpha(entry and skipped[entry.key] and 0.4 or 1)
		row:Show()
	end

	local function CountAndLink(entry)
		return (entry.count > 1 and entry.count .. "x " or "") .. (entry.link or "?")
	end

	function Shared.RefreshPreview()
		if not pageSend:IsVisible() then
			return
		end
		local sending = Shared.IsSending()
		local rows, sendCount = 0, 0

		if mailOpen and not sending then
			local send, kept = Shared.BuildPlan()
			local recipient
			for _, entry in ipairs(send) do
				if entry.recipient ~= recipient then
					recipient = entry.recipient
					rows = rows + 1
					SetRow(rows, "To " .. recipient, colors.accent)
				end
				local skip = skipped[entry.key]
				rows = rows + 1
				SetRow(rows, CountAndLink(entry), nil, entry.icon, skip and "skipped" or entry.rule, entry.link, entry)
				if not skip then
					sendCount = sendCount + 1
				end
			end
			if #kept > 0 then
				rows = rows + 1
				SetRow(rows, "Kept in your bags", colors.muted)
				for _, entry in ipairs(kept) do
					rows = rows + 1
					SetRow(rows, CountAndLink(entry), nil, entry.icon, entry.reason, entry.link)
				end
			end
		end

		for i = rows + 1, #previewRows do
			previewRows[i]:Hide()
		end
		previewContent:SetHeight(rows * ROW_HEIGHT + 6)
		previewBox:ScrollBy(0)

		textPreview:SetText(
			not mailOpen and "Open a mailbox to see what will be sent."
			or sending and "Sending..."
			or rows == 0 and "Nothing to send.\nAdd items on the Lists tab."
			or "")
		buttonSend.label:SetText(sendCount == 0 and "Send" or sendCount == 1 and "Send 1 item" or "Send " .. sendCount .. " items")
		buttonSend:SetEnabled(sendCount > 0)
		buttonSend.label:SetTextColor(unpack(sendCount > 0 and colors.text or colors.muted))
	end
	Shared.OnSendingFinished = Shared.RefreshPreview

	-- keep the window next to whichever mail window is furthest right
	if OpenMailFrame then
		OpenMailFrame:HookScript("OnShow", Shared.Redock)
		OpenMailFrame:HookScript("OnHide", Shared.Redock)
	end
	if SendMailFrame then
		-- PathForever Mail opens its own side panel on the Send Mail tab; look again a frame later
		local function RedockSoon() C_Timer.After(0, Shared.Redock) end
		SendMailFrame:HookScript("OnShow", RedockSoon)
		SendMailFrame:HookScript("OnHide", RedockSoon)
	end

	--------------------------------------------------
	-- GUI scripts - helper functions
	--------------------------------------------------
	-- show a group's settings, or disable widgets if that group doesn't exist
	ShowGroup = function(name)
		editboxInput:ClearFocus()

		local group = GetGroupSettings(name)
		LibDD:CloseDropDownMenus()
		for _, widget in ipairs({ buttonGroup, buttonFaction, buttonRename, buttonDelete, checkboxSendEquipmentHere, buttonQuality, checkboxDoNotSendEquipment, listArea }) do
			widget:SetShown(group ~= nil)
		end
		textNoGroup:SetShown(group == nil)
		-- the faction of your own characters is known, so only typed names get the faction toggle
		buttonFaction:SetShown(group ~= nil and not EasyMailListsSave.characters[name])
		if group then
			EasyMailListsSave.lastGroupShown = name
			buttonGroup.label:SetText(name)

			checkboxSendEquipmentHere:SetChecked(name == EasyMailListsSave.sendEquipmentHere)
			checkboxDoNotSendEquipment:SetChecked(group.doNotSendEquipment)
			buttonFaction:SetFactionIcon(group.faction)

			-- put list in alphabetical order
			local list = {}
			if group.list then
				for item in group.list:gmatch("[^\n\r]+") do
					local lowercaseItem = LineKey(item)
					if lowercaseItem ~= "" and not list[lowercaseItem] then
						list[lowercaseItem] = true
						list[#list+1] = item
					end
				end
				table.sort(list, function(text1, text2) return LineKey(text1) < LineKey(text2) end)
			end
			editboxInput:SetText(table.concat(list, "\n"))
			RefreshRows(list)
			if mode == "bags" then
				RefreshBags()
			end
		end
	end

	-- create a new group and add it in alphabetical order - return true if successful
	local function AddGroup(name)
		if not name or name == "" or GetGroupSettings(name) then
			return false
		end
		local insertAt = 1
		for i=1,#EasyMailListsSave.groups do
			if EasyMailListsSave.groups[i].name:lower() > name:lower() then
				break
			end
			insertAt = insertAt + 1
		end
		table.insert(EasyMailListsSave.groups, insertAt, {["name"]=name, ["faction"]=(UnitFactionGroup("player")), ["list"]=""})
		return true
	end

	-- remove a group - doesn't update the rules list - return true if successful
	local function RemoveGroup(name)
		for i=1,#EasyMailListsSave.groups do
			if EasyMailListsSave.groups[i].name:lower() == name:lower() then
				table.remove(EasyMailListsSave.groups, i)
				if EasyMailListsSave.sendEquipmentHere == name then
					EasyMailListsSave.sendEquipmentHere = nil
				end
				return true
			end
		end
		return false
	end

	-- rename a group - return true if successful
	local function RenameGroup(oldName, newName)
		local oldGroup = GetGroupSettings(oldName)
		if not oldGroup or not newName or newName == "" or GetGroupSettings(newName) then
			return false
		end

		if EasyMailListsSave.sendEquipmentHere == oldName then
			EasyMailListsSave.sendEquipmentHere = newName
		end

		RemoveGroup(oldName)
		AddGroup(newName)
		oldGroup.name = newName
		local newGroup = GetGroupSettings(newName)
		for k,v in pairs(oldGroup) do
			newGroup[k] = v
		end

		return true
	end

	--------------------------------------------------
	-- GUI scripts - editbox
	--------------------------------------------------
	editboxInput:SetScript("OnEditFocusLost", function(self)
		local group = GetGroupSettings(EasyMailListsSave.lastGroupShown)
		if not group then
			return
		end
		group.list = self:GetText()

		-- a line with only * mails everything, so it needs a yes before it takes effect
		local matchesEverything = false
		for line in group.list:gmatch("[^\r\n]+") do
			matchesEverything = matchesEverything or Shared.MatchesEverything(line)
		end
		if not matchesEverything then
			group.allowAll = nil
		elseif not group.allowAll then
			StaticPopupDialogs["EASYMAILLISTS_POPUP_ALL"] = StaticPopupDialogs["EASYMAILLISTS_POPUP_ALL"] or {
				text = "A line with only * mails every unbound item in your bags to %s.\n\nKeep that line?",
				button1 = YES,
				button2 = NO,
				timeout = 0,
				whileDead = true,
				preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
				OnAccept = function(popup, confirmedGroup)
					confirmedGroup.allowAll = true
					Shared.UpdateItemList()
					Shared.RefreshPreview()
				end,
				OnCancel = function(popup, refusedGroup)
					local lines = {}
					for line in refusedGroup.list:gmatch("[^\r\n]+") do
						if not Shared.MatchesEverything(line) then
							lines[#lines+1] = line
						end
					end
					refusedGroup.list = table.concat(lines, "\n")
					if window:IsShown() and EasyMailListsSave.lastGroupShown == refusedGroup.name then
						ShowGroup(refusedGroup.name)
					end
				end,
			}
			local popup = StaticPopup_Show("EASYMAILLISTS_POPUP_ALL", group.name)
			if popup then
				popup.data = group
			end
		end

		Shared.UpdateItemList()
	end)

	-- dragging an item onto the editbox - has to affect the scroll box and input
	local function InputReceiveItem()
		local cursorType, info2, info3 = GetCursorInfo()
		if cursorType == "item" then
			AddItem(info3:match("%[(.+)]"), info2) -- for an item on the cursor, info2 is its ID
			ClearCursor()
		elseif cursorType == "merchant" then
			itemLink = GetMerchantItemLink(info2)
			if itemLink then
				AddItem(itemLink:match("%[(.+)]"), itemLink:match("|Hitem:(%d+)"))
				ClearCursor()
			end
		end
	end

	editboxScroll:SetScript("OnReceiveDrag", InputReceiveItem)
	local editboxScroll_OnMouseDown = editboxScroll:GetScript("OnMouseDown")
	editboxScroll:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then InputReceiveItem() end
		editboxScroll_OnMouseDown(self, button)
	end)

	editboxInput:SetScript("OnReceiveDrag", InputReceiveItem)
	editboxInput:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then InputReceiveItem() end
	end)

	-- shift-click an item (bags, bank, merchant, links...) to add it while the window is open
	hooksecurefunc("HandleModifiedItemClick", function(link)
		if not link or not listArea:IsVisible() or not IsModifiedClick("CHATLINK") then return end
		if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end -- chat is open: link there instead
		local name = link:match("|Hitem:.-%[(.+)]")
		if not name then return end
		AddItem(name, link:match("|Hitem:(%d+)"))
		-- shift-click on a stack also opens the split popup right after this hook, so close it
		C_Timer.After(0, function() if StackSplitFrame then StackSplitFrame:Hide() end end)
	end)

	--------------------------------------------------
	-- rows view: one row per item - [icon] name [rule] [x]
	--------------------------------------------------
	local ITEM_ROW_HEIGHT = 20
	local GetItemInfo = C_Item.GetItemInfo or GetItemInfo
	local GetItemIconByID = C_Item.GetItemIconByID or GetItemIcon

	local rowsBox = ScrollBox(listArea)
	rowsBox:SetPoint("TOPLEFT", 0, -26)
	rowsBox:SetPoint("BOTTOMRIGHT")
	rowsBox:EnableMouse(true)
	rowsBox:SetScript("OnReceiveDrag", InputReceiveItem)
	rowsBox:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then InputReceiveItem() end
	end)

	local textNoItems = Label(rowsBox, 12, colors.muted)
	textNoItems:SetPoint("CENTER")
	textNoItems:SetWidth(230)
	textNoItems:SetText("No items yet.\n\nShift-click an item, drag one here, or click Add from bags.")

	-- the rules a row can have: list prefix, menu text, the question for the amount, and the row label
	local RULES = {
		{ sign = nil, menu = "Send all",                              label = "Send all" },
		{ sign = "-", menu = "Keep stacks, send the rest...",         label = "Keep %d stacks", ask = "How many stacks of %s do you want to keep?" },
		{ sign = "+", menu = "Send only when I have at least...",     label = "When %d+",       ask = "Send %s only when you have at least how many?" },
		-- no menu text: "keep N items" isn't offered in the menu, but a =N line typed in the text view still works
		{ sign = "=", label = "Keep %d" },
	}
	local function RuleLabel(sign, amount)
		for _, rule in ipairs(RULES) do
			if rule.sign == sign then
				return (sign == "-" and amount == 1) and "Keep 1 stack" or rule.label:format(amount or 0)
			end
		end
	end

	-- asks for the amount of a rule, then rewrites the item's line
	StaticPopupDialogs["EASYMAILLISTS_POPUP_AMOUNT"] = {
		text = "%s",
		button1 = ACCEPT,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox = true,
		preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
		OnAccept = function(self, row)
			local amount = tonumber(_G[self:GetName().."EditBox"]:GetText())
			if amount and amount >= 1 then
				EditLine(row.key, row.sign .. math.floor(amount) .. " " .. row.item)
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local popup = self:GetParent()
			StaticPopupDialogs["EASYMAILLISTS_POPUP_AMOUNT"].OnAccept(popup, popup.data)
			popup:Hide()
		end,
		EditBoxOnEscapePressed = function(self)
			self:GetParent():Hide()
		end,
	}

	-- one menu shared by every row; ruleMenu.row is the row whose rule button opened it
	local ruleMenu = LibDD:Create_UIDropDownMenu("EasyMailListsRuleMenu", window)
	LibDD:UIDropDownMenu_Initialize(ruleMenu, function()
		local row = ruleMenu.row
		if not row then
			return -- the library also runs this once when the menu is created, before any row exists
		end
		for _, rule in ipairs(RULES) do
			if not rule.menu then
				break -- the rules after this one are only reachable from the text view
			end
			local info = LibDD:UIDropDownMenu_CreateInfo()
			info.text = rule.menu
			info.checked = rule.sign == row.sign
			info.func = function()
				if not rule.sign then
					EditLine(row.key, row.item)
					return
				end
				-- a copy, because the row itself is reused for other items when the list changes
				local data = { key = row.key, item = row.item, sign = rule.sign }
				local popup = StaticPopup_Show("EASYMAILLISTS_POPUP_AMOUNT", rule.ask:format(row.item))
				if popup then
					popup.data = data
					local editBox = _G[popup:GetName().."EditBox"]
					editBox:SetText(rule.sign == row.sign and row.amount or "")
					editBox:SetFocus()
				end
			end
			LibDD:UIDropDownMenu_AddButton(info)
		end
	end, "MENU")

	local itemRows = {}
	local function SetItemRow(i, line)
		local row = itemRows[i]
		if not row then
			row = CreateFrame("Frame", nil, rowsBox.content)
			row:SetSize(262, ITEM_ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 1, -(i - 1) * ITEM_ROW_HEIGHT - 3)
			row:EnableMouse(true)
			row:SetScript("OnReceiveDrag", InputReceiveItem)
			row:SetScript("OnMouseDown", function(self, button)
				if button == "LeftButton" then InputReceiveItem() end
			end)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(16, 16)
			row.icon:SetPoint("LEFT", 4, 0)
			row.remove = Button(row, "x", 18)
			row.remove:SetHeight(18)
			row.remove:SetPoint("RIGHT", -3, 0)
			row.remove:SetScript("OnClick", function() EditLine(row.key) end)
			row.rule = Button(row, "", 96)
			row.rule:SetHeight(18)
			row.rule:SetPoint("RIGHT", row.remove, "LEFT", -3, 0)
			row.rule.label:SetTextColor(unpack(colors.muted))
			row.rule:SetScript("OnClick", function(self)
				ruleMenu.row = row
				LibDD:ToggleDropDownMenu(1, nil, ruleMenu, self, 0, 0)
			end)
			row.name = Label(row, 12, colors.text)
			row.name:SetPoint("LEFT", 24, 0)
			row.name:SetPoint("RIGHT", row.rule, "LEFT", -4, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			Tip(row.rule, "When to send this item, and how much to keep. Click to change.")
			Tip(row.remove, "Remove this item from the list.")
			itemRows[i] = row
		end
		local sign, amount, item = ParseLine(line)
		row.key, row.sign, row.amount, row.item = item:lower(), sign, amount, item
		row.name:SetText(item)
		row.rule.label:SetText(RuleLabel(sign, tonumber(amount)))
		-- With a remembered ID the icon is always available. By name, the game only knows items
		-- it has seen this session, so the others get a question mark.
		local itemID = EasyMailListsSave.itemIDs[row.key]
		row.icon:SetTexture((item:find("*", 1, true) or Shared.IsGroup(item)) and "Interface\\Icons\\INV_Misc_Bag_10"
			or itemID and GetItemIconByID(itemID)
			or select(10, GetItemInfo(item))
			or "Interface\\Icons\\INV_Misc_QuestionMark")
		row:Show()
	end

	RefreshRows = function(lines)
		LibDD:CloseDropDownMenus()
		for i, line in ipairs(lines) do
			SetItemRow(i, line)
		end
		for i = #lines + 1, #itemRows do
			itemRows[i]:Hide()
		end
		rowsBox.content:SetHeight(#lines * ITEM_ROW_HEIGHT + 6)
		rowsBox:ScrollBy(0)
		textNoItems:SetShown(#lines == 0)
	end

	--------------------------------------------------
	-- bags view: an icon for every unbound item in the bags that isn't on this list yet
	--------------------------------------------------
	local BAG_ICON, BAG_COLUMNS = 32, 8

	local bagsBox = ScrollBox(listArea)
	bagsBox:SetPoint("TOPLEFT", 0, -26)
	bagsBox:SetPoint("BOTTOMRIGHT")

	local textNoBagItems = Label(bagsBox, 12, colors.muted)
	textNoBagItems:SetPoint("CENTER")
	textNoBagItems:SetWidth(230)
	textNoBagItems:SetText("Every unbound item in your bags is already on this list.")

	local bagButtons = {}
	RefreshBags = function()
		local group = CurrentGroup()
		if not group then
			return
		end
		local seen = {} -- lowercase names that are on the list or already have a button
		for line in group.list:gmatch("[^\r\n]+") do
			seen[LineKey(line)] = true
		end

		local count = 0
		for bag=0,5 do
			for slot=1,C_Container.GetContainerNumSlots(bag) do
				local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
				local key = itemInfo and not itemInfo.isBound and itemInfo.itemName:lower()
				if key and not seen[key] then
					seen[key] = true
					count = count + 1
					local button = bagButtons[count]
					if not button then
						button = CreateFrame("Button", nil, bagsBox.content)
						button:SetSize(BAG_ICON - 2, BAG_ICON - 2)
						button:SetPoint("TOPLEFT", 4 + ((count - 1) % BAG_COLUMNS) * BAG_ICON, -4 - math.floor((count - 1) / BAG_COLUMNS) * BAG_ICON)
						button.icon = button:CreateTexture(nil, "ARTWORK")
						button.icon:SetAllPoints()
						Fill(button, "HIGHLIGHT", colors.accent, 0):SetAlpha(0.3)
						button:SetScript("OnClick", function(self) AddItem(self.name, self.itemID) end)
						button:SetScript("OnEnter", function(self)
							GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
							GameTooltip:SetBagItem(self.bag, self.slot)
							GameTooltip:Show()
						end)
						button:SetScript("OnLeave", function() GameTooltip:Hide() end)
						bagButtons[count] = button
					end
					button.name, button.bag, button.slot, button.itemID = itemInfo.itemName, bag, slot, itemInfo.itemID
					button.icon:SetTexture(itemInfo.iconFileID)
					button:Show()
				end
			end
		end
		for i = count + 1, #bagButtons do
			bagButtons[i]:Hide()
		end
		bagsBox.content:SetHeight(math.ceil(count / BAG_COLUMNS) * BAG_ICON + 8)
		bagsBox:ScrollBy(0)
		textNoBagItems:SetShown(count == 0)
	end

	--------------------------------------------------
	-- switching between the three views
	--------------------------------------------------
	local function SetMode(newMode)
		mode = newMode
		editbox:SetShown(mode == "text")
		rowsBox:SetShown(mode == "rows")
		bagsBox:SetShown(mode == "bags")
		buttonMode.label:SetText(EasyMailListsSave.textMode and "Rows" or "Text") -- the view it switches to
		buttonAddBags.label:SetText(mode == "bags" and "Done" or "Add from bags")
		if mode == "bags" then
			RefreshBags()
		end
	end
	window.SetMode = SetMode

	buttonMode:SetScript("OnClick", function()
		editboxInput:ClearFocus() -- saves the text view
		EasyMailListsSave.textMode = not EasyMailListsSave.textMode or nil
		SetMode(EasyMailListsSave.textMode and "text" or "rows")
		ShowGroup(EasyMailListsSave.lastGroupShown) -- the other view now shows the saved list
	end)

	--------------------------------------------------
	-- patterns: ready-made * lines for common groups of items
	--------------------------------------------------
	-- ponytail: these match English item names. Use item classes if other languages matter.
	-- { menu text, description, lines to add }. Without lines, the menu text itself is the line.
	-- A * line is only used where nothing unwanted shares the name: "* Stone" also caught
	-- sharpening stones and "* Cloth" catches bolts, so those two add exact names instead.
	local buttonPatterns = Button(listArea, "Patterns", 66)
	buttonPatterns:SetPoint("LEFT", buttonAddBags, "RIGHT", 4, 0)
	local patternMenu = LibDD:Create_UIDropDownMenu("EasyMailListsPatternMenu", window)
	LibDD:UIDropDownMenu_Initialize(patternMenu, function()
		for _, pattern in ipairs(Shared.PATTERNS) do
			local info = LibDD:UIDropDownMenu_CreateInfo()
			info.text = pattern[1] .. "  |cff999999" .. pattern[2] .. "|r"
			info.notCheckable = true
			info.func = function()
				AddItem(pattern[1])
				-- the new line (a group or a * line) now covers its items, so plain lines for them are
				-- duplicates (lines with a rule stay)
				local group = CurrentGroup()
				if group then
					local members = {}
					for _, name in ipairs(pattern[3] or {}) do members[name:lower()] = true end
					local wildcard = pattern[4] and "^" .. pattern[4]:lower():gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
					local lines = {}
					for line in group.list:gmatch("[^\r\n]+") do
						local sign, _, item = ParseLine(line)
						local lower = item:lower()
						-- the old literal line ("* Ore") is a duplicate of the new one too; the new line itself stays
						if sign or lower == pattern[1]:lower() or not (members[lower] or wildcard and lower:find(wildcard)) then
							lines[#lines+1] = line
						end
					end
					group.list = table.concat(lines, "\n")
					Shared.UpdateItemList()
					ShowGroup(group.name)
				end
			end
			LibDD:UIDropDownMenu_AddButton(info)
		end
	end, "MENU")
	buttonPatterns:SetScript("OnClick", function(self)
		LibDD:ToggleDropDownMenu(1, nil, patternMenu, self, 0, 0)
	end)

	buttonAddBags:SetScript("OnClick", function()
		editboxInput:ClearFocus()
		SetMode(mode == "bags" and (EasyMailListsSave.textMode and "text" or "rows") or "bags")
	end)

	--------------------------------------------------
	-- GUI scripts - buttons
	--------------------------------------------------
	-- new group button - show a popup to name and create a new group
	local function AskRecipientName()
		-- create the dialog if it doesn't exist yet
		if not StaticPopupDialogs["EASYMAILLISTS_POPUP_NAME"] then
			StaticPopupDialogs["EASYMAILLISTS_POPUP_NAME"] = {
				text = "Enter the recipient's name:",
				button1 = ACCEPT,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				hasEditBox = true,
				preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
				OnShow = function(self)
					_G[self:GetName().."EditBox"]:SetText("")
					_G[self:GetName().."EditBox"]:SetFocus()
				end,
				OnAccept = function(self)
					local name = _G[self:GetName().."EditBox"]:GetText()
					name = name:gsub("(%a)(%w*)", function(first,rest) return first:upper() .. rest:lower() end) -- capitalize
					if AddGroup(name) then
						ShowGroup(name)
					end
				end,
				EditBoxOnEnterPressed = function(self)
					StaticPopupDialogs["EASYMAILLISTS_POPUP_NAME"].OnAccept(self:GetParent())
					self:GetParent():Hide()
				end,
				EditBoxOnEscapePressed = function(self)
					self:GetParent():Hide()
				end,
			}
		end
		StaticPopup_Show("EASYMAILLISTS_POPUP_NAME")
	end

	-- your characters that aren't recipients yet, sorted by name
	local function CharactersToAdd()
		local names = {}
		for name in pairs(EasyMailListsSave.characters) do
			if not GetGroupSettings(name) then
				names[#names+1] = name
			end
		end
		table.sort(names)
		return names
	end

	-- the New button lists your own characters, so their names and factions are never typed wrong
	local newMenu = LibDD:Create_UIDropDownMenu("EasyMailListsNewMenu", window)
	LibDD:UIDropDownMenu_Initialize(newMenu, function()
		local realm = GetRealmName()
		for _, name in ipairs(CharactersToAdd()) do
			local character = EasyMailListsSave.characters[name]
			local info = LibDD:UIDropDownMenu_CreateInfo()
			info.text = name .. (character.realm ~= realm and " (" .. tostring(character.realm) .. ")" or "")
			info.notCheckable = true
			info.func = function()
				if AddGroup(name) then
					GetGroupSettings(name).faction = character.faction
					Shared.UpdateItemList()
					ShowGroup(name)
				end
			end
			LibDD:UIDropDownMenu_AddButton(info)
		end
		local info = LibDD:UIDropDownMenu_CreateInfo()
		info.text = "Type a name..."
		info.notCheckable = true
		info.func = AskRecipientName
		LibDD:UIDropDownMenu_AddButton(info)
	end, "MENU")

	buttonNew:SetScript("OnClick", function(self)
		if #CharactersToAdd() == 0 then
			AskRecipientName() -- nothing to pick from
		else
			LibDD:ToggleDropDownMenu(1, nil, newMenu, self, 0, 0)
		end
	end)

	-- rename button - show a popup to rename the currently shown group
	buttonRename:SetScript("OnClick", function()
		if not GetGroupSettings(EasyMailListsSave.lastGroupShown) then
			return
		end
		-- create the dialog if it doesn't exist yet
		if not StaticPopupDialogs["EASYMAILLISTS_POPUP_RENAME"] then
			StaticPopupDialogs["EASYMAILLISTS_POPUP_RENAME"] = {
				text = "Enter a new name to be the recipient:",
				button1 = ACCEPT,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				hasEditBox = true,
				preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
				OnShow = function(self)
					_G[self:GetName().."EditBox"]:SetText(EasyMailListsSave.lastGroupShown)
					_G[self:GetName().."EditBox"]:SetFocus()
				end,
				OnAccept = function(self)
					local name = _G[self:GetName().."EditBox"]:GetText()
					name = name:gsub("(%a)(%w*)", function(first,rest) return first:upper() .. rest:lower() end) -- capitalize
					if RenameGroup(EasyMailListsSave.lastGroupShown, name) then
						Shared.UpdateItemList()
						ShowGroup(name)
					end
				end,
				EditBoxOnEnterPressed = function(self)
					StaticPopupDialogs["EASYMAILLISTS_POPUP_RENAME"].OnAccept(self:GetParent())
					self:GetParent():Hide()
				end,
				EditBoxOnEscapePressed = function(self)
					self:GetParent():Hide()
				end,
			}
		end
		StaticPopup_Show("EASYMAILLISTS_POPUP_RENAME")
	end)

	-- delete button - show confirmation popup to delete the currently shown group
	buttonDelete:SetScript("OnClick", function()
		if not GetGroupSettings(EasyMailListsSave.lastGroupShown) then
			return
		end
		-- create the dialog if it doesn't exist yet
		if not StaticPopupDialogs["EASYMAILLISTS_POPUP_DELETE"] then
			StaticPopupDialogs["EASYMAILLISTS_POPUP_DELETE"] = {
				text = "Really delete this recipient?",
				button1 = ACCEPT,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				hasEditBox = false,
				preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
				OnAccept = function()
					if RemoveGroup(EasyMailListsSave.lastGroupShown) then
						Shared.UpdateItemList()
						ShowGroup(EasyMailListsSave.groups[1] and EasyMailListsSave.groups[1].name or "")
					end
				end,
			}
		end
		StaticPopup_Show("EASYMAILLISTS_POPUP_DELETE")
	end)

	--------------------------------------------------
	-- GUI scripts - faction
	--------------------------------------------------
	function buttonFaction:SetFactionIcon(faction)
		local factionIcon
		if faction == "Horde" then
			factionIcon = "Interface\\COMMON\\icon-horde"
		elseif faction == "Alliance" then
			factionIcon = "Interface\\COMMON\\icon-alliance"
		else
			factionIcon = "Interface\\CURSOR\\FishingCursor"
		end
		self:SetNormalTexture(factionIcon)
	end

	buttonFaction:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText("Click to toggle this character's faction.")
		GameTooltip:Show()
	end)
	buttonFaction:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	buttonFaction:SetScript("OnClick", function(self)
		local name = EasyMailListsSave.lastGroupShown
		local group = name and GetGroupSettings(name)
		if group then
			group.faction = group.faction == "Horde" and "Alliance" or "Horde"
			self:SetFactionIcon(group.faction)
			Shared.UpdateItemList()
		end
	end)

	--------------------------------------------------
	-- GUI scripts - BoE options
	--------------------------------------------------
	checkboxSendEquipmentHere:SetScript("OnClick", function(this)
		local name = EasyMailListsSave.lastGroupShown
		local group = name and GetGroupSettings(name)
		if group then
			EasyMailListsSave.sendEquipmentHere = this:GetChecked() and name or nil
		end
	end)

	checkboxDoNotSendEquipment:SetScript("OnClick", function(this)
		local name = EasyMailListsSave.lastGroupShown
		local group = name and GetGroupSettings(name)
		if group then
			group.doNotSendEquipment = this:GetChecked() and true or nil
		end
	end)

	--------------------------------------------------
	-- GUI scripts - showing window
	--------------------------------------------------
	--------------------------------------------------
	-- hints - after every script above, because Tip adds to the scripts a control already has
	--------------------------------------------------
	Tip(tabSend, "What will be mailed. It fills in when you open a mailbox.")
	Tip(tabLists, "Choose who gets which items.")
	Tip(buttonTheme, "Change the look of this window. The change applies after a reload.")
	Tip(buttonGroup, "The recipient whose list is shown. Click to switch.")
	Tip(buttonNew, "Add a recipient: one of your characters, or a name you type.")
	Tip(buttonRename, "Change this recipient's name.")
	Tip(buttonDelete, "Remove this recipient and their list.")
	Tip(checkboxSendEquipmentHere, "Mail unbound weapons and armor from your other characters to this one. Items on a list follow the list instead.")
	Tip(checkboxDoNotSendEquipment, "When you play this character, its unbound gear stays in its bags.")
	Tip(buttonAddBags, "Pick items from your bags.")
	Tip(buttonPatterns, "Add a ready-made group of items.")
	Tip(buttonMode, "Switch between rows and plain text.")
	Tip(buttonSend, "Mail the items listed above.")
	Tip(checkboxEnabled, "Auto-send: mail everything as soon as you open a mailbox, without clicking Send.")
	Tip(checkboxRequireShift, "Auto-send only when you hold Shift while you open the mailbox.")

	window:SetScript("OnShow", function()
		window.SetMode(EasyMailListsSave.textMode and "text" or "rows")
		buttonQuality:Update()
		checkboxEnabled:SetChecked(EasyMailListsSave.enabled)
		checkboxRequireShift:SetChecked(EasyMailListsSave.requireShift)
		ShowGroup((GetGroupSettings(EasyMailListsSave.lastGroupShown) and EasyMailListsSave.lastGroupShown) or
			(EasyMailListsSave.groups[1] and EasyMailListsSave.groups[1].name) or "")
		window.ShowTab(mailOpen or false) -- the preview at the mailbox, the lists anywhere else
	end)

	-- only hide after everything is set up and placed
	window:Hide()
	return
end

----------------------------------------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------------------------------------
_G.SLASH_EASYMAILLISTS1 = "/easymail"
_G.SLASH_EASYMAILLISTS2 = "/eml"
function SlashCmdList.EASYMAILLISTS(input)
	if Shared.paused then
		DEFAULT_CHAT_FRAME:AddMessage("EasyMail Lists: paused. Disable Plain AutoMail in the addon list, then type /reload.", 1, 1, 0)
		return
	end
	Shared.ToggleWindow()
end

----------------------------------------------------------------------------------------------------
-- Docking - the window sits to the right of the mailbox while the mailbox is open
----------------------------------------------------------------------------------------------------
-- ponytail: fixed gap from the mailbox's top right corner. Raise DOCK_X if another addon
-- puts buttons on the right side of the mail frame.
local DOCK_X, DOCK_Y = 4, 0

function Shared.Redock()
	if docked and window and window:IsShown() then
		Shared.DockWindow()
	end
end

function Shared.DockWindow()
	-- PathForever Mail's "Send to..." panel uses the same spot, so sit to the right of it
	local side = PathForeverMailFrame
	if side and not side.autoMailHooked then
		side.autoMailHooked = true
		side:HookScript("OnShow", Shared.Redock)
		side:HookScript("OnHide", Shared.Redock)
	end
	local anchor = MailFrame
	if OpenMailFrame and OpenMailFrame:IsShown() then
		anchor = OpenMailFrame
	elseif side and side:IsShown() then
		anchor = side
	end
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", anchor, "TOPRIGHT", DOCK_X, DOCK_Y)
	docked = true
end

function Shared.ShowWindow()
	CreateGUI()
	if mailOpen then
		Shared.DockWindow()
	elseif docked then
		window:ClearAllPoints()
		window:SetPoint("CENTER")
		docked = false
	end
	window:Show()
end

-- show or hide the window; at the mailbox the choice is remembered for the next visit
function Shared.ToggleWindow()
	if window and window:IsShown() then
		window:Hide()
	else
		Shared.ShowWindow()
	end
	if mailOpen then
		EasyMailListsSave.showAtMailbox = window:IsShown()
	end
end

local function MailboxClosed()
	mailOpen = false
	wipe(skipped)
	if window then
		window:Hide() -- also when it wasn't docked, for example if it was open before the mailbox
	end
end

local buttonToggle -- small button above the mailbox's top right corner
local mailEvents = CreateFrame("Frame")
mailEvents:RegisterEvent("MAIL_SHOW")
mailEvents:RegisterEvent("MAIL_CLOSED")
mailEvents:RegisterEvent("BAG_UPDATE_DELAYED")
mailEvents:SetScript("OnEvent", function(self, event)
	if Shared.paused then return end
	if event == "MAIL_SHOW" then
		-- MAIL_SHOW can arrive before the game shows the mail frame, so mailOpen is tracked here
		-- instead of asking MailFrame:IsShown()
		mailOpen = true
		if not buttonToggle then
			ApplySkin()
			buttonToggle = Button(MailFrame, "EasyMail", 70)
			buttonToggle:SetPoint("BOTTOMRIGHT", MailFrame, "TOPRIGHT", 0, 2)
			buttonToggle:SetScript("OnClick", Shared.ToggleWindow)
			-- MAIL_CLOSED doesn't cover every way the mail frame can go away, so watch the frame too
			MailFrame:HookScript("OnHide", MailboxClosed)
		end
		-- showAtMailbox is nil until the window is closed at the mailbox, so it shows by default
		if EasyMailListsSave.showAtMailbox ~= false then
			Shared.ShowWindow()
			window.ShowTab(true) -- the preview, also when the window was already open
		end
	elseif event == "MAIL_CLOSED" then
		MailboxClosed()
	elseif mailOpen and Shared.RefreshPreview then
		Shared.RefreshPreview() -- bags changed while the mailbox is open
	end
end)
