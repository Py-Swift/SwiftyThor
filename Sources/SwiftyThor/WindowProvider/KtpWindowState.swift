// KtpWindowState.swift — per-window state for the KTP provider.
//
// Holds the platform window object (NSWindow on macOS, UIWindow on iOS, …)
// together with every C callback/userdata pair registered by Cython.
//
// The instance is heap-allocated through Unmanaged and handed to Cython as
// a raw void*.  Lifecycle:
//   create  → Unmanaged.passRetained(state).toOpaque()   → returned as KtpWindow
//   borrow  → KtpWindowState.unretained(from: ptr)       → used inside every ktp_* stub
//   destroy → KtpWindowState.release(ptr)                → called by ktp_window_destroy

import Foundation
import CKivyThorProvider

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif


// MARK: - KtpWindowState

final class KtpWindowState {

    // MARK: Platform window

    #if os(macOS)
    let window: NSWindow
    #elseif os(iOS)
    let window: UIWindow
    #else
    // Unsupported platform — placeholder
    #endif


    // MARK: Stored callbacks (C function pointers + userdata)

    // Frame
    var frameCb:        KtpFrameCb?              = nil
    var frameUd:        UnsafeMutableRawPointer? = nil

    // Mouse
    var mouseMotionCb:  KtpMouseMotionCb?        = nil
    var mouseMotionUd:  UnsafeMutableRawPointer? = nil

    var mouseBtnDownCb: KtpMouseButtonCb?        = nil
    var mouseBtnDownUd: UnsafeMutableRawPointer? = nil

    var mouseBtnUpCb:   KtpMouseButtonCb?        = nil
    var mouseBtnUpUd:   UnsafeMutableRawPointer? = nil

    var mouseWheelCb:   KtpMouseWheelCb?         = nil
    var mouseWheelUd:   UnsafeMutableRawPointer? = nil

    // Touch
    var touchDownCb:    KtpTouchCb?              = nil
    var touchDownUd:    UnsafeMutableRawPointer? = nil

    var touchMovedCb:   KtpTouchCb?              = nil
    var touchMovedUd:   UnsafeMutableRawPointer? = nil

    var touchUpCb:      KtpTouchCb?              = nil
    var touchUpUd:      UnsafeMutableRawPointer? = nil

    // Keyboard
    var keyDownCb:      KtpKeyCb?                = nil
    var keyDownUd:      UnsafeMutableRawPointer? = nil

    var keyUpCb:        KtpKeyCb?                = nil
    var keyUpUd:        UnsafeMutableRawPointer? = nil

    var textInputCb:    KtpTextCb?               = nil
    var textInputUd:    UnsafeMutableRawPointer? = nil

    var textEditCb:     KtpTextCb?               = nil
    var textEditUd:     UnsafeMutableRawPointer? = nil

    // Window state
    var resizedCb:      KtpSizeCb?               = nil
    var resizedUd:      UnsafeMutableRawPointer? = nil

    var movedCb:        KtpPosCb?                = nil
    var movedUd:        UnsafeMutableRawPointer? = nil

    var closeCb:        KtpVoidCb?               = nil
    var closeUd:        UnsafeMutableRawPointer? = nil

    var focusGainCb:    KtpVoidCb?               = nil
    var focusGainUd:    UnsafeMutableRawPointer? = nil

    var focusLostCb:    KtpVoidCb?               = nil
    var focusLostUd:    UnsafeMutableRawPointer? = nil

    var minimizedCb:    KtpVoidCb?               = nil
    var minimizedUd:    UnsafeMutableRawPointer? = nil

    var maximizedCb:    KtpVoidCb?               = nil
    var maximizedUd:    UnsafeMutableRawPointer? = nil

    var restoredCb:     KtpVoidCb?               = nil
    var restoredUd:     UnsafeMutableRawPointer? = nil

    var shownCb:        KtpVoidCb?               = nil
    var shownUd:        UnsafeMutableRawPointer? = nil

    var hiddenCb:       KtpVoidCb?               = nil
    var hiddenUd:       UnsafeMutableRawPointer? = nil

    var exposedCb:      KtpVoidCb?               = nil
    var exposedUd:      UnsafeMutableRawPointer? = nil

    // Cursor enter / leave
    var cursorEnterCb:  KtpVoidCb?               = nil
    var cursorEnterUd:  UnsafeMutableRawPointer? = nil

    var cursorLeaveCb:  KtpVoidCb?               = nil
    var cursorLeaveUd:  UnsafeMutableRawPointer? = nil

    // Drop
    var dropFileCb:     KtpDropCb?               = nil
    var dropFileUd:     UnsafeMutableRawPointer? = nil

    var dropTextCb:     KtpDropCb?               = nil
    var dropTextUd:     UnsafeMutableRawPointer? = nil

    var dropBeginCb:    KtpVoidCb?               = nil
    var dropBeginUd:    UnsafeMutableRawPointer? = nil

    var dropEndCb:      KtpVoidCb?               = nil
    var dropEndUd:      UnsafeMutableRawPointer? = nil

    // Custom titlebar
    var hitTestCb:      KtpHitTestCb?            = nil
    var hitTestUd:      UnsafeMutableRawPointer? = nil

    // Root widgets
    var rootWidgets: [KtpRootWidget] = []


    // MARK: - Init

    #if os(macOS)
    init(window: NSWindow) {
        self.window = window
    }
    #elseif os(iOS)
    init(window: UIWindow) {
        self.window = window
    }
    #endif


    // MARK: - Opaque handle helpers

    /// Retain `self` and return as a raw void* to give to Cython as KtpWindow.
    func toOpaque() -> UnsafeMutableRawPointer {
        return Unmanaged.passRetained(self).toOpaque()
    }

    /// Borrow the state from a void* without changing retain count.
    /// Safe to call from any ktp_* stub that holds a valid window handle.
    static func unretained(from ptr: UnsafeMutableRawPointer) -> KtpWindowState {
        return Unmanaged<KtpWindowState>.fromOpaque(ptr).takeUnretainedValue()
    }

    /// Release the retained reference.  Call exactly once, in ktp_window_destroy.
    static func release(_ ptr: UnsafeMutableRawPointer) {
        Unmanaged<KtpWindowState>.fromOpaque(ptr).release()
    }
}
