-- Small helpers for building UI in code.

local Widgets = {}

Widgets.COLORS = {
	panel = Color3.fromRGB(22, 24, 32),
	card = Color3.fromRGB(34, 37, 48),
	cardHover = Color3.fromRGB(46, 50, 64),
	empty = Color3.fromRGB(28, 30, 38),
	text = Color3.fromRGB(240, 240, 245),
	muted = Color3.fromRGB(160, 165, 180),
	accent = Color3.fromRGB(255, 205, 90),
	good = Color3.fromRGB(120, 220, 140),
	bad = Color3.fromRGB(240, 100, 100),
	team = Color3.fromRGB(80, 140, 240),
	enemy = Color3.fromRGB(230, 90, 90),
	gold = Color3.fromRGB(250, 200, 70),
	xp = Color3.fromRGB(150, 100, 230),
	fight = Color3.fromRGB(225, 120, 40),
	button = Color3.fromRGB(70, 74, 92),
}

-- Border colors by unit cost, like TFT: grey, green, blue, purple, gold.
Widgets.TIER_COLORS = {
	[1] = Color3.fromRGB(150, 150, 160),
	[2] = Color3.fromRGB(70, 180, 100),
	[3] = Color3.fromRGB(70, 130, 230),
	[4] = Color3.fromRGB(170, 90, 230),
	[5] = Color3.fromRGB(240, 190, 60),
}

-- Create an instance and set its properties. Parent is set last, which is
-- the recommended order (it avoids extra work as properties change).
function Widgets.create(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

function Widgets.corner(parent: Instance, radius: number?)
	Widgets.create("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

function Widgets.stroke(parent: Instance, color: Color3, thickness: number?): UIStroke
	return Widgets.create("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Widgets.padding(parent: Instance, pixels: number)
	Widgets.create("UIPadding", {
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels),
		PaddingRight = UDim.new(0, pixels),
		Parent = parent,
	})
end

function Widgets.list(parent: Instance, horizontal: boolean, gap: number, centered: boolean?)
	Widgets.create("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = if centered then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

function Widgets.label(parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local label = Widgets.create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 4),
		Text = text,
		TextSize = size,
		Font = Enum.Font.GothamBold,
		TextColor3 = Widgets.COLORS.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = parent,
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

-- A plain clickable button. Disabled buttons are dimmed and ignore clicks.
function Widgets.button(
	parent: Instance,
	text: string,
	color: Color3,
	size: UDim2,
	enabled: boolean,
	onClick: () -> ()
): TextButton
	local button = Widgets.create("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		BackgroundTransparency = if enabled then 0 else 0.65,
		AutoButtonColor = enabled,
		Text = text,
		TextColor3 = Widgets.COLORS.text,
		TextTransparency = if enabled then 0 else 0.45,
		TextSize = 15,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		Parent = parent,
	})
	Widgets.corner(button)
	if enabled then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Remove everything in a container except its layout helpers.
function Widgets.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

return Widgets
