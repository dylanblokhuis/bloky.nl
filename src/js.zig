const std = @import("std");
const c = @cImport({
    @cInclude("quickjs.h");
});

const Self = @This();

const JS = struct {
    const Value = c.JSValue;
    const Context = c.JSContext;
    const Runtime = c.JSRuntime;

    fn serialize(ctx: *Context, allocator: std.mem.Allocator, value: anytype) !Value {
        if (@TypeOf(value) == Value) {
            return value;
        }

        return switch (@typeInfo(@TypeOf(value))) {
            .Type, .Void, .Undefined, .NoReturn, .Null => {
                return Value{
                    .tag = c.JS_TAG_UNDEFINED,
                    .u = .{
                        .int32 = 0,
                    },
                };
            },
            .Bool => {
                // return c.JS_NewBool(ctx, @intFromBool(value));
                return Value{
                    .u = .{
                        .int32 = @intFromBool(value),
                    },
                    .tag = c.JS_TAG_BOOL,
                };
            },

            .Int => |info| {
                if (info.bits <= 32 and info.signedness == .signed) {
                    return c.JS_NewInt32(ctx, @intCast(value));
                }

                if (info.bits <= 32 and info.signedness == .unsigned) {
                    return c.JS_NewUint32(ctx, @intCast(value));
                }

                if (info.bits > 32 and info.signedness == .signed) {
                    return c.JS_NewInt64(ctx, @intCast(value));
                }

                if (info.bits > 32 and info.signedness == .unsigned) {
                    return c.JS_NewBigUint64(ctx, @intCast(value));
                }

                @compileError("unsupported integer type");
            },
            .Float => |info| {
                _ = info; // autofix
                return c.JS_NewFloat64(ctx, @floatCast(value));
            },
            .ComptimeInt => {
                return c.JS_NewInt64(ctx, @intCast(value));
            },
            .ComptimeFloat => {
                return c.JS_NewFloat64(ctx, @floatCast(value));
            },
            .Optional => {
                if (value != null) {
                    return try serialize(ctx, allocator, value.?);
                } else {
                    return Value{
                        .tag = c.JS_TAG_NULL,
                        .u = .{
                            .int32 = 0,
                        },
                    };
                }
            },
            .Vector => |vector| {
                const array = c.JS_NewArray(ctx);

                inline for (0..vector.len) |i| {
                    const elem = try serialize(ctx, allocator, value[i]);

                    _ = c.JS_SetPropertyUint32(ctx, array, @intCast(i), elem);
                }

                return array;
            },
            .Struct => |info| {
                const obj = c.JS_NewObject(ctx);

                inline for (info.fields) |field| {
                    const field_name = field.name;
                    const field_value = @field(value, field.name);
                    const field_value_js = try serialize(ctx, allocator, field_value);

                    _ = c.JS_SetPropertyStr(ctx, obj, field_name, field_value_js);
                }

                return obj;
            },
            .Array => |info| {
                const array = c.JS_NewArray(ctx);

                inline for (0..info.len) |i| {
                    // c.JSdefine
                    c.JS_SetPropertyUint32(ctx, array, @intCast(i), try serialize(ctx, allocator, array[i]));
                }

                return array;
            },
            .Pointer => |ptr_type| {
                switch (ptr_type.size) {
                    .One => {
                        return try serialize(ctx, allocator, value.*);
                    },
                    .Slice => {
                        if (ptr_type.child == u8) {
                            return c.JS_NewStringLen(ctx, value.ptr, value.len);
                        }

                        const array = c.JS_NewArray(ctx);
                        for (0..value.len) |i| {
                            _ = c.JS_SetPropertyUint32(ctx, array, @intCast(i), try serialize(ctx, allocator, value[i]));
                        }
                        return array;
                    },
                    else => {
                        @compileLog("unsupported pointer type", ptr_type);
                        @panic("unsupported pointer type");
                    },
                }
            },
            else => {
                @compileLog("unsupported type", value);
                @panic("unsupported type");
            },
        };
    }

    fn deserialize(comptime T: type, ctx: *Context, allocator: std.mem.Allocator, js_value: Value) !T {
        if (T == Value) {
            return js_value;
        }

        // @compileLog(@typeName(c.JSValue));
        // std.debug.print("{s}", .{@typeName(c.JSValue)});

        switch (@typeInfo(T)) {
            .Bool => {
                const value = c.JS_ToBool(ctx, js_value);
                return if (value == 1) true else false;
            },
            .Int => |info| {
                if (info.bits <= 32 and info.signedness == .signed) {
                    var pres: i32 = undefined;
                    _ = c.JS_ToInt32(ctx, &pres, js_value);
                    return @intCast(pres);
                }
                if (info.bits <= 32 and info.signedness == .unsigned) {
                    var pres: u32 = undefined;
                    _ = c.JS_ToUint32(ctx, &pres, js_value);
                    return @intCast(pres);
                }
                if (info.bits > 32 and info.signedness == .signed) {
                    var pres: i64 = undefined;
                    _ = c.JS_ToInt64(ctx, &pres, js_value);
                    return @intCast(pres);
                }
                if (info.bits > 32 and info.signedness == .unsigned) {
                    var pres: u64 = undefined;
                    _ = c.JS_ToBigUint64(ctx, &pres, js_value);
                    return @intCast(pres);
                }
                @compileError("unsupported integer type");
            },
            .Optional => |info| {
                if (c.JS_IsUndefined(js_value) == 1 or c.JS_IsNull(js_value) == 1) {
                    return null;
                } else {
                    return try deserialize(info.child, ctx, allocator, js_value);
                }
            },
            .Vector => |vector| {
                const result: @Vector(vector.len, vector.child) = undefined;

                for (0..vector.len) |i| {
                    const elem = c.JS_GetPropertyUint32(ctx, js_value, @intCast(i));
                    defer c.JS_FreeValue(ctx, elem);

                    result[i] = try deserialize(vector.child, ctx, allocator, elem);
                }

                return result;
            },
            .Struct => |info| {
                var result: T = undefined;

                inline for (info.fields) |field| {
                    const field_name = field.name;
                    const field_value_js = c.JS_GetPropertyStr(ctx, js_value, field_name);
                    defer c.JS_FreeValue(ctx, field_value_js);

                    const field_value = try deserialize(field.type, ctx, allocator, field_value_js);
                    @field(result, field.name) = field_value;
                }

                return result;
            },
            .Array => |info| {
                const result: [info.len]info.child = undefined;

                for (0..info.len) |i| {
                    const elem = c.JS_GetPropertyUint32(ctx, js_value, @intCast(i));
                    defer c.JS_FreeValue(ctx, elem);

                    result[i] = try deserialize(info.child, ctx, allocator, elem);
                }

                return result;
            },
            .Pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .One => {
                        return try deserialize(ptr_info.child, ctx, allocator, js_value);
                    },
                    .Slice => {
                        if (ptr_info.child == u8) {
                            var len: usize = undefined;
                            const str = c.JS_ToCStringLen(ctx, @ptrCast(&len), js_value);
                            defer c.JS_FreeCString(ctx, str);

                            return try std.fmt.allocPrintZ(allocator, "{s}", .{str[0..len]});
                        }

                        const len = c.JS_GetPropertyStr(ctx, js_value, "length");
                        defer c.JS_FreeValue(ctx, len);

                        var len_val: u32 = undefined;
                        _ = c.JS_ToUint32(ctx, &len_val, len);
                        const result = try allocator.alloc(ptr_info.child, @intCast(len_val));
                        for (0..len_val) |i| {
                            const elem = c.JS_GetPropertyUint32(ctx, js_value, @intCast(i));
                            defer c.JS_FreeValue(ctx, elem);

                            result[i] = try deserialize(ptr_info.child, ctx, allocator, elem);
                        }

                        return result;
                    },
                    else => {
                        @compileLog("unsupported pointer type", ptr_info);
                        @panic("unsupported pointer type");
                    },
                }
            },
            else => {
                @compileLog("unsupported type", T);
                @panic("unsupported type");
            },
        }
    }
};

rt: *JS.Runtime,
ctx: *JS.Context,
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) Self {
    const rt = c.JS_NewRuntime();
    const ctx = c.JS_NewContext(rt);
    c.JS_SetMaxStackSize(rt, 0);

    return Self{ .rt = rt.?, .ctx = ctx.?, .gpa = gpa };
}

pub fn run(self: *Self, script_file: [:0]const u8) !void {
    const file = try std.fs.cwd().readFileAlloc(self.gpa, script_file, std.math.maxInt(usize));
    const file_formatted = try std.fmt.allocPrintZ(self.gpa, "{s}", .{file});
    const script_result = c.JS_Eval(self.ctx, file_formatted.ptr, file_formatted.len, script_file, 0);

    if (c.JS_IsException(script_result) == 1) {
        std.log.err("script exception", .{});
        const exception_val = c.JS_GetException(self.ctx);
        const str_val = c.JS_ToCString(self.ctx, exception_val);
        defer c.JS_FreeCString(self.ctx, str_val);
        defer c.JS_FreeValue(self.ctx, exception_val);
        std.log.err("{s}", .{str_val});
        return error.Unreachable;
    }
    self.gpa.free(file);
    self.gpa.free(file_formatted);
    c.JS_FreeValue(self.ctx, script_result);
}

pub fn garbageCollection(self: *Self) void {
    c.JS_RunGC(self.rt);
}

pub fn call(self: *Self, T: type, func_name: [:0]const u8, arg: anytype) !T {
    const func_obj = c.JS_GetPropertyStr(self.ctx, c.JS_GetGlobalObject(self.ctx), func_name.ptr);
    var arg_val = try JS.serialize(self.ctx, self.gpa, arg);
    // const str = c.JS_ToCString(self.ctx, value);
    // defer c.JS_FreeCString(self.ctx, str);
    // std.debug.print("{s}\n", .{str});
    // return func;
    const value = c.JS_Call(self.ctx, func_obj, c.JS_GetGlobalObject(self.ctx), 1, &arg_val);
    return try JS.deserialize(T, self.ctx, self.gpa, value);
}
