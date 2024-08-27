//! zconn: lightweight http/1.1 processing in zig

const std = @import("std");

pub const Request = struct { keep_alive: bool, method: std.http.Method };

const RequestError = error{
    InvalidMethod,
    InvalidPath,
    InvalidRequest,
} || std.posix.ReadError;

/// parse incomming requests
/// TODO: make safe
fn parseRequest(buf: []u8, conn: std.net.Server.Connection) RequestError!Request {
    const read = try conn.stream.read(buf);
    var index: u32 = 0;

    // parse method
    while (index < read) : (index += 1) {
        if (buf[index] == ' ') break;
    }
    const method: std.http.Method = @enumFromInt(std.http.Method.parse(buf[0..index]));
    index += 1;

    if (buf[index] != '/') {
        return RequestError.InvalidPath;
    }

    // parse path
    const path_start = index;
    while (index < read) : (index += 1) {
        if (buf[index] == ' ') break;
    }

    const path = buf[path_start..index];
    index += 1;

    // verify end
    const version = buf[index .. index + 8];
    index += 9;

    // check for end of line
    if (buf[index] != '\n') {
        return RequestError.InvalidRequest;
    }
    index += 1;

    std.debug.print("method: {}, path: '{s}', ver: '{s}'\n", .{ @intFromEnum(method), path, version });

    // parse headers
    var header_start = index;
    while (index < read) : (index += 1) {
        if (buf[index] != '\n') continue;
        if (index == header_start + 1) break;

        std.debug.print("[header] '{s}'\n", .{buf[header_start .. index - 1]});

        header_start = index + 1;
    }
    index += 1;

    // data
    std.debug.print("[data] '{s}'\n", .{buf[index..read]});

    return Request{
        .keep_alive = false,
        .method = method,
    };
}

pub fn listen() !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3000);

    var server = try addr.listen(.{});
    while (true) {
        const conn = server.accept() catch continue;

        var buffer = std.mem.zeroes([4096]u8);
        _ = try parseRequest(&buffer, conn);

        conn.stream.close();
    }
}
