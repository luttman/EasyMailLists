local addonName, Shared = ...

Shared.itemList = {} -- { { ["recipient"], ["minimum"], ["keepStacks"] }, ... }
Shared.wildcards = {} -- list lines containing *: { { pattern, info }, ... } where info is like an itemList entry

Shared.idList = {} -- [itemID] = itemList entry, for the list items whose ID is known

local AutoMail = CreateFrame("frame")
AutoMail:Hide()

----------------------------------------------------------------------------------------------------
-- Work out what would be mailed right now - the preview and the sending both use this
----------------------------------------------------------------------------------------------------
-- a list rule in plain words, shown next to the item in the preview
local function RuleText(mailInfo)
	local parts = {}
	if mailInfo.wildcard then
		parts[#parts+1] = mailInfo.wildcard
	end
	if mailInfo.minimum then
		parts[#parts+1] = "when " .. mailInfo.minimum .. " or more"
	end
	if mailInfo.keepStacks then
		parts[#parts+1] = "keeps " .. mailInfo.keepStacks .. (mailInfo.keepStacks == 1 and " stack" or " stacks")
	end
	if mailInfo.keepItems then
		parts[#parts+1] = "keeps " .. mailInfo.keepItems
	end
	return table.concat(parts, ", ")
end

-- the list rule for an item: exact names win, then the first matching wildcard line
-- The ID also finds the rule when the name on the list is spelled as in another game language.
local function FindMailInfo(lowercaseName, itemID, classID, subclassID)
	local mailInfo = Shared.itemList[lowercaseName]
	if mailInfo then
		EasyMailListsSave.itemIDs[lowercaseName] = itemID -- remembered for the row icons and for ID matching
		return mailInfo
	end
	if Shared.idList[itemID] then
		return Shared.idList[itemID]
	end
	for _, wildcard in ipairs(Shared.wildcards) do
		if lowercaseName:find(wildcard.pattern) then
			return wildcard.info
		end
	end
	-- last: groups like Meat and Flowers also take every item of their type (Trade Goods: meat, herb)
	return Shared.classRules and classID and subclassID and Shared.classRules[classID .. "/" .. subclassID]
end

-- returns two lists, each with one entry per item:
--   send: { key, recipient, link, icon, count, rule, slots = { {bag, slot}, ... } } sorted by recipient and name
--         a slot with an amount field sends only that many from the stack, which needs a split first
--   kept: { link, icon, count, reason } for items that are on a list but stay in the bags
function Shared.BuildPlan()
	local localPlayerName = GetUnitName("player")

	-- BoE options: who gets unbound equipment, and whether this character keeps theirs
	local boeRecipient = EasyMailListsSave.sendEquipmentHere
	local boeGroup = boeRecipient and Shared.GetGroupSettings(boeRecipient)
	if not boeGroup or boeGroup.faction ~= (UnitFactionGroup("player")) then
		boeRecipient = nil -- nobody selected, or they're on the other faction
	end
	local ownGroup = Shared.GetGroupSettings(localPlayerName)
	local keepBoeItems = ownGroup and ownGroup.doNotSendEquipment

	local send, kept, index = {}, {}, {}
	-- add one bag slot to the entry for its item, creating the entry the first time
	-- amount: only part of the stack counts (the rest of it goes to the other list)
	local function Add(list, key, itemInfo, bag, slot, amount)
		local entry = index[key]
		if not entry then
			entry = { key = key, link = itemInfo.hyperlink, icon = itemInfo.iconFileID, count = 0, slots = {} }
			index[key] = entry
			list[#list+1] = entry
		end
		entry.count = entry.count + (amount or itemInfo.stackCount or 1)
		entry.slots[#entry.slots+1] = { bag, slot, amount = amount }
		return entry
	end
	local function AddSend(recipient, rule, itemInfo, bag, slot, amount)
		local entry = Add(send, recipient .. "\n" .. itemInfo.itemName:lower(), itemInfo, bag, slot, amount)
		entry.recipient, entry.rule = recipient, rule
	end
	local function AddKept(reason, itemInfo, bag, slot, amount)
		Add(kept, "kept\n" .. itemInfo.itemName:lower(), itemInfo, bag, slot, amount).reason = reason
	end

	local stackGroups = {} -- [itemName] = { mailInfo = <rule>, {bag, slot, count, itemInfo}, ... }

	for bag=0,5 do
		for slot=1,C_Container.GetContainerNumSlots(bag) do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo and not itemInfo.isBound then
				local lowercaseName = itemInfo.itemName:lower()
				local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemInfo.itemID)
				local mailInfo = FindMailInfo(lowercaseName, itemInfo.itemID, classID, subclassID)

				if mailInfo then
					if mailInfo.recipient == localPlayerName then
						-- on this character's own list: it stays here, which also protects it from BoE mailing
					elseif mailInfo.minimum and C_Item.GetItemCount(itemInfo.itemID, true) < mailInfo.minimum then
						AddKept("fewer than " .. mailInfo.minimum, itemInfo, bag, slot)
					elseif mailInfo.keepStacks or mailInfo.keepItems then
						local group = stackGroups[lowercaseName]
						if not group then
							group = { mailInfo = mailInfo }
							stackGroups[lowercaseName] = group
						end
						group[#group+1] = { bag=bag, slot=slot, count=itemInfo.stackCount, itemInfo=itemInfo }
					else
						AddSend(mailInfo.recipient, RuleText(mailInfo), itemInfo, bag, slot)
					end
				elseif boeRecipient
				and not keepBoeItems
				and boeRecipient ~= localPlayerName
				and (classID == 2 or classID == 4) -- weapon or armor, works on any client language
				and itemInfo.quality >= (EasyMailListsSave.gearQuality or 2) then
					AddSend(boeRecipient, "unbound gear", itemInfo, bag, slot)
				end
			end
		end
	end

	-- Keep the largest stacks and if equal, the first slots
	for itemName, group in pairs(stackGroups) do
		local mailInfo = group.mailInfo
		table.sort(group, function(a, b)
			if a.count ~= b.count then return a.count > b.count end
			if a.bag ~= b.bag then return a.bag < b.bag end
			return a.slot < b.slot
		end)
		local toKeep = mailInfo.keepItems -- items still to keep, for the "keep N items" rule
		for i, stack in ipairs(group) do
			if toKeep then
				local reason = "keeping " .. mailInfo.keepItems
				if stack.count <= toKeep then
					AddKept(reason, stack.itemInfo, stack.bag, stack.slot)
					toKeep = toKeep - stack.count
				elseif toKeep > 0 then
					-- this stack covers the rest of what to keep: split it and send the other part
					AddKept(reason, stack.itemInfo, stack.bag, stack.slot, toKeep)
					AddSend(mailInfo.recipient, RuleText(mailInfo), stack.itemInfo, stack.bag, stack.slot, stack.count - toKeep)
					toKeep = 0
				else
					AddSend(mailInfo.recipient, RuleText(mailInfo), stack.itemInfo, stack.bag, stack.slot)
				end
			elseif i <= mailInfo.keepStacks then
				AddKept("keeping " .. mailInfo.keepStacks .. (mailInfo.keepStacks == 1 and " stack" or " stacks"), stack.itemInfo, stack.bag, stack.slot)
			else
				AddSend(mailInfo.recipient, RuleText(mailInfo), stack.itemInfo, stack.bag, stack.slot)
			end
		end
	end

	table.sort(send, function(a, b) return a.key < b.key end) -- the key starts with the recipient
	table.sort(kept, function(a, b) return a.key < b.key end)
	return send, kept
end

----------------------------------------------------------------------------------------------------
-- Start sending
----------------------------------------------------------------------------------------------------
AutoMail.mailingList = nil -- [recipient] = { {bag, slot}, ... } still to send

local function CountAndLink(entry)
	return (entry.count > 1 and entry.count .. "x" or "") .. (entry.link or "?")
end

-- mail everything in the current plan except the entries in skipped ([entry.key] = true)
-- returns true if there is something to send
function Shared.StartSending(skipped)
	if AutoMail.sendingMail then
		return false
	end

	local send, kept = Shared.BuildPlan()
	local mailingList, keptText
	local splits = {}
	for _, entry in ipairs(send) do
		if skipped and skipped[entry.key] then
			keptText = (keptText and keptText .. ", " or "") .. CountAndLink(entry) .. " (skipped)"
		else
			mailingList = mailingList or {}
			mailingList[entry.recipient] = mailingList[entry.recipient] or {}
			for _, itemLoc in ipairs(entry.slots) do
				table.insert(mailingList[entry.recipient], itemLoc)
				if itemLoc.amount then
					table.insert(splits, itemLoc)
				end
			end
		end
	end
	if not mailingList then
		return false
	end

	for _, entry in ipairs(kept) do
		keptText = (keptText and keptText .. ", " or "") .. CountAndLink(entry) .. " (" .. entry.reason .. ")"
	end
	if keptText then
		DEFAULT_CHAT_FRAME:AddMessage("EasyMail Lists kept: " .. keptText, 1, 1, 0)
	end

	AutoMail.mailingList = mailingList
	AutoMail.splits = splits
	AutoMail.sendingMail = true
	AutoMail:Show() -- start OnUpdate
	return true
end

function Shared.IsSending()
	return AutoMail.sendingMail or false
end

-- sending is over: finished, failed, or the mailbox closed
function AutoMail:Finish()
	self:Hide()
	self.nextMail = nil
	self.mailingList = nil
	self.splits = nil
	if self.sendingMail then
		self.sendingMail = false
		if Shared.OnSendingFinished then
			Shared.OnSendingFinished()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Split stacks for the "keep N items" rule
----------------------------------------------------------------------------------------------------
-- A partial stack can't go straight into a mail. The part to send is first split off into a free
-- bag slot, and that new slot is mailed. One call does one step for the first waiting split:
-- start it, or check that it arrived. Anything unexpected drops that item from this send, so
-- the worst case is that an item stays in the bags.
AutoMail.splits = nil -- item locations from the mailing list that still have an amount to split off

local function FindFreeSlot()
	for bag=0,4 do
		local free, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		if free > 0 and (bag == 0 or bagFamily == 0) then -- skip profession bags, they refuse most items
			return bag, C_Container.GetContainerFreeSlots(bag)[1]
		end
	end
end

function AutoMail:ProcessSplit()
	local itemLoc = self.splits[1]
	local function GiveUp(reason)
		if itemLoc.target and GetCursorInfo() == "item" then
			ClearCursor() -- puts a split that never landed back on its stack
		end
		itemLoc.failed = true
		table.remove(self.splits, 1)
		DEFAULT_CHAT_FRAME:AddMessage("EasyMail Lists: couldn't split a stack (" .. reason .. "), so that item stays in your bags.", 1, 0, 0)
	end

	if not itemLoc.target then
		local itemInfo = C_Container.GetContainerItemInfo(itemLoc[1], itemLoc[2])
		local bag, slot = FindFreeSlot()
		if not itemInfo or itemInfo.isLocked or itemInfo.stackCount <= itemLoc.amount then
			GiveUp("the stack changed")
		elseif not bag then
			GiveUp("no free bag slot")
		elseif GetCursorInfo() then
			GiveUp("the cursor is holding something")
		else
			itemLoc.itemID = itemInfo.itemID
			itemLoc.target = { bag, slot }
			C_Container.SplitContainerItem(itemLoc[1], itemLoc[2], itemLoc.amount)
			C_Container.PickupContainerItem(bag, slot)
		end
		return
	end

	-- the split was started on an earlier call: mail the new slot only if it holds exactly what was split off
	local itemInfo = C_Container.GetContainerItemInfo(itemLoc.target[1], itemLoc.target[2])
	if itemInfo and itemInfo.itemID == itemLoc.itemID and itemInfo.stackCount == itemLoc.amount and not itemInfo.isLocked then
		itemLoc[1], itemLoc[2], itemLoc.amount = itemLoc.target[1], itemLoc.target[2], nil
		table.remove(self.splits, 1)
	else
		itemLoc.tries = (itemLoc.tries or 0) + 1
		if itemLoc.tries >= 3 then
			GiveUp("the split didn't arrive")
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Put items in the mailbox for the next sending action
----------------------------------------------------------------------------------------------------
AutoMail.nextMail = nil

function AutoMail:SetNextMail()
	if not self.mailingList or self.nextMail then return end

	local onMailSlot = 1
	local itemListText
	for recipient,itemList in pairs(self.mailingList) do
		for i=#itemList,1,-1 do
			local itemLoc = itemList[i]
			itemList[i] = nil

			-- the slot can be empty by now if the item was moved or used
			-- a location that still has an amount was never split (it failed), so it isn't mailed
			local itemInfo = not itemLoc.amount and C_Container.GetContainerItemInfo(itemLoc[1], itemLoc[2])
			if itemInfo and itemInfo.stackCount then
				itemListText = (itemListText and itemListText .. ", " or "") .. (itemInfo.stackCount > 1 and itemInfo.stackCount .. "x" or "") .. itemInfo.hyperlink
				C_Container.PickupContainerItem(itemLoc[1], itemLoc[2])
				ClickSendMailItemButton(onMailSlot)
				self.nextMail = self.nextMail or {}
				self.nextMail[#self.nextMail+1] = itemLoc
				onMailSlot = onMailSlot + 1
				if onMailSlot > 12 then
					break
				end
			end
		end

		-- remove recipient from mailing list if there's no more for them
		if #itemList == 0 then
			self.mailingList[recipient] = nil
			if next(self.mailingList) == nil then
				self.mailingList = nil
			end
		end

		if onMailSlot > 1 then
			self.nextMail.recipient = recipient
			DEFAULT_CHAT_FRAME:AddMessage("Sending mail to " .. recipient .. ": " .. itemListText, 1, 1, 0)
			self:Show() -- start OnUpdate
			return
		end
		if not self.mailingList then
			return
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Keep sending the mail until finished
----------------------------------------------------------------------------------------------------
local totalElapsed = 0
AutoMail:SetScript("OnShow", function(self) totalElapsed = 0 end)
AutoMail:SetScript("OnUpdate", function(self, elapsed)
	totalElapsed = totalElapsed + elapsed
	if totalElapsed > 1 then
		totalElapsed = 0

		-- every split finishes before the first mail is filled
		if self.splits and self.splits[1] then
			self:ProcessSplit()
			return
		end

		if not self.nextMail then
			self:SetNextMail()
			if not self.nextMail then
				self:Finish()
			end
			return
		end

		if GetSendMailItem(1) then
			SendMail(self.nextMail.recipient, "Special Delivery", "")
			self.nextMail = nil
			self:Hide() -- wait for MAIL_SEND_SUCCESS or MAIL_FAILED
		else
			DEFAULT_CHAT_FRAME:AddMessage("EasyMail Lists: No items in slots when trying to send to " .. self.nextMail.recipient, 1, 0, 0)
			self:Finish()
		end
	end
end)

----------------------------------------------------------------------------------------------------
-- Handling events
----------------------------------------------------------------------------------------------------
function AutoMail:SetDefaultSettings()
	if EasyMailListsSave                   == nil then EasyMailListsSave                   = {}   end
	if EasyMailListsSave.groups            == nil then EasyMailListsSave.groups            = {}   end
	if EasyMailListsSave.lastGroupShown    == nil then EasyMailListsSave.lastGroupShown    = ""   end
	-- enabled: send automatically when the mailbox opens. Off for new users: they use the Send button.
	if EasyMailListsSave.enabled           == nil then EasyMailListsSave.enabled           = false end
	if EasyMailListsSave.requireShift      == nil then EasyMailListsSave.requireShift      = true end
	if EasyMailListsSave.sendEquipmentHere == nil then EasyMailListsSave.sendEquipmentHere = false end
	-- characters: every character that has logged in with the addon, [name] = { faction, realm }
	if EasyMailListsSave.characters        == nil then EasyMailListsSave.characters        = {}   end
	-- gearQuality: the lowest quality of unbound gear to send (2 green, 3 blue, 4 epic)
	if EasyMailListsSave.gearQuality       == nil then EasyMailListsSave.gearQuality       = 2    end
	-- itemIDs: [lowercase item name] = item ID, learned when an item is added or seen in the bags
	if EasyMailListsSave.itemIDs           == nil then EasyMailListsSave.itemIDs           = {}   end
	-- theme: "game", "ellesmere" or "modern". Stays nil until the user picks one; then Settings.lua
	-- uses ellesmere when EllesmereUI is loaded and game otherwise (see Shared.ResolveTheme).
end

-- One-time fix for saved lists. The Patterns menu used to add the line "* Stone", which also
-- matches sharpening stones. Replace it with the five stones it was meant for.
function Shared.FixStonePattern()
	if EasyMailListsSave.fixedStonePattern then
		return
	end
	EasyMailListsSave.fixedStonePattern = true
	for _, group in ipairs(EasyMailListsSave.groups) do
		group.list = ((group.list or ""):gsub("[^\r\n]+", function(line)
			if line:lower():match("^%s*%*%s*stone%s*$") then
				return "Rough Stone\nCoarse Stone\nHeavy Stone\nSolid Stone\nDense Stone"
			end
		end))
	end
end

AutoMail:SetScript("OnEvent", function(self, event, arg1)
	-- mailbox has been opened
	if event == "MAIL_SHOW" then
		if EasyMailListsSave.enabled and (not EasyMailListsSave.requireShift or IsShiftKeyDown()) then
			Shared.StartSending()
		end
		return
	end

	-- mail was successfully sent
	if event == "MAIL_SEND_SUCCESS" then
		if self.sendingMail then
			self.nextMail = nil
			self:SetNextMail()
			if not self.nextMail then
				self:Finish()
			end
		end
		return
	end

	-- some mail failed to send or the mailbox was closed
	if event == "MAIL_FAILED" or event == "MAIL_CLOSED" then
		self:Finish()
		return
	end

	-- addon has finished loading
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			self:UnregisterEvent(event)

			self:SetDefaultSettings()
			Shared.FixStonePattern()

			Shared.UpdateItemList()
			self:RegisterEvent("PLAYER_LOGIN")
		end
		return
	end

	-- every addon has loaded: check for the original before touching the mailbox
	if event == "PLAYER_LOGIN" then
		-- remember this character, so it can be picked as a recipient on the others
		local name, faction = GetUnitName("player"), (UnitFactionGroup("player"))
		EasyMailListsSave.characters[name] = { faction = faction, realm = GetRealmName() }
		local ownGroup = Shared.GetGroupSettings(name)
		if ownGroup and ownGroup.faction ~= faction then
			ownGroup.faction = faction -- a recipient that is this character can't have the wrong faction
			Shared.UpdateItemList()
		end

		if C_AddOns.IsAddOnLoaded("PlainAutoMail") then
			-- both addons would send the same mail, so this one waits until the original is disabled
			Shared.paused = true
			if not EasyMailListsSave.imported and PlainAutoMailSave then
				for key, value in pairs(PlainAutoMailSave) do
					EasyMailListsSave[key] = value
				end
				EasyMailListsSave.imported = true
				Shared.UpdateItemList()
				DEFAULT_CHAT_FRAME:AddMessage("EasyMail Lists: imported your lists from Plain AutoMail.", 1, 1, 0)
			end
			DEFAULT_CHAT_FRAME:AddMessage("EasyMail Lists: paused. Disable Plain AutoMail in the addon list, then type /reload.", 1, 1, 0)
			return
		end
		_G.SLASH_EASYMAILLISTS3 = "/automail" -- free to use when the original isn't loaded
		self:RegisterEvent("MAIL_SHOW")
		self:RegisterEvent("MAIL_CLOSED")
		self:RegisterEvent("MAIL_SEND_SUCCESS")
		self:RegisterEvent("MAIL_FAILED")
		return
	end
end)
AutoMail:RegisterEvent("ADDON_LOADED")
