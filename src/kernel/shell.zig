const std = @import("std");
const log = std.log.scoped(.shell);

const bmp = @import("bmp.zig");
const console = @import("console.zig");
const file_system = @import("file_system.zig");
const kb = @import("keyboard.zig");
const tools = @import("tools.zig");
const video = @import("video.zig");

const utf8_less_than = std.sort.asc([]const u8);
pub const ShellCommand = struct {
    name: []const u8,
    summary: []const u8,
    exec: ?*const fn (allocator: std.mem.Allocator, args: []const u8) anyerror!void = null,
    sub_commands: ?[]const ShellCommand = null,

    fn less_than(_: void, lhs: ShellCommand, rhs: ShellCommand) bool {
        for (0..@max(lhs.name.len, rhs.name.len)) |i| {
            if (i >= lhs.name.len) return false;
            if (i >= rhs.name.len) return true;

            const lc = lhs.name[i];
            const rc = rhs.name[i];
            if (lc < rc) return true;
            if (rc < lc) return false;
        }

        return false;
    }
};

const CommandList = std.ArrayList(ShellCommand);

var shell_commands: CommandList = undefined;
var shell_running = false;

const SHOW_SUBCOMMAND_LIMIT = 3;

fn shell_help(_: std.mem.Allocator, _: []const u8) !void {
    console.puts("known commands:\n");
    for (shell_commands.items) |cmd| {
        console.putc('\t');
        console.puts(cmd.name);

        if (cmd.sub_commands) |sub| {
            console.puts("\t\t");

            for (0..@min(SHOW_SUBCOMMAND_LIMIT, sub.len)) |si| {
                if (si > 0) console.puts(", ");
                console.puts(sub[si].name);
            }

            if (sub.len > SHOW_SUBCOMMAND_LIMIT) console.puts("...");
        }

        console.new_line();
    }
}

fn shell_quit(_: std.mem.Allocator, _: []const u8) !void {
    console.puts("exiting shell\n");
    shell_running = false;
}

pub fn initialize(allocator: std.mem.Allocator) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    shell_commands = CommandList.init(allocator);
    try add_command(.{
        .name = "quit",
        .exec = shell_quit,
        .summary = "Exit the kernel shell. This will probably crash the whole system. Enjoy!",
    });
    try add_command(.{
        .name = "help",
        .exec = shell_help,
        .summary = "Get the list of available commands, or get help on a given command.",
    });
}

pub fn add_command(cmd: ShellCommand) !void {
    if (cmd.exec == null and cmd.sub_commands == null) return error.InvalidCommand else try shell_commands.append(cmd);
}

fn get_input(buffer: []u8, previous_input: []u8) []u8 {
    var index: usize = 0;
    var print_cursor = true;

    while (true) {
        if (print_cursor) {
            print_cursor = false;
            console.putc('_');
        }

        const e = kb.get_key_press();
        switch (e.key) {
            .backspace => {
                if (index > 0) {
                    console.replace_last_char(" ", true);
                    console.replace_last_char("_", false);

                    // TODO this won't work with a unicode char
                    index -= 1;
                }
            },
            .enter, .left_enter => {
                if (index > 0) {
                    console.replace_last_char(" ", false);
                    return buffer[0..index];
                }
            },
            .up_arrow => {
                if (previous_input.len > 0) {
                    for (0..index + 1) |_| console.replace_last_char(" ", true);

                    console.puts(previous_input);
                    console.putc('_');
                    @memcpy(buffer.ptr, previous_input);
                    index = previous_input.len;
                }
            },
            else => {
                if (e.printed_value) |p| {
                    console.replace_last_char(p, false);
                    @memcpy(buffer[index .. index + p.len], p);
                    index += p.len;
                    print_cursor = true;
                }
            },
        }

        // TODO support arrows, delete?
    }
}

fn exec_command(allocator: std.mem.Allocator, cmd_line: []const u8, commands: []const ShellCommand) !void {
    const parts = tools.split_by_whitespace(cmd_line);
    log.debug("exec_command: '{s}' '{s}' {d} commands", .{ parts[0], parts[1], commands.len });

    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd.name, parts[0])) {
            if (cmd.sub_commands != null and parts[1].len > 0) {
                return try exec_command(allocator, parts[1], cmd.sub_commands.?);
            }

            if (cmd.exec) |exec| {
                return try exec(allocator, parts[1]);
            }

            // this only occurs if there are sub commands but no arguments were given
            return error.NeedsSubCommand;
        }
    }

    return error.CommandNotFound;
}

fn show_cats(allocator: std.mem.Allocator) !void {
    for (file_system.get_list()) |fs| {
        const buf = fs.read_file(allocator, "cats.bmp") catch continue;
        defer allocator.free(buf);

        log.debug("CATS incoming: size={d}", .{buf.len});

        const image = try bmp.BMP.init(buf);
        const half: usize = @intCast(@divTrunc(image.header.width, 2));
        try image.display(video.vga.horizontal / 2 - half, console.cursor_y);

        console.cursor_y += @intCast(image.header.height);
        console.new_line();
        return;
    }
}

pub fn enter(allocator: std.mem.Allocator) !void {
    try show_cats(allocator);

    std.sort.insertion(ShellCommand, shell_commands.items, {}, ShellCommand.less_than);

    const input_buffer = try allocator.alloc(u8, 128);
    defer allocator.free(input_buffer);

    const previous_input_buffer = try allocator.alloc(u8, 128);
    defer allocator.free(previous_input_buffer);

    var previous_input: []u8 = previous_input_buffer[0..0];

    const prompt = video.rgb(255, 255, 0);
    const text = video.rgb(255, 255, 255);
    const err_text = video.rgb(255, 192, 0);

    shell_running = true;
    while (shell_running) {
        console.set_foreground_colour(prompt);
        console.puts("\n> ");

        console.set_foreground_colour(text);
        const cmd_line = get_input(input_buffer, previous_input);
        console.new_line();

        @memcpy(previous_input_buffer.ptr, cmd_line);
        previous_input = previous_input_buffer[0..cmd_line.len];

        var arena = std.heap.ArenaAllocator.init(allocator);
        exec_command(arena.allocator(), cmd_line, shell_commands.items) catch |e| {
            console.set_foreground_colour(err_text);
            console.printf("error: {s}\n", .{@errorName(e)});
        };
        arena.deinit();
    }
}
