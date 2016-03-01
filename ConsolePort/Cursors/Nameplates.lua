---------------------------------------------------------------
-- Nameplates.lua: Secure nameplate targeting cursor for combat
---------------------------------------------------------------
-- Creates a secure cursor that is used to iterate over nameplates
-- and select a target based on where the plate is drawn on screen.
-- Scans WorldFrame for active nameplates, scales them up to
-- cover the entire screen, then uses a mouseover macro to target.

local _, db = ...
local WorldFrame = WorldFrame
local GetCVarBool = GetCVarBool
local IsMouselooking = IsMouselooking
local InCombatLockdown = InCombatLockdown

---------------------------------------------------------------
-- This is just a convenience button for cycling
-- active nameplates, instead of occupying several bindings to
-- achieve the same result.

local PlateCycle = CreateFrame("Button", "ConsolePortNameplateCycle", nil, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")

PlateCycle:SetAttribute("type", "macro")
PlateCycle:Execute([[
	Scripts = newtable()

	Scripts[1] = "/click InterfaceOptionsNamesPanelUnitNameplatesEnemies"
	Scripts[2] = "/click InterfaceOptionsNamesPanelUnitNameplatesFriends"
]])
PlateCycle:WrapScript(PlateCycle, "PreClick", [[
	Index = Index == 1 and 2 or 1
	self:SetAttribute("macrotext", Scripts[Index])
]])

---------------------------------------------------------------
---------------------------------------------------------------

local Cursor = CreateFrame("Button", "ConsolePortWorldCursor", WorldFrame, "SecureActionButtonTemplate, SecureHandlerBaseTemplate, SecureHandlerShowHideTemplate, SecureHandlerStateTemplate")

Cursor:RegisterForClicks("AnyUp", "AnyDown")
Cursor:SetAttribute("type", "macro")
Cursor:SetAttribute("macrotext1", "/target [@mouseover, exists]")
Cursor:SetAttribute("downbutton", "omit")
Cursor:SetAttribute("_onstate-modifier", "Mod = newstate")

RegisterStateDriver(Cursor, "modifier", "[mod:ctrl,mod:shift] CTRL-SHIFT-; [mod:ctrl] CTRL-; [mod:shift] SHIFT-; ")

Cursor:SetSize(32, 32)
Cursor:Hide()

Cursor:HookScript("OnShow", function(self) PlaySound("INTERFACESOUND_LOSTTARGETUNIT") end)

function Cursor:SetClamped(plateName) _G[plateName]:SetClampedToScreen(true) end

---------------------------------------------------------------
local Key = {
	Up 		= ConsolePort:GetUIControlKey("CP_L_UP"),
	Down 	= ConsolePort:GetUIControlKey("CP_L_DOWN"),
	Left 	= ConsolePort:GetUIControlKey("CP_L_LEFT"),
	Right 	= ConsolePort:GetUIControlKey("CP_L_RIGHT"),
}
---------------------------------------------------------------

Cursor:SetFrameRef("WorldFrame", WorldFrame)
Cursor:SetFrameRef("MouseHandle", ConsolePortMouseHandle)

Cursor:Execute(format([[	
	---------------------------------------------------------------
	Plates = newtable()
	---------------------------------------------------------------
	DPAD = newtable()
	---------------------------------------------------------------
	Key = newtable()
	---------------------------------------------------------------
	Key.Up = %s
	Key.Down = %s
	Key.Left = %s
	Key.Right = %s
	---------------------------------------------------------------
	Cancel = newtable()
	Cancel.CP_C_OPTION = true
	Cancel.CP_L_OPTION = true
	Cancel.CP_R_OPTION = true
	---------------------------------------------------------------
	Target = newtable()
	Target.CP_TR1 = true
	Target.CP_TR2 = true
	Target.CP_R_UP = true
	Target.CP_R_LEFT = true
	Target.CP_R_RIGHT = true
	---------------------------------------------------------------

	WorldFrame = self:GetFrameRef("WorldFrame")
	MouseHandle = self:GetFrameRef("MouseHandle")


	---------------------------------------------------------------

	GetPlates = [=[

		for Plate in pairs(Plates) do
			Plate:SetScale(1)
			Plate:SetFrameLevel(0)
		end

		Plates = wipe(Plates)

		for i, frame in pairs(newtable(WorldFrame:GetChildren())) do
			local name = frame:GetName()
			if name and strmatch(name, "NamePlate") and frame:IsShown() then
				Plates[frame] = true
			end
		end
	]=]

	SetCurrent = [=[
		if old and old:IsShown() then
			current = old
		elseif (not current and next(Plates)) or (current and next(Plates) and not current:IsVisible()) then
			local thisX, thisY = self:GetRect()

			if thisX and thisY then
				local plate, dist

				for Plate in pairs(Plates) do
					if Plate ~= old and Plate:IsShown() then
						local left, bottom, width, height = Plate:GetRect()

						if left and bottom and width and height then
							local destDistance = abs(thisX - (left + width / 2)) + abs(thisY - (bottom + height / 2))

							if not dist or destDistance < dist then
								plate = Plate
								dist = destDistance
							end
						end
					end
				end
				if plate then
					current = plate
				end
			else
				for Plate in pairs(Plates) do
					if Plate:IsShown() then
						current = Plate
						break
					end
				end
			end
		end
		self:SetAttribute("plate", current)
	]=]

	FindClosestPlate = [=[
		if current then
			local left, bottom, width, height = current:GetRect()
			local thisY = bottom+height/2
			local thisX = left+width/2
			local nodeY, nodeX = 10000, 10000
			local destY, destX, diffY, diffX, total, swap
			local newTarget
			for destination in pairs(Plates) do
				left, bottom, width, height = destination:GetRect()
				destY = bottom+height/2
				destX = left+width/2
				diffY = abs(thisY-destY)
				diffX = abs(thisX-destX)
				total = diffX + diffY
				if total < nodeX + nodeY then
					if 	key == Key.Up then
						if 	diffY > diffX and 	-- up/down
							destY > thisY then 	-- up
							swap = true
						end
					elseif key == Key.Down then
						if 	diffY > diffX and 	-- up/down
							destY < thisY then 	-- down
							swap = true
						end
					elseif key == Key.Left then
						if 	diffY < diffX and 	-- left/right
							destX < thisX then 	-- left
							swap = true
						end
					elseif key == Key.Right then
						if 	diffY < diffX and 	-- left/right
							destX > thisX then 	-- right
							swap = true
						end
					end
				end
				if swap then
					nodeX = diffX
					nodeY = diffY
					newTarget = destination
					swap = false
				end
			end
			if not newTarget and key ~= 0 then
				for destination in pairs(Plates) do
					if destination ~= current then
						left, bottom, width, height = destination:GetRect()
						destY = bottom+height/2
						destX = left+width/2
						diffY = abs(thisY-destY)
						diffX = abs(thisX-destX)
						total = diffX + diffY
						if total < nodeX + nodeY then
							nodeX = diffX
							nodeY = diffY
							newTarget = destination
						end
					end
				end
			end
			current = newTarget or current
		end
	]=]

	Disable = [=[
		local wipeOld = ...
		if wipeOld then
			old = nil
		end
		IsEnabled = false
		self:SetParent(WorldFrame)
		self:ClearAllPoints()
		self:ClearBindings()
		self:Hide()
		current = nil
	]=]

	SelectPlate = [=[
		key = ...
		if current then
			old = current
		end

		self:Run(GetPlates)
		self:Run(SetCurrent)
		self:Run(FindClosestPlate)

		if current and current:IsShown() then
			self:CallMethod("SetClamped", current:GetName())
			self:SetParent(current)
			self:ClearAllPoints()
			self:SetPoint("BOTTOM", current, "TOP", 0, 0)
		else
			self:Run(Disable)
		end
	]=]
]], Key.Up, Key.Down, Key.Left, Key.Right))


Cursor:SetAttribute("_onhide", [[
	if IsEnabled then
		self:Run(SelectPlate, 0)
	end
]])

Cursor:WrapScript(Cursor, "OnClick", [[
	if button == "RightButton" then
		self:Run(Disable, true)
	else
		if down then 
			IsEnabled = not IsEnabled
		end
		if IsEnabled then
			if down then
				for binding, name in pairs(DPAD) do
					local key = GetBindingKey(binding)
					if key then
						self:SetBindingClick(true, key, "ConsolePortWorldCursorButton"..name)
						if Mod then
							self:SetBindingClick(true, Mod..key, "ConsolePortWorldCursorButton"..name)
						end
					end
				end
				for button in pairs(Cancel) do
					local key = GetBindingKey(button)
					if key then
						self:SetBindingClick(true, key, self, "RightButton")
					end
				end
				for button in pairs(Target) do
					local key = GetBindingKey(button)
					if key then
						self:SetBindingClick(true, key, self, "LeftButton")
					end
				end
				self:Run(SelectPlate, 0)
				self:Show()
			end
		else
			if current and down then
				self:CallMethod("SetClamped", current:GetName())
				self:SetFrameLevel(20)
				current:SetFrameLevel(1)
				current:SetScale(100)
			end
			-- for Plate in pairs(Plates) do
			-- 	if Plate:IsUnderMouse() and Plate ~= current then
			-- 		-- room for improvement when another plate is in the way
			-- 	end
			-- end
			self:Hide()
			if not down then
				self:ClearBindings()
			end
		end
	end
]])

Cursor:WrapScript(Cursor, "PostClick", [[
	if not IsEnabled and not down and current then
		current:SetScale(1)
	end
]])


---------------------------------------------------------------
local wasMouseLooking

Cursor:HookScript("PreClick", function(self, button, down)
	if 	down and
		not GetCVarBool("nameplateShowEnemies") and
		not GetCVarBool("nameplateShowFriends") then
		if not InCombatLockdown() then
			SetCVar("nameplateShowEnemies", 1)
		end
	end
	if self:IsVisible() and button == "LeftButton" then
		wasMouseLooking = IsMouselooking()
		ConsolePort:StopMouse()
	end
end)

Cursor:HookScript("PostClick", function(self, button, down)
	if wasMouseLooking and not down then
		ConsolePort:StartMouse()
	end
end)

---------------------------------------------------------------
local buttons = {
	Up 		= {binding = "CP_L_UP", 	key = Key.Up},
	Down 	= {binding = "CP_L_DOWN", 	key = Key.Down},
	Left 	= {binding = "CP_L_LEFT", 	key = Key.Left},
	Right 	= {binding = "CP_L_RIGHT",	key = Key.Right},
}
---------------------------------------------------------------
for name, button in pairs(buttons) do
	local btn = CreateFrame("Button", "$parentButton"..name, Cursor, "SecureActionButtonTemplate")
	btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	Cursor:WrapScript(btn, "OnClick", format([[
		local Cursor = self:GetParent()
		if down then
			Cursor:Run(SelectPlate, %s)
		end
	]], button.key))
	Cursor:Execute(format([[
		DPAD.%s = "%s"
	]], button.binding, name))
end

---------------------------------------------------------------
-- Crosshairs are drawn on top of the current nameplate.
-- This frame updates smoothly to look more similar to
-- an actual mouse instead of instantly jumping between plates.

local Crosshairs = CreateFrame("Frame", "ConsolePortWorldCursorCrosshairs", WorldFrame)
Crosshairs:SetBackdrop({bgFile = "Interface\\Cursor\\Crosshairs"})
Crosshairs:SetPoint("CENTER", WorldFrame, "BOTTOMLEFT", 0, 0)
Crosshairs:SetSize(32, 32)
Crosshairs:Lower()
Crosshairs:SetScript("OnUpdate", function(self, elapsed)
	if Cursor:IsVisible() then
		if self:GetAlpha() < 1 then
			for i, child in pairs({Cursor:GetChildren()}) do
				if child.mod then
					child:SetParent(self)
					local point, _, relativePoint, xOffset, yOffset = child:GetPoint()
					child:SetPoint(point, self, relativePoint, xOffset, yOffset)
					break
				end
			end
		end
		self:SetAlpha(1)
		local targetX, targetY = Cursor:GetCenter()
		local currX, currY = self:GetCenter()
		if targetX and targetY then
			local horz, vert = (targetX - currX), (targetY - currY)
			local distX, distY = abs(horz), abs(vert)
			if distX < 10 and distY < 10 then
				self:SetPoint("TOP", WorldFrame, "BOTTOMLEFT", targetX, targetY + 8)
			else
				self:SetPoint("TOP", WorldFrame, "BOTTOMLEFT", currX + horz * 0.25, currY + vert * 0.25 + 8)
			end
		end
	else
		self:SetAlpha(0)
	end
end)