//! zconn: lightweight http/1.1 processing in zig

const MAX_REQUEST_SIZE = 1024 * 1024; // 1 MiB
const std = @import("std");

pub const Request = struct {
    keep_alive: bool,
    method: std.http.Method,
    path: std.ArrayList(u8),
    headers: std.StringHashMap([]const u8),
    body: ?std.ArrayList(u8),

    pub fn deinit(s: *Request) void {
        s.path.deinit();
        s.headers.deinit();
        if (s.body) |b| b.deinit();
        s.* = undefined;
    }
};

pub const Response = struct {
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),

    pub fn deinit(s: *Response) void {
        s.headers.deinit();
        s.body.deinit();
        s.* = undefined;
    }
};

pub const Application = struct {
    handle_all: fn (Request, *Response) void,
};

const RequestError = error{
    InvalidMethod,
    InvalidPath,
    InvalidRequest,
    InvalidHeader,

    RequestTooLarge,

    OutOfMemory,
} || std.posix.ReadError;

/// parse incoming requests
/// TODO: make safer
fn parseRequest(allocator: std.mem.Allocator, conn: std.net.Server.Connection) RequestError!Request {
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    // read all, taken from stdlib
    try array_list.ensureTotalCapacity(@min(MAX_REQUEST_SIZE, 4096));
    var start_index: usize = 0;
    while (true) {
        array_list.expandToCapacity();
        const dest_slice = array_list.items[start_index..];
        const bytes_read = try conn.stream.read(dest_slice);
        start_index += bytes_read;

        if (start_index > MAX_REQUEST_SIZE) {
            array_list.clearAndFree();
            return error.RequestTooLarge;
        }

        if (bytes_read != dest_slice.len) {
            array_list.shrinkAndFree(start_index);
            break;
        }

        // This will trigger ArrayList to expand superlinearly at whatever its growth rate is.
        try array_list.ensureTotalCapacity(start_index + 16);
    }

    var request = array_list.items;
    var index: u32 = 0;

    // parse method, assume max length is 16
    while (index < 16) : (index += 1) {
        if (request[index] == ' ') break;
    }
    const method: std.http.Method = @enumFromInt(std.http.Method.parse(request[0..index]));
    index += 1;

    if (request[index] != '/') {
        return RequestError.InvalidPath;
    }

    // parse path
    const path_start = index;
    while (index < request.len) : (index += 1) {
        if (request[index] == ' ') break;
    }

    var path = std.ArrayList(u8).init(allocator);
    try path.appendSlice(request[path_start..index]);
    index += 1;

    // verify end, version here
    index += 8;

    // check for end of line
    if (request[index] != '\r') {
        return RequestError.InvalidRequest;
    }
    index += 1;
    if (request[index] != '\n') {
        return RequestError.InvalidRequest;
    }
    index += 1;

    // parse headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    var header_start = index;
    while (index < request.len) : (index += 1) {
        if (request[index] != '\n') continue;
        if (index == header_start + 1) break;

        // parse header
        const header = request[header_start .. index - 1];
        var body_start: u32 = 0;
        while (body_start < index - 1) : (body_start += 1) {
            if (header[body_start] == ':')
                break;
        }

        if (header.len < body_start + 2)
            return RequestError.InvalidHeader;

        const header_name = header[0..body_start];
        body_start += 2;

        const header_body = header[body_start..];
        try headers.put(header_name, header_body);

        header_start = index + 1;
    }

    if (request.len <= index)
        return RequestError.InvalidRequest;

    index += 1;
    var body: ?std.ArrayList(u8) = null;
    if (method.requestHasBody()) {
        body = std.ArrayList(u8).init(allocator);
        try body.?.appendSlice(request[index..]);
    }

    return Request{
        .keep_alive = false, // TODO: implement keep alive
        .method = method,
        .headers = headers,
        .path = path,
        .body = body,
    };
}

fn writeResponse(allocator: std.mem.Allocator, res: *Response, conn: std.net.Server.Connection) !void {
    var formatted = std.ArrayList(u8).init(allocator);
    try formatted.appendSlice("HTTP/1.1 200 OK\r\n");

    var iter = res.headers.iterator();
    while (iter.next()) |entry| {
        try formatted.appendSlice(entry.key_ptr.*);
        try formatted.appendSlice(": ");
        try formatted.appendSlice(entry.value_ptr.*);
        try formatted.appendSlice("\r\n");
    }
    try formatted.appendSlice("\r\n");

    try conn.stream.writeAll(formatted.items);
    try conn.stream.writeAll(res.body.items);
}

pub fn listen(application: Application) !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3333);

    var server = try addr.listen(.{});

    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const conn = server.accept() catch continue;

        // TODO: improve logging
        const allocator = arena.allocator();
        const request = parseRequest(allocator, conn);

        if (request) |req| {
            var response = Response{
                .body = std.ArrayList(u8).init(allocator),
                .headers = std.StringHashMap([]const u8).init(allocator),
            };

            application.handle_all(req, &response);

            var buf: [16]u8 = undefined;
            const buf_end = std.fmt.formatIntBuf(&buf, response.body.items.len, 10, .lower, .{});
            response.headers.putNoClobber("Content-Length", buf[0..buf_end]) catch std.debug.panic("Critical Error: Out of Memory!\n", .{});

            writeResponse(allocator, &response, conn) catch |e| std.debug.print("Response error: {any}\n", .{e});

            if (req.keep_alive == true) continue;
        } else |err| {
            std.debug.print("Request error: {any}\n", .{err});
        }

        conn.stream.close();
    }
}
