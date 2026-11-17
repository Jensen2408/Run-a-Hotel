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

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

------------------------------------------------------------------------
-- Idle animation: every icon sways, breathes and wiggles now and then.
-- Covers HUD icons (Icons.create) and world icons made on the server
-- (UiAssets.applyTo tags them "UiIcon"). Code that rotates an icon itself
-- still works: a rotation written by someone else becomes the new base.
-- Opt out with Icons.create(name, { Animate = false }) or the attribute
-- NoIdle = true.
------------------------------------------------------------------------

-- Strong keys on purpose: a weak table would lose world icons, whose Lua
-- wrappers can be collected while the instances still exist. Entries are
-- dropped when the icon leaves the game (render loop) or is destroyed.
local animated = {}

function Icons.animate(img: ImageLabel)
	if animated[img] or img:GetAttribute("NoIdle") then
		return
	end
	local rng = Random.new()
	local scale = img:FindFirstChild("IconIdle") or Instance.new("UIScale")
	scale.Name = "IconIdle"
	scale.Parent = img
	img.Destroying:Once(function()
		animated[img] = nil
	end)
	animated[img] = {
		phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(1.7, 2.6),
		amp = rng:NextNumber(3, 5),
		base = img.Rotation,
		last = img.Rotation,
		scale = scale,
		wiggleAt = os.clock() + rng:NextNumber(1.5, 8),
		rng = rng,
	}
end

if RunService:IsClient() then
	for _, inst in ipairs(CollectionService:GetTagged(UiAssets.ICON_TAG)) do
		if inst:IsA("ImageLabel") then
			Icons.animate(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(UiAssets.ICON_TAG):Connect(function(inst)
		if inst:IsA("ImageLabel") then
			Icons.animate(inst)
		end
	end)
	-- After the other render-step code, so their rotations are seen as the base.
	RunService:BindToRenderStep("MotelIconIdle", Enum.RenderPriority.Last.Value + 10, function()
		local t = os.clock()
		for img, st in pairs(animated) do
			if not img:IsDescendantOf(game) then
				animated[img] = nil
			elseif img.Visible then
				if math.abs(img.Rotation - st.last) > 0.01 then
					st.base = img.Rotation
				end
				local rot = math.sin(t * st.speed + st.phase) * st.amp
				local w = t - st.wiggleAt
				if w >= 0 then
					if w < 0.6 then
						rot += math.sin(w * 30) * 14 * (1 - w / 0.6)
					else
						st.wiggleAt = t + st.rng:NextNumber(4, 9)
					end
				end
				local value = st.base + rot
				img.Rotation = value
				st.last = value
				st.scale.Scale = 1 + math.sin(t * st.speed * 1.3 + st.phase) * 0.045
			end
		end
	end)
end

-- props: Name, Size, Position, AnchorPoint, ZIndex, Rotation, Parent, FallbackColor,
-- Animate (default true: idle animation)
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
	if props.Animate == false then
		img:SetAttribute("NoIdle", true)
	end
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
