/// Contains all the logic for putting the Ghostty process and
/// each individual surface into its own cgroup.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const c = @import("c.zig").c;
const App = @import("App.zig");
const internal_os = @import("../../os/main.zig");

const log = std.log.scoped(.gtk_systemd_cgroup);

/// Initialize the cgroup for the app. This will create our
/// transient scope, initialize the cgroups we use for the app,
/// configure them, and return the cgroup path for the app.
pub fn init(app: *App) ![]const u8 {
    const pid = std.os.linux.getpid();
    const alloc = app.core_app.alloc;
    const connection = c.g_application_get_dbus_connection(@ptrCast(app.app)) orelse
        return error.DbusConnectionRequired;

    // Get our initial cgroup. We need this so we can compare
    // and detect when we've switched to our transient group.
    const original = try internal_os.cgroup.current(
        alloc,
        pid,
    ) orelse "";
    defer alloc.free(original);

    // Create our transient scope. If this succeeds then the unit
    // was created, but we may not have moved into it yet, so we need
    // to do a dumb busy loop to wait for the move to complete.
    try createScope(connection);
    const transient = transient: while (true) {
        const current = try internal_os.cgroup.current(
            alloc,
            pid,
        ) orelse "";
        if (!std.mem.eql(u8, original, current)) break :transient current;
        alloc.free(current);
        std.time.sleep(25 * std.time.ns_per_ms);
    };
    errdefer alloc.free(transient);
    log.info("transient scope created cgroup={s}", .{transient});

    // Create the app cgroup and put ourselves in it. This is
    // required because controllers can't be configured while a
    // process is in a cgroup.
    try internal_os.cgroup.create(transient, "app", pid);

    // Create a cgroup that will contain all our surfaces. We will
    // enable the controllers and configure resource limits for surfaces
    // only on this cgroup so that it doesn't affect our main app.
    try internal_os.cgroup.create(transient, "surfaces", null);
    const surfaces = try std.fmt.allocPrint(alloc, "{s}/surfaces", .{transient});
    defer alloc.free(surfaces);

    // Enable all of our cgroup controllers. If these fail then
    // we just log. We can't reasonably undo what we've done above
    // so we log the warning and still return the transient group.
    // I don't know a scenario where this fails yet.
    try enableControllers(alloc, transient);
    try enableControllers(alloc, surfaces);

    // Configure the "high" memory limit. This limit is used instead
    // of "max" because it's a soft limit that can be exceeded and
    // can be monitored by things like systemd-oomd to kill if needed,
    // versus an instant hard kill.
    if (app.config.@"linux-cgroup-memory-limit") |limit| {
        try internal_os.cgroup.configureLimit(surfaces, .{
            .memory_high = limit,
        });
    }

    // Configure the "max" pids limit. This is a hard limit and cannot be
    // exceeded.
    if (app.config.@"linux-cgroup-processes-limit") |limit| {
        try internal_os.cgroup.configureLimit(surfaces, .{
            .pids_max = limit,
        });
    }

    return transient;
}

/// Enable all the cgroup controllers for the given cgroup.
fn enableControllers(alloc: Allocator, cgroup: []const u8) !void {
    const raw = try internal_os.cgroup.controllers(alloc, cgroup);
    defer alloc.free(raw);

    // Build our string builder for enabling all controllers
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();

    // Controllers are space-separated
    var it = std.mem.splitScalar(u8, raw, ' ');
    while (it.next()) |controller| {
        try builder.append('+');
        try builder.appendSlice(controller);
        if (it.rest().len > 0) try builder.append(' ');
    }

    // Enable them all
    try internal_os.cgroup.configureControllers(
        cgroup,
        builder.items,
    );
}

/// Create a transient systemd scope unit for the current process.
///
/// On success this will return the name of the transient scope
/// cgroup prefix, allocated with the given allocator.
fn createScope(connection: *c.GDBusConnection) !void {
    // Our pid that we will move into the cgroup
    const pid: c.guint32 = @intCast(std.os.linux.getpid());

    // The unit name needs to be unique. We use the pid for this.
    var name_buf: [256]u8 = undefined;
    const name = std.fmt.bufPrintZ(
        &name_buf,
        "app-ghostty-transient-{}.scope",
        .{pid},
    ) catch unreachable;

    // Initialize our builder to build up our parameters
    var builder: c.GVariantBuilder = undefined;
    c.g_variant_builder_init(&builder, c.G_VARIANT_TYPE("(ssa(sv)a(sa(sv)))"));
    c.g_variant_builder_add(&builder, "s", name.ptr);
    c.g_variant_builder_add(&builder, "s", "fail");
    {
        // Properties
        c.g_variant_builder_open(&builder, c.G_VARIANT_TYPE("a(sv)"));
        defer c.g_variant_builder_close(&builder);

        // https://www.freedesktop.org/software/systemd/man/latest/systemd-oomd.service.html
        c.g_variant_builder_add(
            &builder,
            "(sv)",
            "ManagedOOMMemoryPressure",
            c.g_variant_new_string("kill"),
        );

        // Delegate
        c.g_variant_builder_add(
            &builder,
            "(sv)",
            "Delegate",
            c.g_variant_new_boolean(1),
        );

        // Pid to move into the unit
        c.g_variant_builder_add(
            &builder,
            "(sv)",
            "PIDs",
            c.g_variant_new_fixed_array(
                c.G_VARIANT_TYPE("u"),
                &pid,
                1,
                @sizeOf(c.guint32),
            ),
        );
    }
    {
        // Aux
        c.g_variant_builder_open(&builder, c.G_VARIANT_TYPE("a(sa(sv))"));
        defer c.g_variant_builder_close(&builder);
    }

    var err: ?*c.GError = null;
    defer if (err) |e| c.g_error_free(e);
    _ = c.g_dbus_connection_call_sync(
        connection,
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        "StartTransientUnit",
        c.g_variant_builder_end(&builder),
        c.G_VARIANT_TYPE("(o)"),
        c.G_DBUS_CALL_FLAGS_NONE,
        -1,
        null,
        &err,
    ) orelse {
        if (err) |e| log.err(
            "creating transient cgroup scope failed code={} err={s}",
            .{ e.code, e.message },
        );
        return error.DbusCallFailed;
    };
}
