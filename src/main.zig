const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var store = std.StringHashMap([]const u8).init(allocator);
    defer store.deinit();

    var stdin = std.io.getStdIn();
    var stdout = std.io.getStdOut();
    var reader = stdin.reader();
    var writer = stdout.writer();

    try writer.print("Zig Store REPL. Type commands (SET key value, GET key, DEL key, EXIT).\n", .{});

    while (true) {
        try writer.print("> ", .{});

        var buffer: [256]u8 = undefined;
        const input = try reader.readUntilDelimiterOrEof(&buffer, '\n') orelse break;

        var tokenizer = std.mem.tokenizeAny(u8, input, " \n");
        var args: [3][]const u8 = undefined;
        var i: usize = 0;

        while (tokenizer.next()) |token| {
            if (i < args.len) {
                args[i] = token;
                i += 1;
            }
        }

        if (i == 0) continue;
        if (std.mem.eql(u8, args[0], "EXIT")) break;
        if (std.mem.eql(u8, args[0], "SET") and i == 3) {
            const key = try allocator.dupe(u8, args[1]);
            const value = try allocator.dupe(u8, args[2]);
            try store.put(key, value);

            try writer.print("OK\n", .{});
        } else if (std.mem.eql(u8, args[0], "GET") and i == 2) {
            if (store.get(args[1])) |value| {
                try writer.print("{s}\n", .{value});
            } else {
                try writer.print("(nil)\n", .{});
            }
        } else if (std.mem.eql(u8, args[0], "DEL") and i == 2) {
            _ = store.remove(args[1]);
            try writer.print("OK\n", .{});
        } else {
            try writer.print("Unknown command.\n", .{});
        }
    }
}
