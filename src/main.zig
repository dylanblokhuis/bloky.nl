const std = @import("std");
const Server = @import("server.zig").Server;
const JS = @import("js.zig");

const Routes = struct {
    const yo = struct {
        method: std.http.Method = .GET,
        path: []const u8 = "/",

        pub fn handle(s: @This(), js: *JS) ![]const u8 {
            return js.call([]const u8, "onRequest", s.path);
        }
    };
    const health = struct {
        method: std.http.Method = .GET,
        path: []const u8 = "/health",

        pub fn handle(s: @This(), js: *JS) ![]const u8 {
            _ = s; // autofix
            _ = js; // autofix
            return "OK";
        }
    };
};

var rt: JS = undefined;

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    rt = JS.init(allocator);
    try rt.run("zig-out/polyfills.js");
    try rt.run("zig-out/out.js");

    var server = try Server(JS, &.{
        Routes.yo{},
    }).init(allocator, &rt);
    try server.spawn(.{
        .repeat = true,
        .timeout_in_ms = 4000,
    }, JS.garbageCollection, .{&rt});
    try server.listen(try std.net.Address.parseIp("0.0.0.0", 3000));
}

const PerfSpan = struct {
    now: std.time.Instant,
    pub fn init() PerfSpan {
        return PerfSpan{ .now = std.time.Instant.now() catch unreachable };
    }

    pub fn done(self: PerfSpan) void {
        const now = std.time.Instant.now() catch unreachable;
        const elasped: f64 = @floatFromInt(now.since(self.now));

        std.debug.print("Elapsed: {d:.4}us\n", .{elasped / std.time.ns_per_us});
    }
};
