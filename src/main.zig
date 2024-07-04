const std = @import("std");
const xev = @import("xev");

const net = std.net;
const Allocator = std.mem.Allocator;

const CompletionPool = std.heap.MemoryPoolExtra(xev.Completion, .{});
const ClientPool = std.heap.MemoryPoolExtra(Client, .{});

pub fn main() !void {
    var thread_pool = xev.ThreadPool.init(.{});
    defer thread_pool.deinit();
    defer thread_pool.shutdown();

    var loop = try xev.Loop.init(.{
        .entries = 4096,
        .thread_pool = &thread_pool,
    });
    defer loop.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const port = 3000;
    const addr = try net.Address.parseIp4("0.0.0.0", port);
    var socket = try xev.TCP.init(addr);

    std.log.info("Listening on port {}", .{port});

    try socket.bind(addr);
    try socket.listen(std.os.linux.SOMAXCONN);

    var completion_pool = CompletionPool.init(alloc);
    defer completion_pool.deinit();

    var client_pool = ClientPool.init(alloc);
    defer client_pool.deinit();

    const c = try completion_pool.create();
    var server = Server{
        .loop = &loop,
        .gpa = alloc,
        .completion_pool = &completion_pool,
        .client_pool = &client_pool,
    };

    socket.accept(&loop, c, Server, &server, Server.acceptCallback);
    try loop.run(.until_done);
}

pub fn Router(comptime routes: anytype) type {
    return struct {
        pub fn call(self: @This(), method: std.http.Method, path: []const u8) ?[]const u8 {

            // std.meta.decl
            _ = self;
            inline for (routes) |route| {
                if (route.method == method and std.mem.eql(u8, route.path, path)) {
                    return route.handle();
                }
            }

            return null;
        }
    };
}

const Client = struct {
    id: u32,
    socket: xev.TCP,
    loop: *xev.Loop,
    arena: std.heap.ArenaAllocator,
    client_pool: *ClientPool,
    completion_pool: *CompletionPool,
    read_buf: [4096]u8 = undefined,

    const Self = @This();

    pub fn work(self: *Self) void {
        const c_read = self.completion_pool.create() catch unreachable;
        self.socket.read(self.loop, c_read, .{ .slice = &self.read_buf }, Client, self, Client.readCallback);
    }

    pub fn readCallback(
        self_: ?*Client,
        l: *xev.Loop,
        c: *xev.Completion,
        s: xev.TCP,
        buf: xev.ReadBuffer,
        r: xev.TCP.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_.?;
        const n = r catch |err| {
            std.log.err("read error {any}", .{err});
            s.shutdown(l, c, Client, self, shutdownCallback);
            return .disarm;
        };
        const data = buf.slice[0..n];

        const head = std.http.Server.Request.Head.parse(data) catch unreachable;
        const content = router.call(head.method, head.target);

        if (content == null) {
            const httpNotFound =
                \\HTTP/1.1 404 Not Found
                \\Content-Type: text/plain
                \\Content-Length: 0
                \\Connection: close
                \\
                \\
            ;

            const res = std.fmt.allocPrint(self.arena.allocator(), httpNotFound, .{}) catch unreachable;
            self.socket.write(self.loop, c, .{ .slice = res }, Client, self, writeCallback);
            return .disarm;
        }

        const httpOk =
            \\HTTP/1.1 200 OK
            \\Content-Type: text/plain
            \\Content-Length: {d}
            \\Connection: close
            \\
            \\{s}
        ;

        const res = std.fmt.allocPrint(self.arena.allocator(), httpOk, .{ content.?.len, content.? }) catch unreachable;

        self.socket.write(self.loop, c, .{ .slice = res }, Client, self, writeCallback);

        return .disarm;
    }

    fn writeCallback(
        self_: ?*Client,
        l: *xev.Loop,
        c: *xev.Completion,
        s: xev.TCP,
        buf: xev.WriteBuffer,
        r: xev.TCP.WriteError!usize,
    ) xev.CallbackAction {
        _ = buf; // autofix
        _ = r catch unreachable;

        const self = self_.?;
        s.shutdown(l, c, Client, self, shutdownCallback);

        return .disarm;
    }

    fn shutdownCallback(
        self_: ?*Client,
        l: *xev.Loop,
        c: *xev.Completion,
        s: xev.TCP,
        r: xev.TCP.ShutdownError!void,
    ) xev.CallbackAction {
        _ = r catch {};

        const self = self_.?;
        s.close(l, c, Client, self, closeCallback);

        return .disarm;
    }

    fn closeCallback(
        self_: ?*Client,
        l: *xev.Loop,
        c: *xev.Completion,
        socket: xev.TCP,
        r: xev.TCP.CloseError!void,
    ) xev.CallbackAction {
        _ = l;
        _ = r catch unreachable;
        _ = socket;

        var self = self_.?;
        self.arena.deinit();
        self.completion_pool.destroy(c);
        self.client_pool.destroy(self);
        return .disarm;
    }

    pub fn destroy(self: *Self) void {
        self.arena.deinit();
        self.client_pool.destroy(self);
    }
};

const Routes = struct {
    const yo = struct {
        method: std.http.Method = .GET,
        path: []const u8 = "/",

        pub fn handle(s: @This()) []const u8 {
            _ = s; // autofix
            std.debug.print("Yo!\n", .{});
            return "Yo!";
        }
    };
    const yo2 = struct {
        method: std.http.Method = .GET,
        path: []const u8 = "/henkie",

        pub fn handle(s: @This()) []const u8 {
            _ = s; // autofix
            std.debug.print("Yo!!!!!\n", .{});
            return "Yo!!!!!";
        }
    };
};

const router = Router(&.{
    Routes.yo{},
    Routes.yo2{},
}){};

const Server = struct {
    loop: *xev.Loop,
    gpa: Allocator,
    completion_pool: *CompletionPool,
    client_pool: *ClientPool,
    conns: u32 = 0,
    // router: Router(Routes) = .{},

    fn acceptCallback(
        self_: ?*Server,
        l: *xev.Loop,
        // we ignore the completion, to keep the accept loop going for new connections
        _: *xev.Completion,
        r: xev.TCP.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        const self = self_.?;
        var client = self.client_pool.create() catch unreachable;
        client.* = Client{
            .id = self.conns,
            .loop = l,
            .socket = r catch unreachable,
            .arena = std.heap.ArenaAllocator.init(self.gpa),
            .client_pool = self.client_pool,
            .completion_pool = self.completion_pool,
        };
        client.work();

        self.conns += 1;

        return .rearm;
    }
};
