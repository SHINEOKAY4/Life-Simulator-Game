--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentAppearanceConfig = require(ReplicatedStorage.Shared.Configurations.ResidentAppearanceConfig)

export type AppearanceIds = {
	SkinToneId: string,
	HairId: string,
	FaceId: string,
	TopId: string,
	PantsId: string,
}

export type ApplyOptions = {
	AnchorRootPart: boolean?,
	FreezeHumanoid: boolean?,
}

local ResidentAppearanceUtils = {}

local function resolveAppearanceIds(appearance: AppearanceIds?)
	local resolvedAppearance = appearance or (ResidentAppearanceConfig.GetDefaultSelection() :: any)
	local skinTone = ResidentAppearanceConfig.ResolveSkinTone(resolvedAppearance.SkinToneId)
	local hair = ResidentAppearanceConfig.ResolveHair(resolvedAppearance.HairId)
	local face = ResidentAppearanceConfig.ResolveFace(resolvedAppearance.FaceId)
	local top = ResidentAppearanceConfig.ResolveTop(resolvedAppearance.TopId)
	local pants = ResidentAppearanceConfig.ResolvePants(resolvedAppearance.PantsId)

	return skinTone, hair, face, top, pants
end

function ResidentAppearanceUtils.ApplyToModel(
	model: Model,
	appearance: AppearanceIds?,
	ageNumeric: number?,
	options: ApplyOptions?
): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local skinTone, hair, face, top, pants = resolveAppearanceIds(appearance)
	local ageDefinition = ResidentAppearanceConfig.ResolveAgeByNumeric(ageNumeric)

	local description = humanoid:GetAppliedDescription()
	description.HeadColor = skinTone.Color
	description.LeftArmColor = skinTone.Color
	description.RightArmColor = skinTone.Color
	description.LeftLegColor = skinTone.Color
	description.RightLegColor = skinTone.Color
	description.TorsoColor = skinTone.Color
	description.HairAccessory = tostring(hair.AssetId)
	description.Face = face.AssetId
	description.Shirt = top.AssetId
	description.Pants = pants.AssetId
	description.BodyTypeScale = ageDefinition.Scales.BodyType
	description.HeightScale = ageDefinition.Scales.Height
	description.WidthScale = ageDefinition.Scales.Width
	description.DepthScale = ageDefinition.Scales.Depth
	description.HeadScale = ageDefinition.Scales.Head
	description.ProportionScale = ageDefinition.Scales.Proportion

	humanoid:ApplyDescription(description)

	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.HeadColor = skinTone.BrickColor
		bodyColors.LeftArmColor = skinTone.BrickColor
		bodyColors.RightArmColor = skinTone.BrickColor
		bodyColors.LeftLegColor = skinTone.BrickColor
		bodyColors.RightLegColor = skinTone.BrickColor
		bodyColors.TorsoColor = skinTone.BrickColor
	end

	local anchorRootPart = if options and options.AnchorRootPart == true then true else false
	local freezeHumanoid = if options and options.FreezeHumanoid == true then true else false

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		humanoidRootPart.Anchored = anchorRootPart
	end

	if freezeHumanoid then
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	return true
end

return ResidentAppearanceUtils
