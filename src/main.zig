const std = @import("std");
const http = @import("http.zig");

const net = std.net;
const mem = std.mem;
const Thread = std.Thread;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var store = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = store.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        store.deinit();
    }

    std.fs.cwd().makeDir("data") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const file = blk: {
        const f = std.fs.cwd().openFile("data/wal.log", .{ .mode = .read_write }) catch |err| {
            if (err == error.FileNotFound) {
                break :blk try std.fs.cwd().createFile("data/wal.log", .{});
            }
            return err;
        };
        break :blk f;
    };
    defer file.close();

    var buf: [1024]u8 = undefined;
    var wal_reader = file.reader();

    const file_size = try file.getEndPos();
    if (file_size > 0) {
        try file.seekTo(0);

        while (true) {
            const maybe_line = try wal_reader.readUntilDelimiterOrEof(&buf, '\n');
            if (maybe_line == null) break;
            const line = maybe_line.?;

            var tokenizer = std.mem.tokenizeAny(u8, line, " ");
            var args: [3][]const u8 = undefined;
            var i: usize = 0;

            while (tokenizer.next()) |token| {
                if (i < args.len) {
                    args[i] = token;
                    i += 1;
                }
            }

            if (i == 3 and std.mem.eql(u8, args[0], "SET")) {
                const key = try allocator.dupe(u8, args[1]);
                const value = try allocator.dupe(u8, args[2]);
                try store.put(key, value);
            } else if (i == 2 and std.mem.eql(u8, args[0], "DEL")) {
                _ = store.remove(args[1]);
            }
        }
    }

    try file.seekTo(file_size);
    var wal_writer = file.writer();

    var thread = try Thread.spawn(.{}, http.httpServer, .{ &store, allocator });
    defer thread.join();

    var stdin = std.io.getStdIn();
    var stdout = std.io.getStdOut();
    var reader = stdin.reader();
    var writer = stdout.writer();

    try writer.print("Zig Store CLI. Type commands (SET key value, GET key, DEL key, EXIT).\n", .{});

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
            try wal_writer.print("SET {s} {s}\n", .{ key, value });
            try file.sync();
        } else if (std.mem.eql(u8, args[0], "GET") and i == 2) {
            if (store.get(args[1])) |value| {
                try writer.print("{s}\n", .{value});
            } else {
                try writer.print("(nil)\n", .{});
            }
        } else if (std.mem.eql(u8, args[0], "DEL") and i == 2) {
            _ = store.remove(args[1]);
            try writer.print("OK\n", .{});
            try wal_writer.print("DEL {s}\n", .{args[1]});
            try file.sync();
        } else {
            try writer.print("Unknown command.\n", .{});
        }
    }
}
