const std = @import("std");
const net = std.net;
const mem = std.mem;

const server_addr = "127.0.0.1";
const server_port = 8000;

pub fn httpServer(store: *std.StringHashMap([]const u8), allocator: mem.Allocator) !void {
    const address = try net.Address.parseIp4(server_addr, server_port);
    var server = try address.listen(.{});
    defer server.deinit();

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
