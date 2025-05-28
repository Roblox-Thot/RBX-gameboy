local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Gameboy = loadfile('gayboy/!init.lua')()

local enabled = pcall(function()
	AssetService:CreateEditableImage()
end)

if not enabled then
	warn("EditableImage is not enabled! Go to 'Game Settings > Security' and check 'Allow Mesh / Image APIs' to use the Gameboy Emulator!")
	return
end


local WIDTH = 160
local HEIGHT = 144


local gui = Instance.new('ScreenGui',game:GetService('CoreGui'))
gui.ResetOnSpawn = false
gui.Name = "Gameboy Emulator"

local gb = Gameboy.new()
local size = Vector2.new(WIDTH, HEIGHT)

local window = Instance.new("ImageLabel")
window.Position = UDim2.fromScale(0.5, 0.5)
window.BackgroundColor3 = Color3.new()
window.AnchorPoint = Vector2.one / 2
window.Size = UDim2.fromScale(1, 1)
window.ResampleMode = "Pixelated"
window.Parent = gui

local aspectRatio = Instance.new("UIAspectRatioConstraint")
aspectRatio.AspectRatio = WIDTH / HEIGHT
aspectRatio.Parent = window

local screen = AssetService:CreateEditableImage({ Size = size })
window.ImageContent = Content.fromObject(screen)

local ticker = 0
local runner: thread?
local lastTick = os.clock()

local frameBuffer = buffer.create(WIDTH * HEIGHT * 4)
buffer.fill(frameBuffer, 0, 255)

local inputMap = {
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.Right] = "Right",

	[Enum.KeyCode.X] = "A",
	[Enum.KeyCode.Z] = "B",

	[Enum.KeyCode.Return] = "Start",
	[Enum.KeyCode.RightShift] = "Select",

	[Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.DPadRight] = "Right",

	[Enum.KeyCode.ButtonY] = "A",
	[Enum.KeyCode.ButtonX] = "B",
}

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	local key = inputMap[input.KeyCode]

	if key then
		gb.input.keys[key] = 1
		gb.input.update()
	end
end

local function onInputEnded(input: InputObject, gameProcessed: boolean)
	local key = inputMap[input.KeyCode]

	if key then
		gb.input.keys[key] = 0
		gb.input.update()
	end
end

local function runThread()
	local self = assert(runner)
	assert(self == coroutine.running())

	while true do
		local now = os.clock()
		local dt = now - lastTick

		lastTick = now
		ticker = math.min(ticker + dt * 60, 3)

		while ticker >= 1 do
			for i = 1, HEIGHT do
				if self ~= runner then
					return
				end

				debug.profilebegin(`hblank {i}`)
				gb:run_until_hblank()
				debug.profileend()
			end

			ticker -= 1
		end

		-- read pixels
		local pixels = gb.graphics.game_screen
		local i = 0

		for y = 0, HEIGHT - 1 do
			for x = 0, WIDTH - 1 do
				local pixel = pixels[y][x]
				buffer.writeu8(frameBuffer, i, pixel[1])
				buffer.writeu8(frameBuffer, i + 1, pixel[2])
				buffer.writeu8(frameBuffer, i + 2, pixel[3])
				buffer.writeu8(frameBuffer, i + 3, 255)
				
				i += 4
			end
		end
		
		screen:WritePixelsBuffer(Vector2.zero, size, frameBuffer)
		RunService.Heartbeat:Wait()
	end
end

local file = readfile(...)
gb.cartridge.load(file)
gb:reset()

gui.Enabled = true
runner = task.defer(runThread)


local inputService = cloneref(game:GetService('UserInputService'))
inputService.InputBegan:Connect(onInputBegan)
inputService.InputEnded:Connect(onInputEnded)
