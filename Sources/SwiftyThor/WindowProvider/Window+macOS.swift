//
//  Window+macOS.swift
//  SwiftyThor
//
//  Created by CodeBuilder on 21/03/2026.
//
// Window+macOS.swift
//
// MacOSWindowProvider is a lightweight helper used during development/testing
// to manually create a window outside of the Cython KTP path.
// Real windows are created via ktp_window_create() → KtpWindowState.

import AppKit


final class MacOSWindowProvider {

    var window: NSWindow?

    init(
        x: Int = 200, y: Int = 200,
        width: Int = 1280, height: Int = 720,
        title: String = "ThorVG",
        resizable: Bool = true
    ) {
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { mask.insert(.resizable) }

        let rect = NSRect(x: x, y: y, width: width, height: height)
        let win = NSWindow(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
        win.title = title
        self.window = win
        print(Self.self, "created window at \(x)x\(y) with size \(width)x\(height)")
        
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}

