# Roblox GBA emulator
Edited Lua GBA emulator for roblox script utils to run

The default controls for PC are
* Arrow keys is GBA dpad
* X is A
* Z is B
* Enter is Start
* Right Shift is Select


The default controls for controller are
* Dpad is GBA dpad
* Y is A
* X is B

(I haven't added the start/select yet sue me)

### Example script
replace sml.gb with any .gb file in workspace
```lua
ROMName = 'sml.gb'

exampleLoader = game:HttpGet(
    'https://raw.githubusercontent.com/Roblox-Thot/RBX-gameboy/refs/heads/main/example.lua'
)

-- Disable 3d for this example since it's full screen anyway
game:GetService('RunService'):Set3dRenderingEnabled(false)
print('-----------------')
loadfile(exampleLoader)(ROMName)
```

# Credits
[MaximumADHD](https://github.com/MaximumADHD/Roblox-Luau-GB) for the example Roblox use

[zeta0134](https://github.com/zeta0134/LuaGB) for the Lua GB emulator code