/// KivyThorProvider.swift — bare @_cdecl stubs for kivy_thor_provider.h
///
/// Exports every ktp_* symbol so the dylib links and Cython can import.
/// No logic — just signatures + default return values.

import CThorVG
import CKivyThorProvider
import AppKit


// MARK: - App Init

@_cdecl("ktp_app_init")
public func ktp_app_init(_ embedded: Bool) {
    #if os(macOS)
    // Standalone (embedded=false): Python owns the process — bootstrap NSApplication.
    // Embedded  (embedded=true) : host app already running — just wire the delegate.
    // Always dispatches to main synchronously so windows can be created right after.
    let block = { ThorApplication.setup(embedded: embedded) }
    if Thread.isMainThread { block() } else { DispatchQueue.main.sync(execute: block) }
    #elseif os(iOS)
    // Standalone: UIApplicationMain is owned by Swift entry point — not applicable.
    // Embedded: app already running, nothing to do beyond wiring the delegate.
    #elseif os(Linux)
    // Standalone: gtk_init(nil, nil) / g_application_run(...)
    // Embedded:   host already called gtk_main() — just register callbacks.
    #elseif os(Windows)
    // Standalone: CoInitializeEx, register window class, start message pump.
    // Embedded:   host Win32 message loop already running.
    #elseif os(Android)
    // Standalone: not applicable — Android always launches via Activity.
    // Embedded:   ANativeActivity already set up, Python loaded as .so.
    #else
    // Unsupported platform
    #endif
}


// MARK: - Window Lifecycle

@_cdecl("ktp_engine_start")
public func ktp_engine_start(_ threads: UInt32) {
    #if os(macOS) || os(iOS)
    let t = threads > 0 ? threads : 4
    do {
        try ThorVGEngine.start(threads: t)
    } catch {
        // Already started or engine error — not fatal, log and continue.
        print("[KTP] ktp_engine_start: \(error)")
    }
    #elseif os(Linux)
    // ThorVGEngine.start(threads: threads > 0 ? threads : 4)
    #elseif os(Windows)
    // ThorVGEngine.start(threads: threads > 0 ? threads : 4)
    #endif
}

@_cdecl("ktp_engine_stop")
public func ktp_engine_stop() {
    #if os(macOS) || os(iOS)
    ThorVGEngine.stop()
    #elseif os(Linux)
    // ThorVGEngine.stop()
    #elseif os(Windows)
    // ThorVGEngine.stop()
    #endif
}

@_cdecl("ktp_window_create")
public func ktp_window_create(
    _ x: Int32, _ y: Int32,
    _ w: Int32, _ h: Int32,
    _ borderless: Bool, _ fullscreen: Bool, _ resizable: Bool,
    _ state: Int32,
    _ outW: UnsafeMutablePointer<Int32>?,
    _ outH: UnsafeMutablePointer<Int32>?
) -> KtpWindow? {
    #if os(macOS)
    // Creates an NSWindow, wraps it in KtpWindowState, and returns a retained
    // void* handle that Cython stores as KtpWindow.
    var result: UnsafeMutableRawPointer? = nil

    let block = {
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable  { mask.insert(.resizable) }
        if borderless { mask = [] }

        let screenH = NSScreen.main?.frame.height ?? 768.0
        let winX: CGFloat = x >= 0 ? CGFloat(x) : 200.0
        // AppKit origin is bottom-left; Kivy/SDL uses top-left — flip Y.
        let winY: CGFloat = y >= 0 ? screenH - CGFloat(y) - CGFloat(h) : 200.0
        let rect = NSRect(x: winX, y: winY, width: CGFloat(w), height: CGFloat(h))

        let win = NSWindow(
            contentRect: rect,
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
        win.title = "ThorVG"
        win.contentView = ThorVGView()

        switch state {
        case 1: win.zoom(nil)           // maximized
        case 2: win.miniaturize(nil)    // minimized
        case 3: win.orderOut(nil)       // hidden
        default: win.makeKeyAndOrderFront(nil)
        }

        if fullscreen { win.toggleFullScreen(nil) }

        let contentSize = win.contentRect(forFrameRect: win.frame).size
        outW?.pointee = Int32(contentSize.width)
        outH?.pointee = Int32(contentSize.height)
        
        result = KtpWindowState(window: win).toOpaque()
    }

    if Thread.isMainThread { block() } else { DispatchQueue.main.sync(execute: block) }
    return result
    #elseif os(iOS)
    // Example:
    // let window = UIWindow(frame: CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h)))
    // let vc = UIViewController()
    // window.rootViewController = vc
    // window.makeKeyAndVisible()
    // let renderer = ThorVGRenderer(view: vc.view)
    // return Unmanaged.passRetained(renderer).toOpaque()
    return nil
    #elseif os(Linux)
    // Example (Swift w/ GTK):
    // gtk_init(nil, nil)
    // let window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
    // gtk_window_set_default_size(window, Int32(w), Int32(h))
    // let renderer = ThorVGRenderer(widget: window)
    // return UnsafeMutableRawPointer(Unmanaged.passRetained(renderer).toOpaque())
    return nil
    #elseif os(Windows)
    // Example (Swift w/ WinSDK):
    // let hwnd = CreateWindowExW(
    //     0, L"ThorVGWndClass", L"ThorVG", WS_OVERLAPPEDWINDOW,
    //     Int32(x), Int32(y), Int32(w), Int32(h),
    //     nil, nil, hInstance, nil)
    // let renderer = ThorVGRenderer(hwnd: hwnd)
    // return UnsafeMutableRawPointer(Unmanaged.passRetained(renderer).toOpaque())
    return nil
    #elseif os(Android)
    // Example (Kotlin/NDK):
    // val surface = ANativeWindow_fromSurface(env, surfaceObj)
    // val renderer = ThorVGRenderer(surface)
    // return renderer.nativeHandle
    return nil
    #else
    // Unsupported platform
    return nil
    #endif
}

@_cdecl("ktp_window_destroy")
public func ktp_window_destroy(_ win: KtpWindow?) {
    #if os(macOS)
    guard let ptr = win else { return }
    let state = KtpWindowState.unretained(from: ptr)
    // Close the window on the main thread, then release the Swift object.
    let block = { state.window.close() }
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    KtpWindowState.release(ptr)
    #elseif os(iOS)
    // Example:
    // guard let ptr = win else { return }
    // let state = KtpWindowState.unretained(from: ptr)
    // state.window.isHidden = true
    // KtpWindowState.release(ptr)
    #elseif os(Linux)
    // Example (GTK):
    // if let ptr = win { gtk_widget_destroy(KtpWindowState.unretained(from: ptr).widget) }
    // KtpWindowState.release(ptr)
    #elseif os(Windows)
    // Example: DestroyWindow(state.hwnd); KtpWindowState.release(ptr)
    #elseif os(Android)
    // Example: ANativeWindow_release(state.surface); KtpWindowState.release(ptr)
    #else
    // Unsupported platform
    #endif
}

@_cdecl("ktp_window_resize")
public func ktp_window_resize(_ win: KtpWindow?, _ w: Int32, _ h: Int32) {
    #if os(macOS)
    guard let ptr = win else { return }
    let state = KtpWindowState.unretained(from: ptr)
    let size = NSSize(width: Int(w), height: Int(h))
    let block = { state.window.setContentSize(size) }
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    #elseif os(iOS)
    // Example:
    //     renderer.view.frame.size = CGSize(width: Int(w), height: Int(h))

    #elseif os(Linux)
    // Example (GTK):
    //     gtk_window_resize(renderer.widget, Int32(w), Int32(h))

    #elseif os(Windows)
    // Example (WinSDK):
    //     SetWindowPos(renderer.hwnd, nil, 0, 0, Int32(w), Int32(h), SWP_NOMOVE | SWP_NOZORDER)
    
    #elseif os(Android)
    // Example (NDK):
    //     renderer.surfaceHolder.setFixedSize(w, h)
    
    #else
    // Unsupported platform
    #endif
}


// MARK: - Frame Callback

@_cdecl("ktp_window_set_frame_cb")
public func ktp_window_set_frame_cb(
    _ win: KtpWindow?,
    _ cb: KtpFrameCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud, start CVDisplayLink
}


// MARK: - Mouse Callbacks

@_cdecl("ktp_window_set_mouse_motion_cb")
public func ktp_window_set_mouse_motion_cb(
    _ win: KtpWindow?,
    _ cb: KtpMouseMotionCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_mouse_button_down_cb")
public func ktp_window_set_mouse_button_down_cb(
    _ win: KtpWindow?,
    _ cb: KtpMouseButtonCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_mouse_button_up_cb")
public func ktp_window_set_mouse_button_up_cb(
    _ win: KtpWindow?,
    _ cb: KtpMouseButtonCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_mouse_wheel_cb")
public func ktp_window_set_mouse_wheel_cb(
    _ win: KtpWindow?,
    _ cb: KtpMouseWheelCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}


// MARK: - Touch Callbacks

@_cdecl("ktp_window_set_touch_down_cb")
public func ktp_window_set_touch_down_cb(
    _ win: KtpWindow?,
    _ cb: KtpTouchCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_touch_moved_cb")
public func ktp_window_set_touch_moved_cb(
    _ win: KtpWindow?,
    _ cb: KtpTouchCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_touch_up_cb")
public func ktp_window_set_touch_up_cb(
    _ win: KtpWindow?,
    _ cb: KtpTouchCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}


// MARK: - Keyboard Callbacks

@_cdecl("ktp_window_set_key_down_cb")
public func ktp_window_set_key_down_cb(
    _ win: KtpWindow?,
    _ cb: KtpKeyCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_key_up_cb")
public func ktp_window_set_key_up_cb(
    _ win: KtpWindow?,
    _ cb: KtpKeyCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_text_input_cb")
public func ktp_window_set_text_input_cb(
    _ win: KtpWindow?,
    _ cb: KtpTextCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_text_edit_cb")
public func ktp_window_set_text_edit_cb(
    _ win: KtpWindow?,
    _ cb: KtpTextCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}


// MARK: - Window State Callbacks

@_cdecl("ktp_window_set_resized_cb")
public func ktp_window_set_resized_cb(
    _ win: KtpWindow?,
    _ cb: KtpSizeCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_moved_cb")
public func ktp_window_set_moved_cb(
    _ win: KtpWindow?,
    _ cb: KtpPosCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_close_cb")
public func ktp_window_set_close_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_focus_gained_cb")
public func ktp_window_set_focus_gained_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_focus_lost_cb")
public func ktp_window_set_focus_lost_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_minimized_cb")
public func ktp_window_set_minimized_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_maximized_cb")
public func ktp_window_set_maximized_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_restored_cb")
public func ktp_window_set_restored_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_shown_cb")
public func ktp_window_set_shown_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_hidden_cb")
public func ktp_window_set_hidden_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_exposed_cb")
public func ktp_window_set_exposed_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}


// MARK: - Cursor Enter / Leave

@_cdecl("ktp_window_set_cursor_enter_cb")
public func ktp_window_set_cursor_enter_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_cursor_leave_cb")
public func ktp_window_set_cursor_leave_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}


// MARK: - Drop Callbacks

@_cdecl("ktp_window_set_drop_file_cb")
public func ktp_window_set_drop_file_cb(
    _ win: KtpWindow?,
    _ cb: KtpDropCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_drop_text_cb")
public func ktp_window_set_drop_text_cb(
    _ win: KtpWindow?,
    _ cb: KtpDropCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_drop_begin_cb")
public func ktp_window_set_drop_begin_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}

@_cdecl("ktp_window_set_drop_end_cb")
public func ktp_window_set_drop_end_cb(
    _ win: KtpWindow?,
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store cb/ud
}


// MARK: - App Lifecycle (global)

@_cdecl("ktp_set_app_terminating_cb")
public func ktp_set_app_terminating_cb(
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store global cb/ud, observe NSApplication.willTerminateNotification
}

@_cdecl("ktp_set_app_low_memory_cb")
public func ktp_set_app_low_memory_cb(
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store global cb/ud
}

@_cdecl("ktp_set_app_will_background_cb")
public func ktp_set_app_will_background_cb(
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store global cb/ud, observe resignActive
}

@_cdecl("ktp_set_app_did_foreground_cb")
public func ktp_set_app_did_foreground_cb(
    _ cb: KtpVoidCb?,
    _ ud: UnsafeMutableRawPointer?
) {
    // TODO: Store global cb/ud, observe didBecomeActive
}


// MARK: - Window Properties

@_cdecl("ktp_window_set_title")
public func ktp_window_set_title(
    _ win: KtpWindow?,
    _ title: UnsafePointer<CChar>?
) {
    // TODO: window.title = String(cString: title)
}

@_cdecl("ktp_window_set_icon")
public func ktp_window_set_icon(
    _ win: KtpWindow?,
    _ filename: UnsafePointer<CChar>?
) {
    // TODO: Load image, set as dock icon
}

@_cdecl("ktp_window_set_pos")
public func ktp_window_set_pos(
    _ win: KtpWindow?,
    _ x: Int32,
    _ y: Int32
) {
    // TODO: window.setFrameOrigin(...)
    print("Swift set_pos", x, y)
    NSApplication.shared.keyWindow?.contentView?.frame.origin = .init(x: Int(x), y: Int(y))
}

@_cdecl("ktp_window_get_pos")
public func ktp_window_get_pos(
    _ win: KtpWindow?,
    _ outX: UnsafeMutablePointer<Int32>?,
    _ outY: UnsafeMutablePointer<Int32>?
) {
    // TODO: Read window.frame.origin
}

@_cdecl("ktp_window_get_size")
public func ktp_window_get_size(
    _ win: KtpWindow?,
    _ outW: UnsafeMutablePointer<Int32>?,
    _ outH: UnsafeMutablePointer<Int32>?
) {
    // TODO: Read contentView frame size
}

@_cdecl("ktp_window_get_pixel_size")
public func ktp_window_get_pixel_size(
    _ win: KtpWindow?,
    _ outW: UnsafeMutablePointer<Int32>?,
    _ outH: UnsafeMutablePointer<Int32>?
) {
    // TODO: contentView size * backingScaleFactor
}

@_cdecl("ktp_window_set_opacity")
public func ktp_window_set_opacity(
    _ win: KtpWindow?,
    _ opacity: Float
) -> Bool {
    // TODO: window.alphaValue = CGFloat(opacity)
    return false
}

@_cdecl("ktp_window_get_opacity")
public func ktp_window_get_opacity(_ win: KtpWindow?) -> Float {
    // TODO: return Float(window.alphaValue)
    return 1.0
}

@_cdecl("ktp_window_get_pixel_density")
public func ktp_window_get_pixel_density(_ win: KtpWindow?) -> Float {
    // TODO: return Float(window.backingScaleFactor)
    return 1.0
}

@_cdecl("ktp_window_get_display_scale")
public func ktp_window_get_display_scale(_ win: KtpWindow?) -> Float {
    // TODO: return Float(window.backingScaleFactor)
    return 1.0
}

@_cdecl("ktp_window_set_minimum_size")
public func ktp_window_set_minimum_size(
    _ win: KtpWindow?,
    _ w: Int32,
    _ h: Int32
) {
    // TODO: window.minSize = NSSize(...)
}

@_cdecl("ktp_window_set_always_on_top")
public func ktp_window_set_always_on_top(
    _ win: KtpWindow?,
    _ on: Bool
) {
    // TODO: window.level = on ? .floating : .normal
}

@_cdecl("ktp_window_set_allow_screensaver")
public func ktp_window_set_allow_screensaver(
    _ win: KtpWindow?,
    _ allow: Bool
) {
    // TODO: IOPMAssertionCreateWithName / release
}

@_cdecl("ktp_window_set_border_state")
public func ktp_window_set_border_state(
    _ win: KtpWindow?,
    _ borderless: Bool
) {
    // TODO: Toggle styleMask between .borderless and titled
}

@_cdecl("ktp_window_set_fullscreen_mode")
public func ktp_window_set_fullscreen_mode(
    _ win: KtpWindow?,
    _ fullscreen: Bool
) {
    // TODO: toggleFullScreen if state differs
}


// MARK: - Window State

@_cdecl("ktp_window_maximize")
public func ktp_window_maximize(_ win: KtpWindow?) {
    // TODO: window.zoom(nil)
}

@_cdecl("ktp_window_minimize")
public func ktp_window_minimize(_ win: KtpWindow?) {
    // TODO: window.miniaturize(nil)
}

@_cdecl("ktp_window_restore")
public func ktp_window_restore(_ win: KtpWindow?) {
    // TODO: window.deminiaturize(nil)
}

@_cdecl("ktp_window_hide")
public func ktp_window_hide(_ win: KtpWindow?) {
    // TODO: window.orderOut(nil)
}

@_cdecl("ktp_window_show")
public func ktp_window_show(_ win: KtpWindow?) {
    // TODO: window.makeKeyAndOrderFront(nil)
}

@_cdecl("ktp_window_raise")
public func ktp_window_raise(_ win: KtpWindow?) {
    // TODO: window.orderFrontRegardless()
}


// MARK: - Cursor / Mouse

@_cdecl("ktp_window_set_cursor_visible")
public func ktp_window_set_cursor_visible(
    _ win: KtpWindow?,
    _ visible: Bool
) {
    // TODO: NSCursor.unhide() / .hide()
}

@_cdecl("ktp_window_set_system_cursor")
public func ktp_window_set_system_cursor(
    _ win: KtpWindow?,
    _ name: UnsafePointer<CChar>?
) -> Bool {
    // TODO: Map name string to NSCursor, call .set()
    return false
}

@_cdecl("ktp_window_grab_mouse")
public func ktp_window_grab_mouse(
    _ win: KtpWindow?,
    _ grab: Bool
) {
    // TODO: CGAssociateMouseAndMouseCursorPosition
}

@_cdecl("ktp_window_get_relative_mouse_pos")
public func ktp_window_get_relative_mouse_pos(
    _ win: KtpWindow?,
    _ outX: UnsafeMutablePointer<Float>?,
    _ outY: UnsafeMutablePointer<Float>?
) {
    // TODO: Read mouseLocationOutsideOfEventStream, flip Y
}


// MARK: - Keyboard

@_cdecl("ktp_window_show_keyboard")
public func ktp_window_show_keyboard(
    _ win: KtpWindow?,
    _ inputType: UnsafePointer<CChar>?,
    _ suggestions: Bool,
    _ softinputMode: Int32
) {
    // TODO: No-op on macOS (physical keyboard always present)
}

@_cdecl("ktp_window_hide_keyboard")
public func ktp_window_hide_keyboard(_ win: KtpWindow?) {
    // TODO: No-op on macOS
}

@_cdecl("ktp_window_is_keyboard_shown")
public func ktp_window_is_keyboard_shown(_ win: KtpWindow?) -> Bool {
    // TODO: Always true on macOS
    return false
}

@_cdecl("ktp_window_get_key_modifiers")
public func ktp_window_get_key_modifiers(_ win: KtpWindow?) -> Int32 {
    // TODO: Read NSEvent.modifierFlags, map to bitmask
    return 0
}


// MARK: - Shape / Transparency

@_cdecl("ktp_window_is_shapable")
public func ktp_window_is_shapable(_ win: KtpWindow?) -> Bool {
    // TODO: Return true if shaped windows are supported
    return false
}

@_cdecl("ktp_window_set_shape")
public func ktp_window_set_shape(
    _ win: KtpWindow?,
    _ pixels: UnsafePointer<UInt8>?,
    _ w: Int32,
    _ h: Int32
) {
    // TODO: Apply alpha mask to window shape
}


// MARK: - Screenshot

@_cdecl("ktp_window_save_png")
public func ktp_window_save_png(
    _ win: KtpWindow?,
    _ filename: UnsafePointer<CChar>?,
    _ data: UnsafePointer<UInt8>?,
    _ w: Int32,
    _ h: Int32
) {
    // TODO: Write RGBA data to PNG file via CGImage
}


// MARK: - Custom Titlebar

@_cdecl("ktp_window_set_custom_titlebar")
public func ktp_window_set_custom_titlebar(
    _ win: KtpWindow?,
    _ cb: KtpHitTestCb?,
    _ ud: UnsafeMutableRawPointer?
) -> Int32 {
    // TODO: Install hit-test delegate for custom titlebar regions
    return 0
}


// MARK: - System Theme

@_cdecl("ktp_get_system_theme")
public func ktp_get_system_theme() -> UnsafePointer<CChar>? {
    // TODO: Read NSApp.effectiveAppearance, return "light"/"dark"
    return nil
}


// MARK: - ThorVG Canvas Access

@_cdecl("ktp_window_get_canvas")
public func ktp_window_get_canvas(_ win: KtpWindow?) -> Tvg_Canvas? {
    // TODO: Return the GlCanvas from ThorVGRenderer
    return nil
}

@_cdecl("ktp_window_get_canvas_size")
public func ktp_window_get_canvas_size(
    _ win: KtpWindow?,
    _ outW: UnsafeMutablePointer<Int32>?,
    _ outH: UnsafeMutablePointer<Int32>?
) {
    // TODO: Return pixel-size of the canvas backing
}
