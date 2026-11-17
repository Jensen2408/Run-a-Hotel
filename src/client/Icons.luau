--!nonstrict
-- Icons from the UI icon sheet (UiAssets.iconSheet), with an emoji/text
-- fallback while the sheet has not been uploaded yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiAssets"))

local Icons = {}

local OUTLINE = Color3.fromRGB(46, 32, 22)

export type Icon = {
	frame: ImageLabel,
	fallback: TextLabel,
	name: string?,
	set: (Icon, string) -> (),
}

local function setIcon(self, name: string)
	if self.name == name then
		return
	end
	self.name = name
	local cell = UiAssets.icons[name]
	if UiAssets.iconSheet ~= "" and cell then
		local size = UiAssets.cellSize - UiAssets.cellInset * 2
		self.frame.Image = UiAssets.iconSheet
		self.frame.ImageRectSize = Vector2.new(size, size)
		self.frame.ImageRectOffset = Vector2.new(
			(cell[1] - 1) * UiAssets.cellSize + UiAssets.cellInset,
			(cell[2] - 1) * UiAssets.cellSize + UiAssets.cellInset
		)
		self.fallback.Visible = false
	else
		self.frame.Image = ""
		local text = UiAssets.fallback[name] or "?"
		self.fallback.Text = text
		-- Outline plain glyphs ($, ★); emoji look better without one.
		self.fallback.UIStroke.Enabled = text == "$" or text == "★"
		self.fallback.Visible = true
	end
end

-- props: Name, Size, Position, AnchorPoint, ZIndex, Parent, FallbackColor
function Icons.create(name: string, props): Icon
	local img = Instance.new("ImageLabel")
	img.Name = props.Name or "Icon"
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = props.Size or UDim2.fromScale(1, 1)
	img.Position = props.Position or UDim2.new()
	img.AnchorPoint = props.AnchorPoint or Vector2.zero
	img.ZIndex = props.ZIndex or 1
	local fb = Instance.new("TextLabel")
	fb.Name = "Fallback"
	fb.BackgroundTransparency = 1
	fb.Size = UDim2.fromScale(1, 1)
	fb.Font = Enum.Font.FredokaOne
	fb.TextScaled = true
	fb.TextColor3 = props.FallbackColor or Color3.new(1, 1, 1)
	fb.ZIndex = img.ZIndex
	fb.Parent = img
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = OUTLINE
	stroke.Parent = fb
	img.Parent = props.Parent
	local icon = { frame = img, fallback = fb, name = nil, set = setIcon }
	icon:set(name)
	return icon :: any
end

return Icons
