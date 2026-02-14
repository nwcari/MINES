-- LocalScript (StarterPlayer > StarterPlayerScripts)
-- Studio-safe target lock + movement utility menu

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ====== Config ======
local MENU_KEY = Enum.KeyCode.Insert
local DEFAULT_AIM_KEY = Enum.KeyCode.Q
local DEFAULT_WALK_KEY = Enum.KeyCode.LeftShift

local settings = {
	-- Camlock model (matched style)
	Prediction = 0.08,  -- 0.00 - 0.50
	Smoothness = 0.10,  -- 0.00 - 1.00
	LeftOffset = -1.0,  -- -20.00 - 20.00
	UpOffset = 0.5,     -- -20.00 - 20.00

	-- Other
	HipHeight = 2.0,    -- 0.0 - 20.0
	WalkSpeed = 24,     -- 0 - 200
}

local aimToggleKey = DEFAULT_AIM_KEY
local walkSpeedKey = DEFAULT_WALK_KEY
local walkSpeedMode = "Toggle" -- "Toggle" or "Hold"

local lockEnabled = false
local lockedTarget = nil
local listeningForNewAimKey = false
local listeningForNewWalkKey = false
local scriptKilled = false
local connections = {}

-- Walkspeed state
local walkSpeedActive = false
local baseWalkSpeed = 16
local originalWalkSpeed = nil

local currentYaw, currentPitch = 0, 0
do
	local lv = camera.CFrame.LookVector
	currentYaw = math.atan2(-lv.X, -lv.Z)
	currentPitch = math.asin(math.clamp(lv.Y, -1, 1))
end

local function bindConnection(conn)
	table.insert(connections, conn)
	return conn
end

local function getHumanoid()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function applyHipHeight()
	local hum = getHumanoid()
	if hum then hum.HipHeight = settings.HipHeight end
end

local function refreshBaseWalkSpeed()
	local hum = getHumanoid()
	if hum then baseWalkSpeed = hum.WalkSpeed end
end

local function setWalkSpeedEnabled(enabled)
	local hum = getHumanoid()
	if not hum then
		walkSpeedActive = enabled
		return
	end

	if enabled then
		if not walkSpeedActive then
			originalWalkSpeed = hum.WalkSpeed
		end
		walkSpeedActive = true
		hum.WalkSpeed = settings.WalkSpeed
	else
		walkSpeedActive = false
		if originalWalkSpeed then
			hum.WalkSpeed = originalWalkSpeed
			originalWalkSpeed = nil
		else
			hum.WalkSpeed = baseWalkSpeed
		end
	end
end

local function isValidTargetPlayer(plr)
	if plr == player then return nil end
	local char = plr.Character
	if not char then return nil end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end

	return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

local function getClosestTargetToCursor()
	local mousePos = UserInputService:GetMouseLocation()
	local closestPart = nil
	local shortest = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		local part = isValidTargetPlayer(plr)
		if part then
			local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
			if onScreen then
				local dist = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
				if dist < shortest then
					shortest = dist
					closestPart = part
				end
			end
		end
	end

	return closestPart
end

-- ====== UI ======
local gui = Instance.new("ScreenGui")
gui.Name = "Cari & Kay's"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(370, 500)
frame.Position = UDim2.fromOffset(20, 120)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -10, 0, 28)
title.Position = UDim2.fromOffset(5, 4)
title.BackgroundTransparency = 1
title.Text = "Cari & Kay's"
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.TextXAlignment = Enum.TextXAlignment.Center
title.Font = Enum.Font.GothamSemibold
title.TextSize = 16
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -10, 0, 20)
status.Position = UDim2.fromOffset(5, 30)
status.BackgroundTransparency = 1
status.Text = "Status: OFF"
status.TextColor3 = Color3.fromRGB(200, 120, 120)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Gotham
status.TextSize = 13
status.Parent = frame

local menuHint = Instance.new("TextLabel")
menuHint.Size = UDim2.new(1, -10, 0, 18)
menuHint.Position = UDim2.fromOffset(5, 50)
menuHint.BackgroundTransparency = 1
menuHint.Text = "Menu key: Insert"
menuHint.TextColor3 = Color3.fromRGB(165, 165, 165)
menuHint.TextXAlignment = Enum.TextXAlignment.Left
menuHint.Font = Enum.Font.Gotham
menuHint.TextSize = 12
menuHint.Parent = frame

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -10, 0, 30)
tabBar.Position = UDim2.fromOffset(5, 74)
tabBar.BackgroundTransparency = 1
tabBar.Parent = frame

local function makeTabButton(text, posScale, posOffset)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.25, -3, 1, 0)
	b.Position = UDim2.new(posScale, posOffset, 0, 0)
	b.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.fromRGB(230, 230, 230)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Parent = tabBar
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	return b
end

local tabAimbotBtn = makeTabButton("Aimbot", 0.00, 0)
local tabHipBtn = makeTabButton("HipHeight", 0.25, 1)
local tabWalkBtn = makeTabButton("WalkSpeed", 0.50, 2)
local tabMiscBtn = makeTabButton("Misc", 0.75, 3)

local aimbotTab = Instance.new("Frame")
aimbotTab.Size = UDim2.new(1, -10, 0, 380)
aimbotTab.Position = UDim2.fromOffset(5, 110)
aimbotTab.BackgroundTransparency = 1
aimbotTab.Parent = frame

local hipTab = Instance.new("Frame")
hipTab.Size = UDim2.new(1, -10, 0, 380)
hipTab.Position = UDim2.fromOffset(5, 110)
hipTab.BackgroundTransparency = 1
hipTab.Visible = false
hipTab.Parent = frame

local walkTab = Instance.new("Frame")
walkTab.Size = UDim2.new(1, -10, 0, 380)
walkTab.Position = UDim2.fromOffset(5, 110)
walkTab.BackgroundTransparency = 1
walkTab.Visible = false
walkTab.Parent = frame

local miscTab = Instance.new("Frame")
miscTab.Size = UDim2.new(1, -10, 0, 380)
miscTab.Position = UDim2.fromOffset(5, 110)
miscTab.BackgroundTransparency = 1
miscTab.Visible = false
miscTab.Parent = frame

local function setTab(name)
	local isAimbot = (name == "Aimbot")
	local isHip = (name == "HipHeight")
	local isWalk = (name == "WalkSpeed")
	local isMisc = (name == "Misc")

	aimbotTab.Visible = isAimbot
	hipTab.Visible = isHip
	walkTab.Visible = isWalk
	miscTab.Visible = isMisc

	tabAimbotBtn.BackgroundColor3 = isAimbot and Color3.fromRGB(70, 110, 220) or Color3.fromRGB(45, 45, 52)
	tabHipBtn.BackgroundColor3 = isHip and Color3.fromRGB(70, 110, 220) or Color3.fromRGB(45, 45, 52)
	tabWalkBtn.BackgroundColor3 = isWalk and Color3.fromRGB(70, 110, 220) or Color3.fromRGB(45, 45, 52)
	tabMiscBtn.BackgroundColor3 = isMisc and Color3.fromRGB(70, 110, 220) or Color3.fromRGB(45, 45, 52)
end

local activeSlider = nil

local function createSlider(parent, cfg)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -4, 0, 42)
	holder.Position = UDim2.fromOffset(2, cfg.Y)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.62, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = cfg.Name
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.Parent = holder

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0.38, 0, 0, 16)
	valueLabel.Position = UDim2.new(0.62, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Font = Enum.Font.Code
	valueLabel.TextSize = 13
	valueLabel.Parent = holder

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.Position = UDim2.fromOffset(0, 24)
	bar.BackgroundColor3 = Color3.fromRGB(48, 48, 56)
	bar.BorderSizePixel = 0
	bar.Parent = holder

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 140, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.fromOffset(14, 14)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.BackgroundColor3 = Color3.fromRGB(235, 235, 245)
	knob.BorderSizePixel = 0
	knob.Parent = bar

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local state = {
		min = cfg.Min,
		max = cfg.Max,
		step = cfg.Step,
		decimals = cfg.Decimals or 2,
		value = cfg.Default,
		bar = bar,
		fill = fill,
		knob = knob,
		onChanged = cfg.OnChanged,
	}

	local function roundToStep(v)
		local snapped = math.floor((v / state.step) + 0.5) * state.step
		return math.clamp(snapped, state.min, state.max)
	end

	local function setValue(v, fireCallback)
		state.value = roundToStep(v)
		local alpha = (state.value - state.min) / (state.max - state.min)
		state.fill.Size = UDim2.fromScale(alpha, 1)
		state.knob.Position = UDim2.fromScale(alpha, 0.5)

		if state.decimals == 0 then
			valueLabel.Text = string.format("%d", state.value)
		else
			valueLabel.Text = string.format("%." .. state.decimals .. "f", state.value)
		end

		if fireCallback and state.onChanged then
			state.onChanged(state.value)
		end
	end

	local function updateFromMouseX(mouseX)
		local x = mouseX - state.bar.AbsolutePosition.X
		local width = math.max(state.bar.AbsoluteSize.X, 1)
		local alpha = math.clamp(x / width, 0, 1)
		local v = state.min + (state.max - state.min) * alpha
		setValue(v, true)
	end

	bindConnection(bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSlider = { update = updateFromMouseX }
			updateFromMouseX(input.Position.X)
		end
	end))

	bindConnection(knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSlider = { update = updateFromMouseX }
			updateFromMouseX(input.Position.X)
		end
	end))

	setValue(cfg.Default, true)
end

-- Aimbot Tab
createSlider(aimbotTab, {
	Name = "Smoothness",
	Y = 0,
	Min = 0.00,
	Max = 1.00,
	Step = 0.01,
	Default = settings.Smoothness,
	Decimals = 2,
	OnChanged = function(v) settings.Smoothness = v end,
})

createSlider(aimbotTab, {
	Name = "Prediction",
	Y = 44,
	Min = 0.00,
	Max = 0.50,
	Step = 0.001,
	Default = settings.Prediction,
	Decimals = 3,
	OnChanged = function(v) settings.Prediction = v end,
})

createSlider(aimbotTab, {
	Name = "Left / Right Offset",
	Y = 88,
	Min = -20.00,
	Max = 20.00,
	Step = 0.05,
	Default = settings.LeftOffset,
	Decimals = 2,
	OnChanged = function(v) settings.LeftOffset = v end,
})

createSlider(aimbotTab, {
	Name = "Up / Down Offset",
	Y = 132,
	Min = -20.00,
	Max = 20.00,
	Step = 0.05,
	Default = settings.UpOffset,
	Decimals = 2,
	OnChanged = function(v) settings.UpOffset = v end,
})

local aimKeyRow = Instance.new("Frame")
aimKeyRow.Size = UDim2.new(1, -4, 0, 34)
aimKeyRow.Position = UDim2.fromOffset(2, 188)
aimKeyRow.BackgroundTransparency = 1
aimKeyRow.Parent = aimbotTab

local aimKeyLabel = Instance.new("TextLabel")
aimKeyLabel.Size = UDim2.new(0.45, 0, 1, 0)
aimKeyLabel.BackgroundTransparency = 1
aimKeyLabel.Text = "Aim Toggle Key"
aimKeyLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
aimKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
aimKeyLabel.Font = Enum.Font.Gotham
aimKeyLabel.TextSize = 13
aimKeyLabel.Parent = aimKeyRow

local aimKeyButton = Instance.new("TextButton")
aimKeyButton.Size = UDim2.new(0.30, -4, 0, 26)
aimKeyButton.Position = UDim2.new(0.45, 4, 0.5, -13)
aimKeyButton.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
aimKeyButton.BorderSizePixel = 0
aimKeyButton.Text = aimToggleKey.Name
aimKeyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
aimKeyButton.Font = Enum.Font.GothamBold
aimKeyButton.TextSize = 12
aimKeyButton.Parent = aimKeyRow
local aimKeyCorner = Instance.new("UICorner")
aimKeyCorner.CornerRadius = UDim.new(0, 6)
aimKeyCorner.Parent = aimKeyButton

local aimKeyHint = Instance.new("TextLabel")
aimKeyHint.Size = UDim2.new(0.25, 0, 1, 0)
aimKeyHint.Position = UDim2.new(0.75, 0, 0, 0)
aimKeyHint.BackgroundTransparency = 1
aimKeyHint.Text = "Click to set"
aimKeyHint.TextColor3 = Color3.fromRGB(160, 160, 160)
aimKeyHint.TextXAlignment = Enum.TextXAlignment.Left
aimKeyHint.Font = Enum.Font.Gotham
aimKeyHint.TextSize = 11
aimKeyHint.Parent = aimKeyRow

-- HipHeight Tab
local hipTitle = Instance.new("TextLabel")
hipTitle.Size = UDim2.new(1, 0, 0, 20)
hipTitle.Position = UDim2.fromOffset(0, 0)
hipTitle.BackgroundTransparency = 1
hipTitle.Text = "HipHeight"
hipTitle.TextColor3 = Color3.fromRGB(220, 220, 220)
hipTitle.TextXAlignment = Enum.TextXAlignment.Left
hipTitle.Font = Enum.Font.GothamSemibold
hipTitle.TextSize = 14
hipTitle.Parent = hipTab

createSlider(hipTab, {
	Name = "HipHeight",
	Y = 36,
	Min = 0.0,
	Max = 20.0,
	Step = 0.1,
	Default = settings.HipHeight,
	Decimals = 1,
	OnChanged = function(v)
		settings.HipHeight = v
		applyHipHeight()
	end,
})

-- WalkSpeed Tab
local walkTitle = Instance.new("TextLabel")
walkTitle.Size = UDim2.new(1, 0, 0, 20)
walkTitle.Position = UDim2.fromOffset(0, 0)
walkTitle.BackgroundTransparency = 1
walkTitle.Text = "WalkSpeed"
walkTitle.TextColor3 = Color3.fromRGB(220, 220, 220)
walkTitle.TextXAlignment = Enum.TextXAlignment.Left
walkTitle.Font = Enum.Font.GothamSemibold
walkTitle.TextSize = 14
walkTitle.Parent = walkTab

createSlider(walkTab, {
	Name = "WalkSpeed Value",
	Y = 36,
	Min = 0,
	Max = 200,
	Step = 1,
	Default = settings.WalkSpeed,
	Decimals = 0,
	OnChanged = function(v)
		settings.WalkSpeed = v
		if walkSpeedActive then
			local hum = getHumanoid()
			if hum then hum.WalkSpeed = settings.WalkSpeed end
		end
	end,
})

local walkKeyRow = Instance.new("Frame")
walkKeyRow.Size = UDim2.new(1, -4, 0, 34)
walkKeyRow.Position = UDim2.fromOffset(2, 88)
walkKeyRow.BackgroundTransparency = 1
walkKeyRow.Parent = walkTab

local walkKeyLabel = Instance.new("TextLabel")
walkKeyLabel.Size = UDim2.new(0.45, 0, 1, 0)
walkKeyLabel.BackgroundTransparency = 1
walkKeyLabel.Text = "WalkSpeed Key"
walkKeyLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
walkKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
walkKeyLabel.Font = Enum.Font.Gotham
walkKeyLabel.TextSize = 13
walkKeyLabel.Parent = walkKeyRow

local walkKeyButton = Instance.new("TextButton")
walkKeyButton.Size = UDim2.new(0.30, -4, 0, 26)
walkKeyButton.Position = UDim2.new(0.45, 4, 0.5, -13)
walkKeyButton.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
walkKeyButton.BorderSizePixel = 0
walkKeyButton.Text = walkSpeedKey.Name
walkKeyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
walkKeyButton.Font = Enum.Font.GothamBold
walkKeyButton.TextSize = 12
walkKeyButton.Parent = walkKeyRow
local walkKeyCorner = Instance.new("UICorner")
walkKeyCorner.CornerRadius = UDim.new(0, 6)
walkKeyCorner.Parent = walkKeyButton

local walkModeRow = Instance.new("Frame")
walkModeRow.Size = UDim2.new(1, -4, 0, 34)
walkModeRow.Position = UDim2.fromOffset(2, 132)
walkModeRow.BackgroundTransparency = 1
walkModeRow.Parent = walkTab

local walkModeLabel = Instance.new("TextLabel")
walkModeLabel.Size = UDim2.new(0.45, 0, 1, 0)
walkModeLabel.BackgroundTransparency = 1
walkModeLabel.Text = "WalkSpeed Mode"
walkModeLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
walkModeLabel.TextXAlignment = Enum.TextXAlignment.Left
walkModeLabel.Font = Enum.Font.Gotham
walkModeLabel.TextSize = 13
walkModeLabel.Parent = walkModeRow

local walkModeButton = Instance.new("TextButton")
walkModeButton.Size = UDim2.new(0.30, -4, 0, 26)
walkModeButton.Position = UDim2.new(0.45, 4, 0.5, -13)
walkModeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
walkModeButton.BorderSizePixel = 0
walkModeButton.Text = walkSpeedMode
walkModeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
walkModeButton.Font = Enum.Font.GothamBold
walkModeButton.TextSize = 12
walkModeButton.Parent = walkModeRow
local walkModeCorner = Instance.new("UICorner")
walkModeCorner.CornerRadius = UDim.new(0, 6)
walkModeCorner.Parent = walkModeButton

local walkStateLabel = Instance.new("TextLabel")
walkStateLabel.Size = UDim2.new(1, -4, 0, 18)
walkStateLabel.Position = UDim2.fromOffset(2, 176)
walkStateLabel.BackgroundTransparency = 1
walkStateLabel.TextXAlignment = Enum.TextXAlignment.Left
walkStateLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
walkStateLabel.Font = Enum.Font.Gotham
walkStateLabel.TextSize = 12
walkStateLabel.Parent = walkTab

local function updateWalkStateUI()
	local stateText = walkSpeedActive and "ON" or "OFF"
	walkStateLabel.Text = "State: " .. stateText .. "  [" .. walkSpeedKey.Name .. "]  Mode: " .. walkSpeedMode
	walkModeButton.Text = walkSpeedMode
	walkKeyButton.Text = walkSpeedKey.Name
end

-- Misc Tab
local miscTitle = Instance.new("TextLabel")
miscTitle.Size = UDim2.new(1, 0, 0, 20)
miscTitle.Position = UDim2.fromOffset(0, 0)
miscTitle.BackgroundTransparency = 1
miscTitle.Text = "Misc"
miscTitle.TextColor3 = Color3.fromRGB(220, 220, 220)
miscTitle.TextXAlignment = Enum.TextXAlignment.Left
miscTitle.Font = Enum.Font.GothamSemibold
miscTitle.TextSize = 14
miscTitle.Parent = miscTab

local killButton = Instance.new("TextButton")
killButton.Size = UDim2.fromOffset(180, 34)
killButton.Position = UDim2.fromOffset(0, 36)
killButton.BackgroundColor3 = Color3.fromRGB(170, 55, 55)
killButton.BorderSizePixel = 0
killButton.Text = "KILL SWITCH"
killButton.TextColor3 = Color3.fromRGB(255, 255, 255)
killButton.Font = Enum.Font.GothamBold
killButton.TextSize = 13
killButton.Parent = miscTab
local killCorner = Instance.new("UICorner")
killCorner.CornerRadius = UDim.new(0, 6)
killCorner.Parent = killButton

local killState = Instance.new("TextLabel")
killState.Size = UDim2.new(1, 0, 0, 18)
killState.Position = UDim2.fromOffset(0, 76)
killState.BackgroundTransparency = 1
killState.Text = ""
killState.TextColor3 = Color3.fromRGB(220, 160, 160)
killState.TextXAlignment = Enum.TextXAlignment.Left
killState.Font = Enum.Font.Gotham
killState.TextSize = 12
killState.Parent = miscTab

local function updateStatus()
	if scriptKilled then
		status.Text = "Status: KILLED"
		status.TextColor3 = Color3.fromRGB(220, 120, 120)
		return
	end

	if lockEnabled and lockedTarget then
		status.Text = "Status: ON (locked)  [" .. aimToggleKey.Name .. "]"
		status.TextColor3 = Color3.fromRGB(120, 220, 120)
	elseif lockEnabled then
		status.Text = "Status: ON (no target)  [" .. aimToggleKey.Name .. "]"
		status.TextColor3 = Color3.fromRGB(220, 200, 120)
	else
		status.Text = "Status: OFF  [" .. aimToggleKey.Name .. "]"
		status.TextColor3 = Color3.fromRGB(200, 120, 120)
	end
end

local function doKillSwitch()
	if scriptKilled then return end

	setWalkSpeedEnabled(false)

	scriptKilled = true
	lockEnabled = false
	lockedTarget = nil
	listeningForNewAimKey = false
	listeningForNewWalkKey = false

	for _, conn in ipairs(connections) do
		if conn and conn.Connected then conn:Disconnect() end
	end
	table.clear(connections)

	killState.Text = "Script disabled."
	updateStatus()

	task.delay(0.6, function()
		if gui then gui:Destroy() end
	end)
end

-- Hooks
bindConnection(tabAimbotBtn.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	setTab("Aimbot")
end))
bindConnection(tabHipBtn.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	setTab("HipHeight")
end))
bindConnection(tabWalkBtn.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	setTab("WalkSpeed")
end))
bindConnection(tabMiscBtn.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	setTab("Misc")
end))

bindConnection(aimKeyButton.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	listeningForNewAimKey = true
	aimKeyButton.Text = "Press key..."
end))

bindConnection(walkKeyButton.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	listeningForNewWalkKey = true
	walkKeyButton.Text = "Press key..."
end))

bindConnection(walkModeButton.MouseButton1Click:Connect(function()
	if scriptKilled then return end
	if walkSpeedMode == "Toggle" then
		walkSpeedMode = "Hold"
		if walkSpeedActive then setWalkSpeedEnabled(false) end
	else
		walkSpeedMode = "Toggle"
	end
	updateWalkStateUI()
end))

bindConnection(killButton.MouseButton1Click:Connect(function()
	doKillSwitch()
end))

bindConnection(player.CharacterAdded:Connect(function()
	if scriptKilled then return end
	task.wait(0.2)
	applyHipHeight()
	refreshBaseWalkSpeed()

	if walkSpeedActive then
		local hum = getHumanoid()
		if hum then
			originalWalkSpeed = hum.WalkSpeed
			hum.WalkSpeed = settings.WalkSpeed
		end
	end
end))

-- Drag + slider tracking
do
	local dragging = false
	local dragStart, startPos

	bindConnection(frame.InputBegan:Connect(function(input)
		if scriptKilled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end))

	bindConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			activeSlider = nil
		end
	end))

	bindConnection(UserInputService.InputChanged:Connect(function(input)
		if scriptKilled then return end

		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end

		if activeSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
			activeSlider.update(input.Position.X)
		end
	end))
end

-- Input handling
bindConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if scriptKilled then return end
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == MENU_KEY then
		frame.Visible = not frame.Visible
		return
	end

	if listeningForNewAimKey then
		local newKey = input.KeyCode
		if newKey ~= Enum.KeyCode.Unknown and newKey ~= MENU_KEY then
			aimToggleKey = newKey
		end
		aimKeyButton.Text = aimToggleKey.Name
		listeningForNewAimKey = false
		updateStatus()
		return
	end

	if listeningForNewWalkKey then
		local newKey = input.KeyCode
		if newKey ~= Enum.KeyCode.Unknown and newKey ~= MENU_KEY then
			walkSpeedKey = newKey
		end
		listeningForNewWalkKey = false
		updateWalkStateUI()
		return
	end

	if input.KeyCode == aimToggleKey then
		lockEnabled = not lockEnabled
		lockedTarget = lockEnabled and getClosestTargetToCursor() or nil
		updateStatus()
		return
	end

	if input.KeyCode == walkSpeedKey then
		if walkSpeedMode == "Toggle" then
			setWalkSpeedEnabled(not walkSpeedActive)
		else
			setWalkSpeedEnabled(true)
		end
		updateWalkStateUI()
	end
end))

bindConnection(UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if scriptKilled then return end
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if walkSpeedMode == "Hold" and input.KeyCode == walkSpeedKey then
		setWalkSpeedEnabled(false)
		updateWalkStateUI()
	end
end))

-- Camlock update
bindConnection(RunService.RenderStepped:Connect(function()
	if scriptKilled then return end

	if not lockEnabled then
		updateStatus()
		return
	end

	if not lockedTarget or not lockedTarget.Parent then
		lockedTarget = getClosestTargetToCursor()
		updateStatus()
		if not lockedTarget then return end
	end

	-- Exact-style prediction + smoothness model
	local targetPos = lockedTarget.Position + (lockedTarget.Velocity * settings.Prediction)
	local finalPos = targetPos + (camera.CFrame.RightVector * settings.LeftOffset) + Vector3.new(0, settings.UpOffset, 0)

	local camPos = camera.CFrame.Position
	local dir = finalPos - camPos
	if dir.Magnitude < 0.001 then return end
	dir = dir.Unit

	local targetYaw = math.atan2(-dir.X, -dir.Z)
	local targetPitch = math.asin(math.clamp(dir.Y, -1, 1))
	local alpha = math.clamp(settings.Smoothness, 0, 1)

	currentYaw = currentYaw + (targetYaw - currentYaw) * alpha
	currentPitch = currentPitch + (targetPitch - currentPitch) * alpha

	local look = Vector3.new(
		-math.sin(currentYaw) * math.cos(currentPitch),
		math.sin(currentPitch),
		-math.cos(currentYaw) * math.cos(currentPitch)
	)

	camera.CFrame = CFrame.lookAt(camPos, camPos + look)
end))

-- Walkspeed enforcer
bindConnection(RunService.RenderStepped:Connect(function()
	if scriptKilled then return end
	if not walkSpeedActive then return end

	local hum = getHumanoid()
	if hum and hum.WalkSpeed ~= settings.WalkSpeed then
		hum.WalkSpeed = settings.WalkSpeed
	end
end))

refreshBaseWalkSpeed()
setTab("Aimbot")
applyHipHeight()
setWalkSpeedEnabled(false)
updateWalkStateUI()
updateStatus()
