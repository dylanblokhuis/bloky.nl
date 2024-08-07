const std = @import("std");
const xev = @import("xev");

pub fn Server(comptime State: type, comptime routes: anytype) type {
    return struct {
        const Self = @This();
        const CompletionPool = std.heap.MemoryPoolExtra(xev.Completion, .{});
        const ClientPool = std.heap.MemoryPoolExtra(Client, .{});

        gpa: std.mem.Allocator,
        loop: xev.Loop,
        completions: CompletionPool,
        clients: ClientPool,
        state: *State,

        pub fn init(gpa: std.mem.Allocator, state: *State) !Self {
            return Self{
                .gpa = gpa,
                .loop = try xev.Loop.init(.{}),
                .completions = CompletionPool.init(gpa),
                .clients = ClientPool.init(gpa),
                .state = state,
            };
        }

        pub fn listen(self: *Self, addr: std.net.Address) !void {
            var socket = try xev.TCP.init(addr);

            try socket.bind(addr);
            try socket.listen(0);
            var completion: xev.Completion = .{};
            socket.accept(&self.loop, &completion, Self, self, Self.onAccept);

            std.log.info("Listening on port {d}", .{addr.getPort()});

            try self.loop.run(.until_done);
        }

        fn onAccept(ud: ?*Self, l: *xev.Loop, _: *xev.Completion, r: xev.AcceptError!xev.TCP) xev.CallbackAction {
            const self = ud.?;
            const client_socket = r catch @panic("accept error");
            const client_completion = self.completions.create() catch @panic("alloc completion error");
            const client = self.clients.create() catch @panic("alloc client error");
            client.* = Client{
                .server = self,
                .socket = client_socket,
                .arena = std.heap.ArenaAllocator.init(self.gpa),
                .completion = client_completion,
                .head_buf = undefined,
            };
            client_socket.read(l, client_completion, .{ .slice = &client.head_buf }, Client, client, Client.onRead);

            return .rearm;
        }

        pub const SpawnOptions = struct {
            repeat: bool = false,
            timeout_in_ms: usize = 0,
        };
        pub fn spawn(self: *Self, options: SpawnOptions, func: anytype, args: anytype) !void {
            const Cb = struct {
                outer: *Self,
                args: @TypeOf(args),
                func: *anyopaque,
                options: SpawnOptions,

                pub fn cb(
                    ud: ?*anyopaque,
                    loop: *xev.Loop,
                    completion: *xev.Completion,
                    _: xev.Result,
                ) xev.CallbackAction {
                    const callback: *@This() = @ptrCast(@alignCast(ud));

                    const func_ptr: *@TypeOf(func) = @ptrCast(@alignCast(callback.func));
                    _ = @call(.auto, func_ptr, callback.args);

                    if (callback.options.repeat) {
                        loop.timer(completion, callback.options.timeout_in_ms, callback, @This().cb);
                    } else {
                        callback.outer.gpa.destroy(callback);
                        callback.outer.completions.destroy(completion);
                    }

                    return .disarm;
                }
            };

            const ptr = try self.gpa.create(Cb);
            ptr.* = Cb{
                .outer = self,
                .args = args,
                .func = @constCast(&func),
                .options = options,
            };
            const c = try self.completions.create();
            self.loop.timer(c, options.timeout_in_ms, ptr, Cb.cb);
        }
        const Client = struct {
            server: *Self,
            socket: xev.TCP,
            arena: std.heap.ArenaAllocator,
            completion: *xev.Completion,
            head_buf: [4096]u8 = undefined,

            pub inline fn allocator(self: *Client) std.mem.Allocator {
                return self.arena.allocator();
            }

            pub fn deinit(self: *Client) void {
                self.arena.deinit();
                self.server.completions.destroy(self.completion);
                self.server.clients.destroy(self);
            }

            pub fn call(self: *Client, method: std.http.Method, path: []const u8) !?[]const u8 {
                std.log.info("{d} - {s} - {s}", .{ std.time.timestamp(), @tagName(method), path });

                // std.meta.decl
                inline for (routes) |route| {
                    if (route.method == method and std.mem.eql(u8, route.path, path)) {
                        return try @TypeOf(route).handle(path, self.allocator(), self.server.state);
                    }

                    if (route.method == method and std.mem.eql(u8, route.path, "*")) {
                        return try @TypeOf(route).handle(path, self.allocator(), self.server.state);
                    }
                }

                return null;
            }

            pub fn onRead(self_: ?*Client, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.ReadBuffer, r: xev.TCP.ReadError!usize) xev.CallbackAction {
                const self = self_.?;
                const bytes_read = r catch @panic("read error");
                const data = self.head_buf[0..bytes_read];
                const head = std.http.Server.Request.Head.parse(data) catch unreachable;

                if (self.call(head.method, head.target) catch @panic("TODO: add proper res")) |content| {
                    if (std.mem.containsAtLeast(u8, head.target, 1, ".js")) {
                        self.writeHtml("200 OK", "application/javascript", content) catch @panic("write error");
                    } else {
                        self.writeHtml("200 OK", "text/html", content) catch @panic("write error");
                    }
                    return .disarm;
                }

                self.writeHtml("404 Not Found", "text/plain", "Not Found") catch @panic("write error");

                return .disarm;
            }

            fn writeHtml(self: *Client, status: []const u8, content_type: []const u8, html: []const u8) !void {
                const httpOk =
                    \\HTTP/1.1 {s}
                    \\Content-Type: {s}
                    \\Content-Length: {d}
                    \\Connection: close
                    \\
                    \\{s}
                ;
                const response = try std.fmt.allocPrint(self.allocator(), httpOk, .{ status, content_type, html.len, html });
                self.socket.write(&self.server.loop, self.completion, .{ .slice = response }, Client, self, Client.onWrite);
            }

            fn onWrite(
                self_: ?*Client,
                l: *xev.Loop,
                c: *xev.Completion,
                s: xev.TCP,
                buf: xev.WriteBuffer,
                r: xev.TCP.WriteError!usize,
            ) xev.CallbackAction {
                const self = self_.?;

                const written = r catch |err| {
                    std.log.err("write error: {}, deiniting client", .{err});
                    self.deinit();
                    return .disarm;
                };
                if (written != buf.slice.len) {
                    self.socket.write(l, c, .{ .slice = buf.slice[written..] }, Client, self, Client.onWrite);

                    return .disarm;
                }

                s.shutdown(l, c, Client, self, onShutdown);

                return .disarm;
            }

            fn onShutdown(
                self_: ?*Client,
                l: *xev.Loop,
                c: *xev.Completion,
                s: xev.TCP,
                r: xev.TCP.ShutdownError!void,
            ) xev.CallbackAction {
                _ = r catch @panic("shutdown error");

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
                _ = c; // autofix
                _ = l;
                _ = r catch @panic("close error");
                _ = socket;

                var self = self_.?;
                self.deinit();
                return .disarm;
            }
        };
    };
}
