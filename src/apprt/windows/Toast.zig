/// Windows toast notification support via WinRT COM APIs.
///
/// Displays toast notifications when long-running commands complete in
/// unfocused terminals. Uses lazy initialization for the WinRT notifier
/// so COM activation only occurs on the first notification.
const Toast = @This();

const std = @import("std");
const com = @import("com.zig");

const log = std.log.scoped(.toast);

// ---------------------------------------------------------------------------
// Win32 types
// ---------------------------------------------------------------------------

const HWND = std.os.windows.HWND;
const BOOL = std.os.windows.BOOL;

extern "user32" fn GetForegroundWindow() callconv(.c) ?HWND;
extern "user32" fn SetForegroundWindow(hwnd: HWND) callconv(.c) BOOL;

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// Cached WinRT toast notifier (lazy-initialized on first show).
notifier: ?*com.IToastNotifier = null,

/// Back-reference to the owning App for tab activation on click.
app: *@import("App.zig") = undefined,

/// Last tab index passed to show(), stored for activation on toast click.
/// When the user clicks a toast notification while the app is running,
/// handleActivation() uses this to switch to the correct tab.
last_tab_index: ?usize = null,

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

const App = @import("App.zig");

pub fn init(app: *App) Toast {
    return .{
        .notifier = null,
        .app = app,
    };
}

pub fn deinit(self: *Toast) void {
    if (self.notifier) |notifier| {
        const unknown: *com.IUnknown = @ptrCast(notifier);
        _ = unknown.release();
        self.notifier = null;
    }
}

// ---------------------------------------------------------------------------
// Show notification
// ---------------------------------------------------------------------------

/// Show a toast notification with the given title and body text.
/// If tab_index is provided, clicking the toast will switch to that tab.
///
/// This function is non-critical: all errors are logged and swallowed.
/// Toast failures must never crash the application.
pub fn show(self: *Toast, title: [:0]const u8, body: [:0]const u8, tab_index: ?usize) void {
    self.last_tab_index = tab_index;
    self.showInner(title, body, tab_index) catch |err| {
        log.warn("Toast notification failed: {}", .{err});
    };
}

fn showInner(self: *Toast, title: [:0]const u8, body: [:0]const u8, tab_index: ?usize) com.HResultError!void {
    // Lazy-init the notifier on first call.
    if (self.notifier == null) {
        self.notifier = try initNotifier();
    }
    const notifier = self.notifier orelse return error.HResultFail;

    // Build toast XML string with optional launch attribute for tab activation.
    // The launch attribute encodes the tab index so clicking the toast can
    // switch to the correct tab. Format: launch="tab:N"
    // TODO: Full COM activation callback (INotificationActivationCallback)
    // will enable click handling for packaged (MSIX) apps on cold-start.
    // For now, the in-process handleActivation() covers the warm-start case.
    var xml_buf: [2048]u8 = undefined;
    const xml_str = if (tab_index) |idx|
        std.fmt.bufPrint(&xml_buf, "<toast launch=\"tab:{d}\"><visual><binding template=\"ToastGeneric\"><text>{s}</text><text>{s}</text></binding></visual></toast>", .{ idx, title, body }) catch return error.HResultFail
    else
        std.fmt.bufPrint(&xml_buf, "<toast><visual><binding template=\"ToastGeneric\"><text>{s}</text><text>{s}</text></binding></visual></toast>", .{ title, body }) catch return error.HResultFail;

    // Convert XML to UTF-16.
    var xml_wide: [2048]u16 = undefined;
    const xml_wide_len = std.unicode.utf8ToUtf16Le(&xml_wide, xml_str) catch return error.HResultFail;
    if (xml_wide_len >= xml_wide.len) return error.HResultFail;
    xml_wide[xml_wide_len] = 0;

    // Create XmlDocument via RoActivateInstance.
    const xml_doc_class = comptime com.L("Windows.Data.Xml.Dom.XmlDocument");
    var xml_doc_header: com.HSTRING_HEADER = undefined;
    const xml_doc_hstring = try com.hstring(xml_doc_class, &xml_doc_header);
    const xml_doc_inspectable = try com.activateInstance(xml_doc_hstring);

    // QI for IXmlDocumentIO to call LoadXml.
    var xml_doc_io_raw: ?*anyopaque = null;
    try com.check(xml_doc_inspectable.vtable.QueryInterface(
        xml_doc_inspectable,
        &com.IXmlDocumentIO.IID,
        &xml_doc_io_raw,
    ));
    const xml_doc_io: *com.IXmlDocumentIO = @ptrCast(@alignCast(xml_doc_io_raw.?));
    defer {
        const unknown: *com.IUnknown = @ptrCast(xml_doc_io);
        _ = unknown.release();
    }

    // Create HSTRING for the XML content.
    const xml_slice: [:0]const u16 = xml_wide[0..xml_wide_len :0];
    var xml_hstring_header: com.HSTRING_HEADER = undefined;
    const xml_hstring = try com.hstring(xml_slice, &xml_hstring_header);

    // Load the XML.
    try com.check(xml_doc_io.vtable.LoadXml(xml_doc_io, xml_hstring));

    // QI the XmlDocument inspectable for IXmlDocument (needed by factory).
    var xml_doc_raw: ?*anyopaque = null;
    try com.check(xml_doc_inspectable.vtable.QueryInterface(
        xml_doc_inspectable,
        &com.IXmlDocument.IID,
        &xml_doc_raw,
    ));
    const xml_doc: *com.IXmlDocument = @ptrCast(@alignCast(xml_doc_raw.?));
    defer {
        const unknown: *com.IUnknown = @ptrCast(xml_doc);
        _ = unknown.release();
    }

    // Release the inspectable now that we have the typed pointer.
    _ = xml_doc_inspectable.release();

    // Get IToastNotificationFactory.
    const toast_class = comptime com.L("Windows.UI.Notifications.ToastNotification");
    var toast_class_header: com.HSTRING_HEADER = undefined;
    const toast_class_hstring = try com.hstring(toast_class, &toast_class_header);
    const factory_raw = try com.getActivationFactory(toast_class_hstring, &com.IToastNotificationFactory.IID);
    const factory: *com.IToastNotificationFactory = @ptrCast(@alignCast(factory_raw));
    defer {
        const unknown: *com.IUnknown = @ptrCast(factory);
        _ = unknown.release();
    }

    // Create the toast notification from the XML document.
    var toast: ?*com.IToastNotification = null;
    try com.check(factory.vtable.CreateToastNotification(factory, xml_doc, &toast));
    const toast_obj = toast orelse return error.HResultFail;
    defer {
        const unknown: *com.IUnknown = @ptrCast(toast_obj);
        _ = unknown.release();
    }

    // Show the toast.
    try com.check(notifier.vtable.Show(notifier, toast_obj));

    log.info("Toast notification shown: {s}", .{title});
}

// ---------------------------------------------------------------------------
// Toast click activation (warm-start only)
// ---------------------------------------------------------------------------

/// Handle a toast notification click when the app is already running.
/// Brings the main window to the foreground and switches to the tab
/// that was active when the notification was shown.
///
/// Note: This only works for warm-start (app already running). For cold-start
/// scenarios where Windows relaunches the exe via COM activation, a full
/// INotificationActivationCallback implementation is needed (deferred).
pub fn handleActivation(self: *Toast) void {
    const tab_index = self.last_tab_index orelse return;
    const app = self.app;

    // Bring the window to the foreground and restore if minimized.
    if (app.hwnd) |hwnd| {
        const SW_RESTORE: i32 = 9;
        _ = ShowWindow(hwnd, SW_RESTORE);
        _ = SetForegroundWindow(hwnd);
    }

    // Switch to the tab that triggered the notification.
    app.switchToTab(tab_index);
    log.info("Toast activation: switched to tab {}", .{tab_index});
}

extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: i32) callconv(.c) BOOL;

/// Initialize the WinRT toast notifier.
fn initNotifier() com.HResultError!*com.IToastNotifier {
    // Get IToastNotificationManagerStatics.
    const manager_class = comptime com.L("Windows.UI.Notifications.ToastNotificationManager");
    var manager_header: com.HSTRING_HEADER = undefined;
    const manager_hstring = try com.hstring(manager_class, &manager_header);
    const manager_raw = try com.getActivationFactory(manager_hstring, &com.IToastNotificationManagerStatics.IID);
    const manager: *com.IToastNotificationManagerStatics = @ptrCast(@alignCast(manager_raw));
    defer {
        const unknown: *com.IUnknown = @ptrCast(manager);
        _ = unknown.release();
    }

    // Create notifier with AUMID for the app identity.
    const aumid = comptime com.L("Ghostty.Terminal");
    var aumid_header: com.HSTRING_HEADER = undefined;
    const aumid_hstring = try com.hstring(aumid, &aumid_header);

    var notifier: ?*com.IToastNotifier = null;
    try com.check(manager.vtable.CreateToastNotifierWithId(manager, aumid_hstring, &notifier));

    return notifier orelse return error.HResultFail;
}
