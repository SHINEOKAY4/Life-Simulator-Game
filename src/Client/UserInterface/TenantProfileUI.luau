--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ClientFolder = script.Parent.Parent
local ClientStoresFolder = ClientFolder:WaitForChild("ClientStores")
local TenantStore = require(ClientStoresFolder:WaitForChild("TenantStore"))

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local TenantProfileUI = {}
local billboard: BillboardGui?
local contentFrame: Frame?
local currentTenantId: string?
local currentAdornee: Instance?

-- Theme Constants
local COLORS = {
	TextPrimary = Color3.fromRGB(255, 255, 255),
	TextSecondary = Color3.fromRGB(230, 230, 230),
	Accent = Color3.fromRGB(100, 181, 246),
	Shadow = Color3.fromRGB(0, 0, 0),
}

local FONTS = {
	Header = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Light = Enum.Font.GothamMedium,
}

local function createLabel(parent: Instance, text: string, font: Enum.Font, heightScale: number, color: Color3)
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, heightScale)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = COLORS.Shadow
	stroke.Transparency = 0.5
	stroke.Parent = label

	return label
end

local function createStatRow(parent: Instance, labelText: string, valueText: string, heightScale: number)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, heightScale)
	row.Parent = parent

	local label = createLabel(row, labelText, FONTS.Light, 1, COLORS.TextSecondary)
	label.Size = UDim2.fromScale(0.4, 1)

	local value = createLabel(row, valueText, FONTS.Body, 1, COLORS.TextPrimary)
	value.Size = UDim2.fromScale(0.6, 1)
	value.Position = UDim2.fromScale(0.4, 0)

	return row
end

function TenantProfileUI.Init()
	if billboard then
		return
	end

	local newBillboard = Instance.new("BillboardGui")
	newBillboard.Name = "TenantProfileBillboard"
	newBillboard.ResetOnSpawn = false
	newBillboard.Enabled = false
	newBillboard.Size = UDim2.fromScale(14, 8) -- Scaled in studs
	newBillboard.StudsOffset = Vector3.new(0, 5, 0)
	newBillboard.AlwaysOnTop = true
	newBillboard.MaxDistance = 60
	newBillboard.Parent = PlayerGui

	billboard = newBillboard

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = newBillboard

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = container

	contentFrame = container
end

local function clearContent()
	if not contentFrame then
		return
	end
	for _, child in ipairs(contentFrame:GetChildren()) do
		if not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function updateUI(details: any)
	if not contentFrame then
		return
	end
	clearContent()

	-- Main Layout: Vertical List
	local mainLayout = Instance.new("UIListLayout")
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainLayout.Padding = UDim.new(0, 0)
	mainLayout.Parent = contentFrame

	-- Header (Name) - REMOVED as per request
	-- local headerFrame = Instance.new("Frame")
	-- headerFrame.BackgroundTransparency = 1
	-- headerFrame.Size = UDim2.fromScale(1, 0.15)
	-- headerFrame.LayoutOrder = 1
	-- headerFrame.Parent = contentFrame

	-- local nameLabel = createLabel(headerFrame, details.Name, FONTS.Header, 1, COLORS.TextPrimary)
	-- nameLabel.Size = UDim2.fromScale(1, 1)
	-- nameLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Columns Container
	local columnsContainer = Instance.new("Frame")
	columnsContainer.BackgroundTransparency = 1
	columnsContainer.Size = UDim2.fromScale(1, 1) -- Expanded to fill space
	columnsContainer.LayoutOrder = 2
	columnsContainer.Parent = contentFrame

	local columnsLayout = Instance.new("UIListLayout")
	columnsLayout.FillDirection = Enum.FillDirection.Horizontal
	columnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnsLayout.Padding = UDim.new(0, 0)
	columnsLayout.Parent = columnsContainer

	-- Left Column (Stats)
	local leftCol = Instance.new("Frame")
	leftCol.BackgroundTransparency = 1
	leftCol.Size = UDim2.fromScale(0.5, 1)
	leftCol.LayoutOrder = 1
	leftCol.Parent = columnsContainer

	local leftPadding = Instance.new("UIPadding")
	leftPadding.PaddingRight = UDim.new(0, 5)
	leftPadding.Parent = leftCol

	local leftList = Instance.new("UIListLayout")
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Padding = UDim.new(0, 0)
	leftList.Parent = leftCol

	createStatRow(leftCol, "Boost", tostring(math.floor((details.Boost or 0) * 100)) .. "%", 0.15).LayoutOrder = 1
	createStatRow(leftCol, "Rating", string.rep("⭐", math.clamp(details.Rating or 3, 1, 5)), 0.15).LayoutOrder = 2

	-- Right Column (Traits)
	local rightCol = Instance.new("Frame")
	rightCol.BackgroundTransparency = 1
	rightCol.Size = UDim2.fromScale(0.5, 1)
	rightCol.LayoutOrder = 2
	rightCol.Parent = columnsContainer

	local rightPadding = Instance.new("UIPadding")
	rightPadding.PaddingLeft = UDim.new(0, 5)
	rightPadding.Parent = rightCol

	local rightList = Instance.new("UIListLayout")
	rightList.SortOrder = Enum.SortOrder.LayoutOrder
	rightList.Padding = UDim.new(0, 0)
	rightList.Parent = rightCol

	local traitsHeader = createLabel(rightCol, "Traits", FONTS.Body, 0.15, COLORS.Accent)
	traitsHeader.LayoutOrder = 0

	if details.Traits and #details.Traits > 0 then
		for i, trait in ipairs(details.Traits) do
			local traitLabel = createLabel(rightCol, "• " .. trait, FONTS.Light, 0.12, COLORS.TextSecondary)
			traitLabel.LayoutOrder = i
		end
	else
		local noneLabel = createLabel(rightCol, "None", FONTS.Light, 0.12, COLORS.TextSecondary)
		noneLabel.LayoutOrder = 1
	end
end

function TenantProfileUI.Show(tenantId: string, residentModel: Model)
	if not billboard then
		TenantProfileUI.Init()
	end

	currentTenantId = tenantId
	currentAdornee = residentModel:FindFirstChild("Head") or residentModel.PrimaryPart

	if billboard and currentAdornee then
		billboard.Adornee = currentAdornee
		billboard.Enabled = true
		billboard.StudsOffset = Vector3.new(3.5, 0.5, 0)
		TweenService:Create(billboard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			StudsOffset = Vector3.new(3.5, 1.5, 0),
		}):Play()
	end

	clearContent()
	if contentFrame then
		createLabel(contentFrame, "Loading...", FONTS.Body, 0.2, COLORS.TextSecondary)
	end

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraSubject = residentModel
	end

	local details = TenantStore.GetTenant(Player.UserId, tenantId)
	if currentTenantId == tenantId and billboard and billboard.Enabled then
		if details then
			updateUI(details)
		else
			clearContent()
			if contentFrame then
				createLabel(contentFrame, "Unavailable", FONTS.Body, 0.2, COLORS.TextSecondary)
			end
		end
	end
end

function TenantProfileUI.Hide()
	if billboard then
		billboard.Enabled = false
		-- billboard.Adornee = nil -- Cannot set to nil if typed as Instance
	end
	currentTenantId = nil
	currentAdornee = nil

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraSubject = Player.Character
	end
end

function TenantProfileUI.Toggle(tenantId: string, residentModel: Model)
	if billboard and billboard.Enabled and currentTenantId == tenantId then
		TenantProfileUI.Hide()
	else
		TenantProfileUI.Show(tenantId, residentModel)
	end
end

return TenantProfileUI
