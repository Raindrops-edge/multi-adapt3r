pub const c = @import("c.zig").c;

// OpenGL
pub extern fn ImGui_ImplOpenGL3_Init(?[*:0]const u8) callconv(.C) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() callconv(.C) void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(*c.ImDrawData) callconv(.C) void;

// Metal
pub extern fn ImGui_ImplMetal_Init(*anyopaque) callconv(.C) bool;
pub extern fn ImGui_ImplMetal_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplMetal_NewFrame(*anyopaque) callconv(.C) void;
pub extern fn ImGui_ImplMetal_RenderDrawData(*c.ImDrawData, *anyopaque, *anyopaque) callconv(.C) void;

// OSX
pub extern fn ImGui_ImplOSX_Init(*anyopaque) callconv(.C) bool;
pub extern fn ImGui_ImplOSX_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplOSX_NewFrame(*anyopaque) callconv(.C) void;

test {}
