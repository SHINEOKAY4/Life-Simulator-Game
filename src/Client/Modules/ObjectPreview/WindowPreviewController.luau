--!strict

local Renderer = require(script.Parent.Renderer)
local Types = require(script.Parent.Types)

local WindowPreviewController = {}

type WindowCutoutPose = Types.WindowCutoutPose

local activePose: WindowCutoutPose? = nil
local activePreview: any = nil
local previewVisible = true
local HIDDEN_PREVIEW_CFRAME = CFrame.new(0, 1e6, 0)

local function setHighlight(model: Model?, highlight: Highlight?, adorneeEnabled: boolean)
	if not highlight then
		return
	end
	if adorneeEnabled and model then
		highlight.Adornee = model
	elseif highlight.Adornee == model then
		highlight.Adornee = nil
	end
end

function WindowPreviewController.IsWindowSpec(spec: any?): boolean
	if typeof(spec) ~= "table" then
		return false
	end
	if spec.RequiresExistingWall ~= true then
		return false
	end
	return spec.WallVariant == "Window"
end

function WindowPreviewController.HideModel(model: Model?, highlight: Highlight?)
	if not model then
		return
	end
	setHighlight(model, highlight, false)
	model:PivotTo(HIDDEN_PREVIEW_CFRAME)
	previewVisible = false
end

function WindowPreviewController.ShowModel(model: Model?, highlight: Highlight?)
	if not model then
		return
	end
	setHighlight(model, highlight, true)
	previewVisible = true
end

function WindowPreviewController.Clear(model: Model?, highlight: Highlight?)
	if activePreview then
		Renderer.ClearWindowPreview(activePreview)
		activePreview = nil
	end
	activePose = nil
	previewVisible = true
	WindowPreviewController.ShowModel(model, highlight)
end

function WindowPreviewController.RenderOnWall(params: {
	model: Model,
	wallPart: BasePart,
	pose: Types.WindowCutoutPose,
	windowConfig: Renderer.WindowCutoutConfig?,
	pivotRotation: CFrame,
	highlight: Highlight?,
}): boolean
	if activePreview then
		Renderer.ClearWindowPreview(activePreview)
		activePreview = nil
	end

	activePreview = Renderer.PreviewWindowOnWall(
		params.model,
		params.wallPart,
		params.pose,
		params.windowConfig,
		params.pivotRotation
	)

	if not activePreview then
		activePose = nil
		WindowPreviewController.HideModel(params.model, params.highlight)
		return false
	end

	activePose = params.pose
	WindowPreviewController.ShowModel(params.model, params.highlight)
	return true
end

function WindowPreviewController.GetPose(): Types.WindowCutoutPose?
	return activePose
end

function WindowPreviewController.IsVisible(): boolean
	return previewVisible
end

return WindowPreviewController
