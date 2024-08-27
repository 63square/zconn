//! a basic hello world server

const std = @import("std");
const zconn = @import("zconn");

pub fn main() !void {
    try zconn.listen();
}
