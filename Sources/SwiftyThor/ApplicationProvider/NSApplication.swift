//
//  NSApplication.swift
//  SwiftyThor
//
//  Created by CodeBuilder on 21/03/2026.
//

import AppKit



final class ThorApplication: NSApplication {

    private static var _isSetup = false

    /// Call once from ktp_app_init().
    ///
    /// - Parameter embedded: When `true` the host NSApplication is already
    ///   running (Xcode / native app launched Python).  We skip NSApplication
    ///   init and only attach the AppDelegate so ThorVG can still start via
    ///   applicationWillFinishLaunching. When `false` (standalone: Python owns
    ///   the process) we do the full bootstrap ourselves.
    static func setup(embedded: Bool) {
        guard !_isSetup else { return }
        _isSetup = true
        print(Self.self, "setup")
        let app = NSApplication.shared
        
        
        if embedded {
            // Host app already called NSApplicationMain / app.run().
            // Just attach our delegate so ThorVG engine starts, then bail.
            // Do NOT call finishLaunching() — it would be called twice.
            if app.delegate == nil {
                app.delegate = AppDelegate.shared
            }
        } else {
            // Standalone: Python is the process owner.
            // Wire delegate, set policy, then finish launching.
            app.delegate = AppDelegate.shared
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            app.activate(ignoringOtherApps: true)
        }
        app.run()
    }

    override init() {
        super.init()
        self.delegate = AppDelegate.shared
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

//    static func main() {
//        do {
//            try ThorVGEngine.start(threads: 4)
//        } catch {
//            fatalError("ThorVG engine init failed: \(error)")
//        }
//        
//        let app = NSApplication.shared
//        let delegate = AppDelegate()
//        app.delegate = delegate
//        app.run()
//    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    //var window: NSWindow!
    
    static let shared = AppDelegate()
    
    var threads: UInt32 = 4
    
    override init() {
       
    }
    
    
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        
        
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Windows are created on demand via ktp_window_create() from Cython.
        // Nothing to do here — no hardcoded window.
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    
    func applicationWillTerminate(_ notification: Notification) {
        ThorVGEngine.stop()
    }
}
