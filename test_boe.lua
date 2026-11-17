-- Run: lua test_boe.lua   (checks the BoE mailing rules with a stubbed game API)
local frame
local noop = function() end
function CreateFrame() -- the first frame created is the addon's mail frame
	local new = { Hide = noop, Show = noop, SetScript = noop, RegisterEvent = noop }
	frame = frame or new
	return new
end
function GetUnitName() return "Me" end
function UnitFactionGroup() return "Horde" end

-- slot = { name, classID, quality, isBound }
local bag = {
	{ "Green Sword",   2, 2, false }, -- BoE weapon: mail
	{ "Kept Robe",     4, 3, false }, -- on my own list: keep
	{ "Bound Helm",    4, 4, true  }, -- soulbound: keep
	{ "White Shield",  4, 1, false }, -- below green: keep
	{ "Linen Cloth",   7, 1, false }, -- not equipment: keep
	{ "Listed Dagger", 2, 2, false }, -- on Alt's list: mail to Alt, not Bank
}
C_Container = {
	GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end,
	GetContainerItemInfo = function(_, s)
		local i = bag[s]
		return { itemName = i[1], itemID = s, quality = i[3], isBound = i[4], stackCount = i[5] or 1 }
	end,
}
C_Item = {
	GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, bag[id][2], bag[id][6] end, -- slot[6]: subclass
	GetItemCount = function() return 1 end,
}

local Shared = {}
local groups = {
	{ name = "Bank", faction = "Horde", list = "" },
	{ name = "Me",   faction = "Horde", list = "" },
}
function Shared.GetGroupSettings(name)
	for _, g in ipairs(groups) do if g.name == name then return g end end
end
EasyMailListsSave = { groups = groups, sendEquipmentHere = "Bank", itemIDs = {} }
assert(loadfile("EasyMailLists/EasyMailLists.lua"))("EasyMailLists", Shared)
Shared.itemList = {
	["kept robe"]     = { recipient = "Me" },
	["listed dagger"] = { recipient = "Alt" },
}

-- the plan as [recipient] = { {bag, slot}, ... }, plus the kept list
local function build()
	local send, kept = Shared.BuildPlan()
	local list = {}
	for _, entry in ipairs(send) do
		list[entry.recipient] = list[entry.recipient] or {}
		for _, slot in ipairs(entry.slots) do table.insert(list[entry.recipient], slot) end
	end
	return list, kept, send
end

local list = build()
assert(#list.Bank == 1 and list.Bank[1][2] == 1, "only the green sword goes to Bank")
assert(#list.Alt == 1 and list.Alt[1][2] == 6, "listed dagger goes to Alt")

groups[2].doNotSendEquipment = true
assert(build().Bank == nil, "'do not send BoE' keeps equipment")
groups[2].doNotSendEquipment = nil

groups[1].faction = "Alliance"
assert(build().Bank == nil, "no BoE mail to the other faction")
groups[1].faction = "Horde"

EasyMailListsSave.sendEquipmentHere = nil
assert(build().Bank == nil, "no BoE mail when nobody is selected")

print("BoE tests ok")

-- wildcards: load the real list parser from Settings.lua
LibStub = { GetLibrary = function() return {} end }
SlashCmdList = {}
assert(loadfile("EasyMailLists/Settings.lua"))("EasyMailLists", Shared)
bag[1][1] = "Raw Sagefish"            -- matches "raw *": mail
bag[2][1] = "Raw Spotted Yellowtail"  -- matches "raw *": mail
bag[4][1] = "Strawberry"              -- contains "raw" but doesn't start with "Raw ": keep
bag[6][1] = "Raw Whitescale Salmon"   -- exact line on my own list wins: keep
groups[1].list = "Raw *\n-1 Linen*"   -- Linen Cloth: one stack, keep 1 stack: keep
groups[2].list = "raw whitescale salmon\n17 Pound Catfish\n+20 Runecloth"
Shared.UpdateItemList()
assert(Shared.itemList["17 pound catfish"], "leading digits without a sign are part of the name")
assert(Shared.itemList["runecloth"].minimum == 20, "+20 is a minimum")
list = build()
assert(#list.Bank == 2 and list.Bank[1][2] == 1 and list.Bank[2][2] == 2, "only the two raw fish go to Bank")
assert(list.Me == nil, "nothing is mailed to myself")

print("wildcard tests ok")

-- preview: rules in plain words, and reasons for what is kept
local _, kept, send = build()
assert(send[1].rule == "Raw *" and send[1].count == 1, "the preview names the wildcard line")
assert(#kept == 1 and kept[1].reason == "keeping 1 stack", "linen cloth is kept with a reason")
C_Item.GetItemCount = function() return 5 end
groups[1].list = "+20 Raw Sagefish"
Shared.UpdateItemList()
list, kept = build()
assert(list.Bank == nil and kept[1].reason == "fewer than 20", "below the minimum is kept with a reason")

-- a line with only * does nothing until it is confirmed
groups[1].list = "*"
Shared.UpdateItemList()
assert(build().Bank == nil, "* alone is ignored")
groups[1].allowAll = true
Shared.UpdateItemList()
assert(#build().Bank == 4, "confirmed * mails every unbound item that isn't on my own list")

print("preview tests ok")

-- "=30": keep 30 items. Stacks of 20, 20, and 5: keep one stack whole, split one, send the rest.
bag[1] = { "Raw Sagefish", 7, 1, false, 20 }
bag[2] = { "Raw Sagefish", 7, 1, false, 20 }
bag[3] = { "Raw Sagefish", 7, 1, false, 5 }
groups[1].list = "=30 Raw Sagefish"
groups[1].allowAll = nil
Shared.UpdateItemList()
_, kept, send = build()
assert(#send == 1 and send[1].count == 15 and send[1].rule == "keeps 30", "15 of 45 are sent")
assert(send[1].slots[1][2] == 2 and send[1].slots[1].amount == 10, "10 are split off the second stack")
assert(send[1].slots[2][2] == 3 and send[1].slots[2].amount == nil, "the stack of 5 is sent whole")
assert(kept[1].count == 30 and kept[1].reason == "keeping 30", "30 are kept")
groups[1].list = "=50 Raw Sagefish"
Shared.UpdateItemList()
_, kept, send = build()
assert(#send == 0 and kept[1].count == 45, "fewer than the amount to keep: nothing is sent")

print("keep N items tests ok")

-- item IDs: seeing a listed item in the bags remembers its ID, and the ID then matches the
-- item even under another name (the item ID in this test is the bag slot number)
groups[1].list = "Linen Cloth"
Shared.UpdateItemList()
assert(#build().Bank == 1 and EasyMailListsSave.itemIDs["linen cloth"] == 5, "the ID of linen cloth is learned")
Shared.UpdateItemList()
bag[5][1] = "Leinenstoff"
list = build()
assert(list.Bank and list.Bank[1][2] == 5, "the same item under another name still matches by ID")

print("item ID tests ok")

-- a group line: "Flowers" sends every herb in the group, with the rule of that line
bag[1][1], bag[2][1] = "Peacebloom", "Stranglevine"
groups[1].list = "Flowers"
Shared.UpdateItemList()
list, _, send = build()
assert(list.Bank and #list.Bank == 2 and send[1].rule == "Flowers", "a Flowers line sends the herbs")
assert(Shared.IsGroup("flowers") and not Shared.IsGroup("Runecloth"), "IsGroup knows the groups")

-- a line for one item beats the group in either order, and an exact line beats a wildcard
for _, text in ipairs({ "Flowers\n-1 Peacebloom", "-1 Peacebloom\nFlowers" }) do
	groups[1].list = text
	Shared.UpdateItemList()
	assert(Shared.itemList["peacebloom"].keepStacks == 1 and Shared.itemList["stranglevine"].keepStacks == false, "the one-item line wins: " .. text)
end
groups[1].list = "Raw *\n-1 Raw Sagefish"
Shared.UpdateItemList()
assert(Shared.itemList["raw sagefish"].keepStacks == 1, "an exact line is checked before the wildcard")

-- Cooking also stands for the line "Raw *", and the menu name has no asterisk
groups[1].list = "Cooking\n-1 Raw Sagefish"
Shared.UpdateItemList()
assert(#Shared.wildcards == 1 and Shared.wildcards[1].info.wildcard == "Cooking", "Cooking also has the Raw * line")
assert(Shared.IsGroup("cooking") and Shared.IsGroup("Ore"), "wildcard entries count as groups")

-- Cooking also takes any Trade Goods meat that isn't named in the group; a named line still wins
bag[1] = { "Unlisted Meat", 7, 1, false, 1, 8 }
bag[2] = { "Raptor Flesh", 7, 1, false, 1, 8 }
bag[3] = { "Some Herb", 7, 1, false, 1, 9 }
groups[1].list = "Cooking\n-1 Raptor Flesh"
Shared.UpdateItemList()
list, kept = build()
assert(#list.Bank == 1 and list.Bank[1][2] == 1, "only the unnamed meat is sent by type; the herb isn't on the list")
assert(kept[1].reason == "keeping 1 stack", "-1 Raptor Flesh still wins over the group")

print("group tests ok")

-- the one-time fix replaces "* Stone" and nothing else, and runs only once
groups[1].list = "Linen Cloth\n* Stone\nRaw *"
Shared.FixStonePattern()
assert(groups[1].list == "Linen Cloth\nRough Stone\nCoarse Stone\nHeavy Stone\nSolid Stone\nDense Stone\nRaw *", groups[1].list)
groups[1].list = "* Stone"
Shared.FixStonePattern()
assert(groups[1].list == "* Stone", "a * Stone line added later on purpose is left alone")

print("stone fix tests ok")
