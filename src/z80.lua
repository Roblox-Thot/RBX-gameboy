--!native

local apply_arithmetic = gbloadfile('gayboy/z80/arithmetic.lua')()
local apply_bitwise = gbloadfile('gayboy/z80/bitwise.lua')()
local apply_call = gbloadfile('gayboy/z80/call.lua')()
local apply_cp = gbloadfile('gayboy/z80/cp.lua')()
local apply_inc_dec = gbloadfile('gayboy/z80/inc_dec.lua')()
local apply_jp = gbloadfile('gayboy/z80/jp.lua')()
local apply_ld = gbloadfile('gayboy/z80/ld.lua')()
local apply_rl_rr_cb = gbloadfile('gayboy/z80/rl_rr_cb.lua')()
local apply_stack = gbloadfile('gayboy/z80/stack.lua')()

local Registers = gbloadfile('gayboy/z80/registers.lua')()

local Z80 = {}

function Z80.new(modules)
    local z80 = {}

    local interrupts = modules.interrupts
    local io = modules.io
    local memory = modules.memory
    local timers = modules.timers

    -- local references, for shorter code
    local read_byte = memory.read_byte
    local write_byte = memory.write_byte

    z80.registers = Registers.new()
    local reg = z80.registers
    local flags = reg.flags

    -- Intentionally bad naming convention: I am NOT typing "registers"
    -- a bazillion times. The exported symbol uses the full name as a
    -- reasonable compromise.
    z80.halted = 0

    local add_cycles_normal = function(cycles)
        timers.system_clock = timers.system_clock + cycles
    end

    local add_cycles_double = function(cycles)
        timers.system_clock = timers.system_clock + cycles / 2
    end

    z80.add_cycles = add_cycles_normal

    z80.double_speed = false

    z80.reset = function(gameboy)
        -- Initialize registers to what the GB's
        -- iternal state would be after executing
        -- BIOS code

        flags.z = true
        flags.n = false
        flags.h = true
        flags.c = true

        if gameboy.type == gameboy.types.color then
            reg.a = 0x11
        else
            reg.a = 0x01
        end

        reg.b = 0x00
        reg.c = 0x13
        reg.d = 0x00
        reg.e = 0xD8
        reg.h = 0x01
        reg.l = 0x4D
        reg.pc = 0x100 --entrypoint for GB games
        reg.sp = 0xFFFE

        z80.halted = 0

        z80.double_speed = false
        z80.add_cycles = add_cycles_normal
        timers:set_normal_speed()
    end

    z80.save_state = function()
        local state = {}
        state.double_speed = z80.double_speed
        state.registers = z80.registers
        state.halted = z80.halted
        return state
    end

    z80.load_state = function(state)
        -- Note: doing this explicitly for safety, so as
        -- not to replace the table with external, possibly old / wrong structure
        flags.z = state.registers.flags.z
        flags.n = state.registers.flags.n
        flags.h = state.registers.flags.h
        flags.c = state.registers.flags.c

        z80.registers.a = state.registers.a
        z80.registers.b = state.registers.b
        z80.registers.c = state.registers.c
        z80.registers.d = state.registers.d
        z80.registers.e = state.registers.e
        z80.registers.h = state.registers.h
        z80.registers.l = state.registers.l
        z80.registers.pc = state.registers.pc
        z80.registers.sp = state.registers.sp

        z80.double_speed = state.double_speed
        if z80.double_speed then
            timers:set_double_speed()
        else
            timers:set_normal_speed()
        end
        z80.halted = state.halted
    end

    io.write_mask[0x4D] = 0x01

    local opcodes = {}
    local opcode_cycles = {}

    -- Initialize the opcode_cycles table with 4 as a base cycle, so we only
    -- need to care about variations going forward
    for i = 0x00, 0xFF do
        opcode_cycles[i] = 4
    end

    function z80.read_at_hl()
        return memory.block_map[reg.h * 0x100][reg.h * 0x100 + reg.l]
    end

    function z80.set_at_hl(value)
        memory.block_map[reg.h * 0x100][reg.h * 0x100 + reg.l] = value
    end

    function z80.read_nn()
        local nn = read_byte(reg.pc)
        reg.pc = reg.pc + 1
        return nn
    end

    local read_nn = z80.read_nn

    apply_arithmetic(opcodes, opcode_cycles, z80, memory)
    apply_bitwise(opcodes, opcode_cycles, z80, memory)
    apply_call(opcodes, opcode_cycles, z80, memory, interrupts)
    apply_cp(opcodes, opcode_cycles, z80, memory)
    apply_inc_dec(opcodes, opcode_cycles, z80, memory)
    apply_jp(opcodes, opcode_cycles, z80, memory)
    apply_ld(opcodes, opcode_cycles, z80, memory)
    apply_rl_rr_cb(opcodes, opcode_cycles, z80, memory)
    apply_stack(opcodes, opcode_cycles, z80, memory)

    -- ====== GMB CPU-Controlcommands ======
    -- ccf
    opcodes[0x3F] = function()
        flags.c = not flags.c
        flags.n = false
        flags.h = false
    end

    -- scf
    opcodes[0x37] = function()
        flags.c = true
        flags.n = false
        flags.h = false
    end

    -- nop
    opcodes[0x00] = function() end

    -- halt
    opcodes[0x76] = function()
        --if interrupts_enabled == 1 then
        --print("Halting!")
        z80.halted = 1
        --else
        --print("Interrupts not enabled! Not actually halting...")
        --end
    end

    -- stop
    opcodes[0x10] = function()
        -- The stop opcode should always, for unknown reasons, be followed
        -- by an 0x00 data byte. If it isn't, this may be a sign that the
        -- emulator has run off the deep end, and this isn't a real STOP
        -- instruction.
        -- TODO: Research real hardware's behavior in these cases
        local stop_value = read_nn()

        if stop_value == 0x00 then
            print("STOP instruction not followed by NOP!")
        else
            print("Unimplemented WEIRDNESS after 0x10")
        end

        if bit32.band(io.ram[0x4D], 0x01) ~= 0 then
            --speed switch!
            print("Switching speeds!")
            if z80.double_speed then
                z80.add_cycles = add_cycles_normal
                z80.double_speed = false
                io.ram[0x4D] = bit32.band(io.ram[0x4D], 0x7E) + 0x00
                timers:set_normal_speed()
                print("Switched to Normal Speed")
            else
                z80.add_cycles = add_cycles_double
                z80.double_speed = true
                io.ram[0x4D] = bit32.band(io.ram[0x4D], 0x7E) + 0x80
                timers:set_double_speed()
                print("Switched to Double Speed")
            end
        end
    end

    -- di
    opcodes[0xF3] = function()
        interrupts.disable()
        --print("Disabled interrupts with DI")
    end

    z80.service_interrupt = function()
        local fired = bit32.band(io.ram[0xFF], io.ram[0x0F])
        if fired ~= 0 then
            z80.halted = 0
            if interrupts.enabled ~= 0 then
                -- First, disable interrupts to prevent nesting routines (unless the program explicitly re-enables them later)
                interrupts.disable()

                -- Now, figure out which interrupt this is, and call the corresponding
                -- interrupt vector
                local vector = 0x40
                local count = 0
                while bit32.band(fired, 0x1) == 0 and count < 5 do
                    vector = vector + 0x08
                    fired = bit32.rshift(fired, 1)
                    count = count + 1
                end
                -- we need to clear the corresponding bit first, to avoid infinite loops
                io.ram[0x0F] = bit32.bxor(bit32.lshift(0x1, count), io.ram[0x0F])

                reg.sp = bit32.band(0xFFFF, reg.sp - 1)
                write_byte(reg.sp, bit32.rshift(bit32.band(reg.pc, 0xFF00), 8))
                reg.sp = bit32.band(0xFFFF, reg.sp - 1)
                write_byte(reg.sp, bit32.band(reg.pc, 0xFF))

                reg.pc = vector

                z80.add_cycles(12)
                return true
            end
        end
        return false
    end

    -- ei
    opcodes[0xFB] = function()
        interrupts.enable()
        --print("Enabled interrupts with EI")
        z80.service_interrupt()
    end

    -- register this as a callback with the interrupts module
    interrupts.service_handler = z80.service_interrupt

    -- For any opcodes that at this point are undefined,
    -- go ahead and "define" them with the following panic
    -- function
    local function undefined_opcode()
        local opcode = read_byte(bit32.band(reg.pc - 1, 0xFFFF))
        print(string.format("Unhandled opcode!: %x", opcode))
    end

    for i = 0, 0xFF do
        if not opcodes[i] then
            opcodes[i] = undefined_opcode
        end
    end

    z80.process_instruction = function()
        --  If the processor is currently halted, then do nothing.
        if z80.halted == 0 then
            local opcode = read_byte(reg.pc)
            -- Advance to one byte beyond the opcode
            reg.pc = bit32.band(reg.pc + 1, 0xFFFF)
            -- Run the instruction
            opcodes[opcode]()

            -- add a base clock of 4 to every instruction
            -- NOPE, working on removing add_cycles, pull from the opcode_cycles
            -- table instead
            z80.add_cycles(opcode_cycles[opcode])
        else
            -- Base cycles of 4 when halted, for sanity
            z80.add_cycles(4)
        end

        return true
    end

    return z80
end

return Z80
