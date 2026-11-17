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
-- Action animation: icons stay still at idle and play a short wiggle +
-- pop when something happens to them:
--   * Icons.bump(icon) / Icons.bumpIn(container) (called by pop and press
--     helpers in Hud and UiKit, so value changes and button presses animate)
--   * the icon image changes (e.g. a room sign switching READY -> CLEAN,
--     also for world icons made on the server)
--   * the icon becomes visible
-- Covers HUD icons (Icons.create) and world icons (UiAssets.applyTo tags
-- them "UiIcon"). Opt out with Icons.create(name, { Animate = false }) or
-- the attribute NoIdle = true (e.g. pointer arrows rotated by code).
------------------------------------------------------------------------

local BUMP_TIME = 0.6

-- Icons currently animating. Strong keys on purpose (a weak table could
-- lose world icons whose Lua wrappers get collected); entries end with the
-- animation or when the icon leaves the game.
local active = {}
local hooked = setmetatable({}, { __mode = "k" })

local function iconOf(target): ImageLabel?
	if typeof(target) == "table" and target.frame then
		return target.frame
	end
	if typeof(target) == "Instance" and target:IsA("ImageLabel") then
		return target
	end
	return nil
end

-- Plays the action animation on one icon (Icon object or ImageLabel).
function Icons.bump(target)
	local img = iconOf(target)
	if not img or img:GetAttribute("NoIdle") then
		return
	end
	local st = active[img]
	if st then
		st.start = os.clock() -- restart, keep the original base rotation
		return
	end
	local scale = img:FindFirstChild("IconFx") or Instance.new("UIScale")
	scale.Name = "IconFx"
	scale.Parent = img
	active[img] = { start = os.clock(), base = img.Rotation, last = img.Rotation, scale = scale }
end

-- Bumps every icon inside a container (and the container if it is one).
function Icons.bumpIn(container: Instance?)
	if not container then
		return
	end
	if container:HasTag(UiAssets.ICON_TAG) then
		Icons.bump(container)
	end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("ImageLabel") and d:HasTag(UiAssets.ICON_TAG) then
			Icons.bump(d)
		end
	end
end

-- Automatic triggers for one icon: image changed, became visible.
local function hook(img: ImageLabel)
	if hooked[img] then
		return
	end
	hooked[img] = true
	img:GetPropertyChangedSignal("ImageRectOffset"):Connect(function()
		Icons.bump(img)
	end)
	img:GetPropertyChangedSignal("Visible"):Connect(function()
		if img.Visible then
			Icons.bump(img)
		end
	end)
end

if RunService:IsClient() then
	for _, inst in ipairs(CollectionService:GetTagged(UiAssets.ICON_TAG)) do
		if inst:IsA("ImageLabel") then
			hook(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(UiAssets.ICON_TAG):Connect(function(inst)
		if inst:IsA("ImageLabel") then
			hook(inst)
		end
	end)
	-- After the other render-step code, so their rotations are seen as the base.
	RunService:BindToRenderStep("MotelIconFx", Enum.RenderPriority.Last.Value + 10, function()
		local now = os.clock()
		for img, st in pairs(active) do
			local t = now - st.start
			if not img:IsDescendantOf(game) then
				active[img] = nil
			else
				if math.abs(img.Rotation - st.last) > 0.01 then
					st.base = img.Rotation -- someone else rotated it meanwhile
				end
				if t >= BUMP_TIME then
					img.Rotation = st.base
					st.scale.Scale = 1
					active[img] = nil
				else
					local k = 1 - t / BUMP_TIME
					local value = st.base + math.sin(t * 30) * 14 * k
					img.Rotation = value
					st.last = value
					st.scale.Scale = 1 + 0.28 * math.sin(math.pi * math.min(t / 0.35, 1)) * k
				end
			end
		end
	end)
end

-- props: Name, Size, Position, AnchorPoint, ZIndex, Rotation, Parent, FallbackColor,
-- Animate (default true: action animation)
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
