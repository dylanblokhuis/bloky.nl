const std = @import("std");
const zap = @import("zap");

fn on_request(r: zap.Request) void {
    r.setStatus(.not_found);
    r.sendBody("<html><body><h1>404 - File not found</h1></body></html>") catch return;
}

pub fn main() !void {
    // const env = try std.process.getEnvMap(std.heap.c_allocator);

    // const maybe_cert = env.get("SSL_CERT_FILE");
    // const maybe_key = env.get("SSL_KEY_FILE");

    // const tls: ?zap.Tls = if (maybe_cert != null and maybe_key != null) blk: {
    //     std.fs.cwd().access(maybe_cert.?, .{}) catch |err| {
    //         std.debug.panic("Could not access file '{s}': {}\n", .{ maybe_cert.?, err });
    //     };

    //     std.fs.cwd().access(maybe_key.?, .{}) catch |err| {
    //         std.debug.panic("Could not access file '{s}': {}\n", .{ maybe_key.?, err });
    //     };

    //     const tls = try zap.Tls.init(.{
    //         .server_name = "localhost:4443",
    //         .public_certificate_file = try std.fmt.allocPrintZ(std.heap.c_allocator, "{s}", .{maybe_cert.?}),
    //         .private_key_file = try std.fmt.allocPrintZ(std.heap.c_allocator, "{s}", .{maybe_key.?}),
    //     });

    //     break :blk tls;
    // } else blk: {
    //     break :blk null;
    // };

    const port: usize = 3000;
    var listener = zap.HttpListener.init(.{
        .port = port,
        .on_request = on_request,
        .public_folder = "public",
        .log = true,
        // .tls = tls,
    });
    try listener.listen();

    // std.debug.print("Listening on {s}://localhost:{d}\n", .{ if (tls != null) "https" else "http", port });
    std.debug.print("Listening on http://localhost:{d}\n", .{port});

    // start worker threads
    zap.start(.{
        .threads = @intCast(try std.Thread.getCpuCount()),
        .workers = @intCast(try std.Thread.getCpuCount()),
    });
}
