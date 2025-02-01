// This file is used to provide compatibility if necessary with
// older versions of GTK and GLib.

#include <gtk/gtk.h>

// Compatibility with gobject < 2.74
#ifndef G_CONNECT_DEFAULT
#define G_CONNECT_DEFAULT 0
#endif

// Compatibility with gobject < 2.74
#ifndef G_APPLICATION_DEFAULT_FLAGS
#define G_APPLICATION_DEFAULT_FLAGS G_APPLICATION_FLAGS_NONE
#endif
