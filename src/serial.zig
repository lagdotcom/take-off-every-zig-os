const utils = @import("utils.zig");

pub const COM1: u16 = 0x3F8;

const Reg = struct {
    pub const Buffer = 0;
    pub const InterruptEnable = 1;
    pub const InterruptIdentification = 2;
    pub const FIFOControl = 2;
    pub const LineControl = 3;
    pub const ModemControl = 4;
    pub const LineStatus = 5;
    pub const ModemStatus = 6;
    pub const Scratch = 7;
};

pub const Interrupts = packed struct {
    data_available: bool,
    transmitter_empty: bool,
    receiver_line_status: bool,
    modem_status: bool,
    reserved: u4,
};

pub const FIFOControl = packed struct {
    enable: bool,
    clear_receive_fifo: bool,
    clear_transmit_fifo: bool,
    dma_mode_select: bool,
    reserved: u2,
    trigger_level: u2,
};

pub const DataBits = enum(u2) {
    Five = 0,
    Six = 1,
    Seven = 2,
    Eight = 3,
};

pub const StopBits = enum(u1) {
    One = 0,
    Two = 1,
};

pub const ParityBits = enum(u3) {
    None = 0,
    Odd = 1,
    Even = 3,
    Mark = 5,
    Space = 7,
};

pub const LineControl = packed struct {
    data_bits: DataBits,
    stop_bits: StopBits,
    parity: ParityBits,
    set_break: bool,
    divisor_latch_access: bool,
};

pub const ModemControl = packed struct {
    data_terminal_ready: bool,
    request_to_send: bool,
    auxiliary_output_1: bool,
    auxiliary_output_2: bool,
    loopback_mode: bool,
    unused: u3,
};

pub const LineStatus = packed struct {
    data_ready: bool,
    overrun_error: bool,
    parity_error: bool,
    framing_error: bool,
    break_indicator: bool,
    transmitter_holding_register_empty: bool,
    transmitter_empty: bool,
    error_in_fifo: bool,
};

pub const Port = struct {
    address: u16,

    pub fn initialize(address: u16) Port {
        return Port{ .address = address };
    }

    pub fn read_offset(self: Port, offset: u16) u8 {
        return utils.inb(self.address + offset);
    }

    pub fn write_offset(self: Port, offset: u16, value: u8) void {
        utils.outb(self.address + offset, value);
    }

    pub fn set_interrupts(self: Port, data_available: bool, transmitter_empty: bool, receiver_line_status: bool, modem_status: bool) void {
        self.write_offset(Reg.InterruptEnable, @bitCast(Interrupts{ .data_available = data_available, .transmitter_empty = transmitter_empty, .receiver_line_status = receiver_line_status, .modem_status = modem_status, .reserved = 0 }));
    }

    pub fn set_fifo_control(self: Port, enable: bool, clear_receive: bool, clear_transmit: bool, dma_mode: bool, interrupt_trigger_level: u2) void {
        self.write_offset(Reg.FIFOControl, @bitCast(FIFOControl{ .enable = enable, .clear_receive_fifo = clear_receive, .clear_transmit_fifo = clear_transmit, .dma_mode_select = dma_mode, .reserved = 0, .trigger_level = interrupt_trigger_level }));
    }

    pub fn set_modem_control(self: Port, dtr: bool, rts: bool, out1: bool, out2: bool, loop: bool) void {
        self.write_offset(Reg.ModemControl, @bitCast(ModemControl{ .data_terminal_ready = dtr, .request_to_send = rts, .auxiliary_output_1 = out1, .auxiliary_output_2 = out2, .loopback_mode = loop, .unused = 0 }));
    }

    pub fn set_line_control(self: Port, value: LineControl) void {
        self.write_offset(Reg.LineControl, @bitCast(value));
    }

    pub fn set_baud_divisor(self: Port, divisor: u16) void {
        self.set_line_control(LineControl{ .divisor_latch_access = true, .data_bits = .Five, .stop_bits = .One, .parity = .None, .set_break = false });
        self.write_offset(0, @intCast(divisor & 0xFF));
        self.write_offset(1, @intCast(divisor >> 8));
    }

    pub fn get_line_status(self: Port) LineStatus {
        return @bitCast(self.read_offset(Reg.LineStatus));
    }

    pub fn is_transmit_empty(self: Port) bool {
        return self.get_line_status().transmitter_empty;
    }

    pub fn write_byte(self: Port, byte: u8) void {
        while (!self.is_transmit_empty()) {}
        self.write_offset(Reg.Buffer, byte);
    }

    pub fn write(self: Port, data: []const u8) void {
        for (data) |byte| self.write_byte(byte);
    }

    pub fn serial_received(self: Port) bool {
        return self.get_line_status().data_ready;
    }

    pub fn read_byte(self: Port) u8 {
        while (!self.serial_received()) {}
        return self.read_offset(Reg.Buffer);
    }
};

pub fn initialize(address: u16) !Port {
    const port = Port.initialize(address);

    port.set_interrupts(false, false, false, false);
    port.set_baud_divisor(3);
    port.set_line_control(LineControl{ .data_bits = .Eight, .stop_bits = .One, .parity = .None, .set_break = false, .divisor_latch_access = false });
    port.set_fifo_control(true, true, true, false, 3);
    port.set_modem_control(true, true, false, true, false);

    // loopback test
    port.set_modem_control(false, true, true, true, true);
    port.write_byte(0xae);
    if (port.read_byte() != 0xae) {
        return error.FaultyHardware;
    }

    // set back to normal mode
    port.set_modem_control(true, true, true, true, false);

    return port;
}
