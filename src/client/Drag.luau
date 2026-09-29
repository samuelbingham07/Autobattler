-- Drag and drop for UI cards, with mouse or touch.
--
-- Press on a registered card and move a few pixels: a "ghost" follows the
-- pointer, and releasing it over a registered drop target calls onDrop.
-- Press and release without moving counts as a click (onClick).
--
-- Positions come from InputObject.Position, which is in the same screen space
-- as GuiObject.AbsolutePosition for a ScreenGui with IgnoreGuiInset = false.

local UserInputService = game:GetService("UserInputService")

local Widgets = require(script.Parent.Widgets)

local DRAG_THRESHOLD = 6 -- pixels of movement before a press becomes a drag

export type Handlers = {
	onClick: (source: any) -> (),
	onDrop: (source: any, target: any) -> (),
	onDragStart: (source: any) -> (),
	onDragEnd: () -> (),
}

type Pending = {
	source: any,
	start: Vector2,
	text: string,
	color: Color3,
}

local Drag = {}
Drag.__index = Drag

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function contains(gui: GuiObject, point: Vector2): boolean
	local position, size = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

function Drag.new(screenGui: ScreenGui, handlers: Handlers)
	local self = setmetatable({
		screenGui = screenGui,
		handlers = handlers,
		targets = {} :: { { gui: GuiObject, target: any } },
		pending = nil :: Pending?,
		ghost = nil :: Frame?,
	}, Drag)

	UserInputService.InputChanged:Connect(function(input)
		if isMove(input) then
			self:_move(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			self:_release(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	return self
end

-- Make a card draggable. `text` and `color` style the ghost.
function Drag:register(card: GuiObject, source: any, text: string, color: Color3)
	card.InputBegan:Connect(function(input)
		if isPress(input) then
			self.pending = {
				source = source,
				start = Vector2.new(input.Position.X, input.Position.Y),
				text = text,
				color = color,
			}
		end
	end)
end

-- Replace the drop targets. Earlier entries win when targets overlap,
-- so list specific ones (single slots) before general ones (whole rows).
function Drag:setTargets(targets: { { gui: GuiObject, target: any } })
	self.targets = targets
end

function Drag:isDragging(): boolean
	return self.ghost ~= nil
end

-- Drop whatever is being dragged without doing anything (e.g. the UI is being rebuilt).
function Drag:cancel()
	if self.ghost then
		self.ghost:Destroy()
		self.ghost = nil
		self.handlers.onDragEnd()
	end
	self.pending = nil
end

function Drag:_move(point: Vector2)
	local pending = self.pending
	if not pending then
		return
	end
	if not self.ghost then
		if (point - pending.start).Magnitude < DRAG_THRESHOLD then
			return
		end
		local ghost = Widgets.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(120, 44),
			BackgroundColor3 = Widgets.COLORS.card,
			BackgroundTransparency = 0.1,
			ZIndex = 100,
			Parent = self.screenGui,
		})
		Widgets.corner(ghost)
		Widgets.stroke(ghost, pending.color, 2)
		Widgets.label(ghost, pending.text, 14, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 101,
		})
		self.ghost = ghost
		self.handlers.onDragStart(pending.source)
	end
	local ghost = self.ghost :: Frame
	ghost.Position = UDim2.fromOffset(point.X, point.Y)
end

function Drag:_release(point: Vector2)
	local pending = self.pending
	if not pending then
		return
	end
	self.pending = nil

	local ghost = self.ghost
	if not ghost then
		self.handlers.onClick(pending.source)
		return
	end
	ghost:Destroy()
	self.ghost = nil

	-- Find the target before onDragEnd, which hides drag-only targets like the sell area.
	local dropped = nil
	for _, entry in self.targets do
		if entry.gui.Visible and entry.gui.Parent and contains(entry.gui, point) then
			dropped = entry.target
			break
		end
	end
	self.handlers.onDragEnd()
	if dropped then
		self.handlers.onDrop(pending.source, dropped)
	end
end

return Drag
