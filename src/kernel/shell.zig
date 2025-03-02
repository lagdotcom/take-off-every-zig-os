const std = @import("std");
const log = std.log.scoped(.shell);

const console = @import("console.zig");
const kb = @import("keyboard.zig");
const tools = @import("tools.zig");
const video = @import("video.zig");

const utf8_less_than = std.sort.asc([]const u8);
pub const ShellCommand = struct {
    name: []const u8,
    summary: []const u8,
    exec: ?*const fn (allocator: std.mem.Allocator, args: []const u8) void = null,
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

fn help_command(_: std.mem.Allocator, _: []const u8) void {
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

fn quit_command(_: std.mem.Allocator, _: []const u8) void {
    console.puts("exiting shell\n");
    shell_running = false;
}

pub fn initialize(allocator: std.mem.Allocator) void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    shell_commands = CommandList.init(allocator);
    add_command(.{
        .name = "quit",
        .exec = quit_command,
        .summary = "Exit the kernel shell. This will probably crash the whole system. Enjoy!",
    });
    add_command(.{
        .name = "help",
        .exec = help_command,
        .summary = "Get the list of available commands, or get help on a given command.",
    });
}

pub fn add_command(cmd: ShellCommand) void {
    if (cmd.exec == null and cmd.sub_commands == null) {
        log.warn("tried to add exec-less command with no sub commands!", .{});
    } else shell_commands.append(cmd) catch unreachable;
}

fn get_input(buffer: []u8) []u8 {
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

fn exec_command(allocator: std.mem.Allocator, cmd_line: []const u8, commands: []const ShellCommand) bool {
    const parts = tools.split_by_space(cmd_line);
    log.debug("exec_command: '{s}' '{s}' {d} commands", .{ parts[0], parts[1], commands.len });

    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd.name, parts[0])) {
            if (cmd.sub_commands != null and parts[1].len > 0) {
                const result = exec_command(allocator, parts[1], cmd.sub_commands.?);
                if (result) return result;
            }

            if (cmd.exec) |exec| {
                exec(allocator, parts[1]);
                return true;
            }

            // this only occurs if there are sub commands but no arguments were given
            return false;
        }
    }

    return false;
}

pub fn enter(allocator: std.mem.Allocator) void {
    std.sort.insertion(ShellCommand, shell_commands.items, {}, ShellCommand.less_than);

    const input_buffer = allocator.alloc(u8, 128) catch unreachable;
    defer allocator.free(input_buffer);

    const prompt = video.rgb(255, 255, 0);
    const text = video.rgb(255, 255, 255);
    const err_text = video.rgb(255, 192, 0);

    shell_running = true;
    while (shell_running) {
        console.set_foreground_colour(prompt);
        console.puts("\n> ");

        console.set_foreground_colour(text);
        const cmd_line = get_input(input_buffer);
        console.new_line();

        if (!exec_command(allocator, cmd_line, shell_commands.items)) {
            console.set_foreground_colour(err_text);
            console.puts("unknown command\n");
        }
    }
}
