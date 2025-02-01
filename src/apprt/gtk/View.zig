/// View helps with creating a view with a constraint layout by
/// managing all the boilerplate. The caller is responsible for
/// providing the widgets, their names, and the VFL code and gets
/// a root box as a result ready to be used.
const View = @This();

const std = @import("std");
const c = @import("c.zig").c;

const log = std.log.scoped(.gtk);

/// The box that contains all of the widgets.
root: *c.GtkWidget,

/// A single widget used in the view.
pub const Widget = struct {
    /// The name of the widget used for the layout code. This is also
    /// the name set for the widget for CSS styling.
    name: [:0]const u8,

    /// The widget itself.
    widget: *c.GtkWidget,
};

/// Initialize a new constraint layout view with the given widgets
/// and VFL.
pub fn init(widgets: []const Widget, vfl: []const [*:0]const u8) !View {
    // Box to store all our widgets
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    errdefer c.g_object_unref(box);
    c.gtk_widget_set_vexpand(box, 1);
    c.gtk_widget_set_hexpand(box, 1);

    // Setup our constraint layout and attach it to the box
    const layout = c.gtk_constraint_layout_new();
    errdefer c.g_object_unref(layout);
    c.gtk_widget_set_layout_manager(@ptrCast(box), layout);

    // Setup our views table
    const views = c.g_hash_table_new(c.g_str_hash, c.g_str_equal);
    defer c.g_hash_table_unref(views);

    // Add our widgets
    for (widgets) |widget| {
        c.gtk_widget_set_parent(widget.widget, box);
        c.gtk_widget_set_name(widget.widget, widget.name);
        _ = c.g_hash_table_insert(
            views,
            @constCast(@ptrCast(widget.name.ptr)),
            widget.widget,
        );
    }

    // Add all of our constraints for layout
    var err_: ?*c.GError = null;
    const list = c.gtk_constraint_layout_add_constraints_from_descriptionv(
        @ptrCast(layout),
        vfl.ptr,
        vfl.len,
        8,
        8,
        views,
        &err_,
    );
    if (err_) |err| {
        defer c.g_error_free(err);
        log.warn("error building view message={s}", .{err.message});
        return error.OperationFailed;
    }
    c.g_list_free(list);

    return .{ .root = box };
}
