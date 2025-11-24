--!strict
-- Client/Utilities/UIBuilder.luau
-- Utility for creating UI elements with common patterns, reducing boilerplate

local UIBuilder = {}

export type FrameProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	BackgroundColor3: Color3?,
	BackgroundTransparency: number?,
	BorderSizePixel: number?,
	ClipsDescendants: boolean?,
	ZIndex: number?,
	Parent: Instance?,
}

export type TextLabelProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Font: Enum.Font?,
	TextSize: number?,
	TextColor3: Color3?,
	TextXAlignment: Enum.TextXAlignment?,
	TextYAlignment: Enum.TextYAlignment?,
	Text: string?,
	TextWrapped: boolean?,
	BackgroundTransparency: number?,
	Parent: Instance?,
}

export type TextButtonProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Font: Enum.Font?,
	TextSize: number?,
	TextColor3: Color3?,
	Text: string?,
	AutoButtonColor: boolean?,
	BackgroundColor3: Color3?,
	BackgroundTransparency: number?,
	BorderSizePixel: number?,
	Parent: Instance?,
}

export type CornerProps = {
	CornerRadius: UDim?,
	Parent: Instance?,
}

export type StrokeProps = {
	Color: Color3?,
	Thickness: number?,
	Transparency: number?,
	ApplyStrokeMode: Enum.ApplyStrokeMode?,
	Parent: Instance?,
}

local function applyProps<T>(instance: Instance, props: T)
	for key, value in props :: any do
		if key ~= "Parent" and value ~= nil then
			(instance :: any)[key] = value
		end
	end

	local parent = (props :: any).Parent
	if parent then
		instance.Parent = parent
	end
end

function UIBuilder.Frame(props: FrameProps): Frame
	local frame = Instance.new("Frame")
	applyProps(frame, props)
	return frame
end

function UIBuilder.TextLabel(props: TextLabelProps): TextLabel
	local label = Instance.new("TextLabel")
	applyProps(label, props)
	return label
end

function UIBuilder.TextButton(props: TextButtonProps): TextButton
	local button = Instance.new("TextButton")
	applyProps(button, props)
	return button
end

function UIBuilder.Corner(props: CornerProps): UICorner
	local corner = Instance.new("UICorner")
	applyProps(corner, props)
	return corner
end

function UIBuilder.Stroke(props: StrokeProps): UIStroke
	local stroke = Instance.new("UIStroke")
	applyProps(stroke, props)
	return stroke
end

function UIBuilder.ListLayout(props: {
	FillDirection: Enum.FillDirection?,
	HorizontalAlignment: Enum.HorizontalAlignment?,
	VerticalAlignment: Enum.VerticalAlignment?,
	Padding: UDim?,
	SortOrder: Enum.SortOrder?,
	Parent: Instance?,
}): UIListLayout
	local layout = Instance.new("UIListLayout")
	applyProps(layout, props)
	return layout
end

function UIBuilder.Padding(props: {
	PaddingTop: UDim?,
	PaddingBottom: UDim?,
	PaddingLeft: UDim?,
	PaddingRight: UDim?,
	Parent: Instance?,
}): UIPadding
	local padding = Instance.new("UIPadding")
	applyProps(padding, props)
	return padding
end

return UIBuilder
