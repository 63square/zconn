//! a basic hello world server

const std = @import("std");
const zconn = @import("zconn");

fn handle_all(req: zconn.Request, res: *zconn.Response) void {
    std.debug.print("Path: {s}\n", .{req.path});

    var iter = req.headers.iterator();
    while (iter.next()) |entry| {
        std.debug.print("[header] '{s}' '{s}'\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    res.headers.put("Server", "zconn") catch {};
    res.body.appendSlice("hello, world!") catch {};
}

pub fn main() !void {
    const application = zconn.Application{
        .addr = .{ 127, 0, 0, 1 },
        .port = 3333,

        .handle_all = handle_all,
    };

    try zconn.listen(application);
}
