const std = @import("std");
const net = std.net;
const mem = std.mem;
const Thread = std.Thread;

const server_addr = "127.0.0.1";
const server_port = 8000;

fn httpServer(store: *std.StringHashMap([]const u8), allocator: mem.Allocator, writer: anytype) !void {
    const address = try net.Address.parseIp4(server_addr, server_port);
    var server = try address.listen(.{});
    defer server.deinit();

    try writer.print("Zig Store CLI. Type commands (SET key value, GET key, DEL key, EXIT).\n", .{});

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        var buffer: [1024]u8 = undefined;
        var reader = conn.stream.reader();
        var writer = conn.stream.writer();

        const request_size = try reader.read(&buffer);
        const request = buffer[0..request_size];

        if (std.mem.startsWith(u8, request, "GET /get")) {
            try handleGet(store, &writer, request);
        } else if (std.mem.startsWith(u8, request, "POST /set")) {
            try handleSet(store, allocator, &writer, request);
        } else if (std.mem.startsWith(u8, request, "DELETE /del")) {
            try handleDelete(store, &writer, request);
        } else {
            try writer.writeAll("HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request");
        }
    }
}

fn handleGet(store: *std.StringHashMap([]const u8), writer: anytype, request: []const u8) !void {
    if (parseQuery(request, "key")) |key| {
        if (store.get(key)) |value| {
            try writer.writeAll("HTTP/1.1 200 OK\r\nContent-Length: ");
            try writer.writeAll(std.fmt.allocPrint(std.heap.page_allocator, "{d}\r\n\r\n{s}", .{ value.len, value }) catch return);
        } else {
            try writer.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found");
        }
    } else {
        try writer.writeAll("HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request");
    }
}

fn handleSet(store: *std.StringHashMap([]const u8), allocator: mem.Allocator, writer: anytype, request: []const u8) !void {
    if (parseQuery(request, "key")) |key| {
        if (parseQuery(request, "value")) |value| {
            const key_dup = try allocator.dupe(u8, key);
            const value_dup = try allocator.dupe(u8, value);
            try store.put(key_dup, value_dup);
            try writer.writeAll("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK");
            return;
        }
    }
    try writer.writeAll("HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request");
}

fn handleDelete(store: *std.StringHashMap([]const u8), writer: anytype, request: []const u8) !void {
    if (parseQuery(request, "key")) |key| {
        _ = store.remove(key);
        try writer.writeAll("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK");
    } else {
        try writer.writeAll("HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request");
    }
}

fn parseQuery(request: []const u8, param: []const u8) ?[]const u8 {
    const param_prefix = std.fmt.allocPrint(std.heap.page_allocator, "{s}=", .{param}) catch return null;
    defer std.heap.page_allocator.free(param_prefix);

    if (std.mem.indexOf(u8, request, param_prefix)) |start| {
        const after_param = request[start + param_prefix.len ..];
        if (std.mem.indexOfScalar(u8, after_param, ' ')) |end| {
            return after_param[0..end];
        }
        return after_param;
    }
    return null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var store = std.StringHashMap([]const u8).init(allocator);
    defer store.deinit();

    var thread = try Thread.spawn(.{}, httpServer, .{ &store, allocator });
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
