--!nonstrict
-- Icons from the UI icon sheets (UiAssets.iconSheets), with an emoji/text
-- fallback. Each icon points at its sheet and keeps the fallback visible
-- until its ImageLabel reports IsLoaded, so a sheet that is not uploaded
-- yet, still in moderation, or failed to load never leaves an empty icon.
--
-- Notes:
--   ContentProvider:PreloadAsync with a string asset ID reports Failure for
--   these sheets even when ImageLabels load them, so it is not used.
--   The ImageLabel stays opaque: Roblox skips loading fully transparent
--   images, and an unloaded image draws nothing anyway.

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

-- Icons waiting for IsLoaded (its property-changed signal is unreliable).
local pending = {}

local function refreshFallback(self)
	local hasSheet = self.frame.Image ~= ""
	local useSheet = hasSheet and self.frame.IsLoaded
	self.fallback.Visible = not useSheet
	pending[self] = if hasSheet and not useSheet then true else nil
end

task.spawn(function()
	while true do
		task.wait(0.5)
		for icon in pairs(pending) do
			if not icon.frame.Parent then
				pending[icon] = nil
			elseif icon.frame.IsLoaded then
				refreshFallback(icon)
			end
		end
	end
end)

local function setIcon(self, name: string)
	if self.name == name then
		return
	end
	self.name = name
	UiAssets.applyTo(self.frame, name)
	local text = UiAssets.fallback[name] or "?"
	self.fallback.Text = text
	-- Outline plain glyph fallbacks; emoji look better without one.
	self.fallback.UIStroke.Enabled = utf8.len(text) == 1 and text:byte() < 0xF0
	refreshFallback(self)
end

-- props: Name, Size, Position, AnchorPoint, ZIndex, Rotation, Parent, FallbackColor
function Icons.create(name: string, props): Icon
	local img = Instance.new("ImageLabel")
	img.Name = props.Name or "Icon"
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = props.Size or UDim2.fromScale(1, 1)
	img.Position = props.Position or UDim2.new()
	img.AnchorPoint = props.AnchorPoint or Vector2.zero
	img.ZIndex = props.ZIndex or 1
	img.Rotation = props.Rotation or 0
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
