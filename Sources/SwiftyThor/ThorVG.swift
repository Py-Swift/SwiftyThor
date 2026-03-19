/// SwiftyThor – thin Swift wrapper around ThorVG's C-API (GlCanvas via ANGLE).
///
/// Typical usage:
/// ```swift
/// try ThorVGEngine.start()
/// let renderer = try ThorVGRenderer(layer: myCALayer, width: 800, height: 600)
/// renderer.drawDemo()          // draw shapes
/// try renderer.render()        // update → draw → sync
/// ThorVGEngine.stop()
/// ```

import CThorVG
import QuartzCore

// Swift can't import EGL_CAST macros, so define the sentinel values here.
public let EGL_NO_DISPLAY_: EGLDisplay? = nil
public let EGL_NO_SURFACE_: EGLSurface? = nil
public let EGL_NO_CONTEXT_: EGLContext? = nil

// MARK: - Result helper

public enum ThorVGError: Error, CustomStringConvertible {
    case engineInit
    case eglSetup(String)
    case canvasCreate
    case canvasTarget
    case renderFailed(String)

    public var description: String {
        switch self {
        case .engineInit:           return "tvg_engine_init failed"
        case .eglSetup(let msg):    return "EGL: \(msg)"
        case .canvasCreate:         return "tvg_glcanvas_create failed"
        case .canvasTarget:         return "tvg_glcanvas_set_target failed"
        case .renderFailed(let m):  return "Render: \(m)"
        }
    }
}

@discardableResult
@inline(__always)
func tvgCheck(_ result: Tvg_Result, _ ctx: String = "") throws -> Tvg_Result {
    guard result == TVG_RESULT_SUCCESS else {
        throw ThorVGError.renderFailed("\(ctx) → code \(result.rawValue)")
    }
    return result
}

// MARK: - Engine lifecycle

public enum ThorVGEngine {
    /// Call once at app start. `threads` = 0 means main-thread only.
    public static func start(threads: UInt32 = 0) throws {
        let r = tvg_engine_init(threads)
        guard r == TVG_RESULT_SUCCESS else { throw ThorVGError.engineInit }
    }
    public static func stop() {
        tvg_engine_term()
    }
}

// MARK: - ANGLE EGL context

/// Manages an EGL display / surface / context backed by ANGLE's Metal backend.
public final class AngleEGLContext {
    public let display: EGLDisplay
    public let surface: EGLSurface
    public let context: EGLContext

    /// Create an ANGLE-Metal EGL context rendering into `layer`.
    public init(layer: CALayer, width: Int, height: Int) throws {
        // ── Display ──
        var displayAttribs: [EGLAttrib] = [
            EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_ANGLE),
            EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE),
            EGLAttrib(EGL_NONE),
        ]
        guard let dpy = eglGetPlatformDisplay(
            EGLenum(EGL_PLATFORM_ANGLE_ANGLE),
            nil,     // EGL_DEFAULT_DISPLAY
            &displayAttribs
        ) else {
            throw ThorVGError.eglSetup("eglGetPlatformDisplay failed (error \(eglGetError()))")
        }
        self.display = dpy

        var major: EGLint = 0
        var minor: EGLint = 0
        guard eglInitialize(display, &major, &minor) == EGL_TRUE else {
            throw ThorVGError.eglSetup("eglInitialize failed (error \(eglGetError()))")
        }
        print("[ANGLE] EGL \(major).\(minor) initialised")

        // ── Config ──
        var configAttribs: [EGLint] = [
            EGL_RED_SIZE,       8,
            EGL_GREEN_SIZE,     8,
            EGL_BLUE_SIZE,      8,
            EGL_ALPHA_SIZE,     8,
            EGL_DEPTH_SIZE,     0,
            EGL_STENCIL_SIZE,   8,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_SURFACE_TYPE,   EGL_WINDOW_BIT,
            EGL_NONE,
        ]
        var config: EGLConfig?
        var numConfigs: EGLint = 0
        guard eglChooseConfig(display, &configAttribs, &config, 1, &numConfigs) == EGL_TRUE,
              numConfigs > 0, let cfg = config else {
            throw ThorVGError.eglSetup("eglChooseConfig failed (error \(eglGetError()))")
        }

        // ── Surface  (ANGLE takes a CALayer pointer as native window) ──
        let layerPtr = Unmanaged.passUnretained(layer).toOpaque()
        guard let surf = eglCreateWindowSurface(display, cfg, layerPtr, nil) else {
            throw ThorVGError.eglSetup("eglCreateWindowSurface failed (error \(eglGetError()))")
        }
        self.surface = surf

        // ── Context (ES 3.0) ──
        var ctxAttribs: [EGLint] = [
            EGL_CONTEXT_MAJOR_VERSION, 3,
            EGL_CONTEXT_MINOR_VERSION, 0,
            EGL_NONE,
        ]
        guard let ctx = eglCreateContext(display, cfg, nil, &ctxAttribs) else {
            throw ThorVGError.eglSetup("eglCreateContext failed (error \(eglGetError()))")
        }
        self.context = ctx

        guard eglMakeCurrent(display, surface, surface, context) == EGL_TRUE else {
            throw ThorVGError.eglSetup("eglMakeCurrent failed (error \(eglGetError()))")
        }
        print("[ANGLE] Context current — ES 3.0 on Metal")
    }

    public func makeCurrent() {
        eglMakeCurrent(display, surface, surface, context)
    }

    public func swapBuffers() {
        eglSwapBuffers(display, surface)
    }

    deinit {
        eglMakeCurrent(display, nil, nil, nil)
        eglDestroyContext(display, context)
        eglDestroySurface(display, surface)
        eglTerminate(display)
    }
}

// MARK: - ThorVG GlCanvas renderer

public final class ThorVGRenderer {
    public let canvas: Tvg_Canvas
    public let egl: AngleEGLContext
    public let width: UInt32
    public let height: UInt32

    /// Create a GlCanvas that renders into `layer` via ANGLE.
    public init(layer: CALayer, width: Int, height: Int) throws {
        self.width  = UInt32(width)
        self.height = UInt32(height)

        // EGL
        egl = try AngleEGLContext(layer: layer, width: width, height: height)

        // ThorVG canvas
        guard let c = tvg_glcanvas_create(TVG_ENGINE_OPTION_DEFAULT) else {
            throw ThorVGError.canvasCreate
        }
        self.canvas = c

        let r = tvg_glcanvas_set_target(
            canvas,
            egl.display,     // display
            egl.surface,     // surface
            egl.context,     // context
            0,               // framebuffer id (default)
            self.width,
            self.height,
            TVG_COLORSPACE_ABGR8888S
        )
        guard r == TVG_RESULT_SUCCESS else {
            print("tvg_glcanvas_set_target returned \(r.rawValue)")
            throw ThorVGError.canvasTarget
        }
    }

    // MARK: Convenience shape helpers

    public func addRect(x: Float, y: Float, w: Float, h: Float,
                        rx: Float = 0, ry: Float = 0,
                        r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) throws {
        guard let shape = tvg_shape_new() else { return }
        tvg_shape_append_rect(shape, x, y, w, h, rx, ry, true)
        tvg_shape_set_fill_color(shape, r, g, b, a)
        try tvgCheck(tvg_canvas_add(canvas, shape), "addRect")
    }

    public func addCircle(cx: Float, cy: Float, rx: Float, ry: Float,
                          r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) throws {
        guard let shape = tvg_shape_new() else { return }
        tvg_shape_append_circle(shape, cx, cy, rx, ry, true)
        tvg_shape_set_fill_color(shape, r, g, b, a)
        try tvgCheck(tvg_canvas_add(canvas, shape), "addCircle")
    }

    public func addStrokedRect(x: Float, y: Float, w: Float, h: Float,
                                strokeWidth: Float = 3,
                                sr: UInt8, sg: UInt8, sb: UInt8, sa: UInt8 = 255,
                                fr: UInt8, fg: UInt8, fb: UInt8, fa: UInt8 = 255) throws {
        guard let shape = tvg_shape_new() else { return }
        tvg_shape_append_rect(shape, x, y, w, h, 0, 0, true)
        tvg_shape_set_fill_color(shape, fr, fg, fb, fa)
        tvg_shape_set_stroke_width(shape, strokeWidth)
        tvg_shape_set_stroke_color(shape, sr, sg, sb, sa)
        try tvgCheck(tvg_canvas_add(canvas, shape), "addStrokedRect")
    }

    public func addGradientRect(x: Float, y: Float, w: Float, h: Float,
                                 colors: [(offset: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) throws {
        guard let shape = tvg_shape_new() else { return }
        tvg_shape_append_rect(shape, x, y, w, h, 0, 0, true)

        guard let grad = tvg_linear_gradient_new() else { return }
        tvg_linear_gradient_set(grad, x, y, x + w, y + h)

        var stops = colors.map { Tvg_Color_Stop(offset: $0.offset, r: $0.r, g: $0.g, b: $0.b, a: $0.a) }
        tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
        tvg_shape_set_gradient(shape, grad)
        try tvgCheck(tvg_canvas_add(canvas, shape), "addGradientRect")
    }

    // MARK: Render cycle

    /// update → draw → sync → eglSwapBuffers
    public func render(clear: Bool = true) throws {
        egl.makeCurrent()
        try tvgCheck(tvg_canvas_update(canvas), "update")
        try tvgCheck(tvg_canvas_draw(canvas, clear), "draw")
        try tvgCheck(tvg_canvas_sync(canvas), "sync")
        egl.swapBuffers()
    }

    public func clear() throws {
        try tvgCheck(tvg_canvas_remove(canvas, nil), "clear")
    }

    deinit {
        tvg_canvas_destroy(canvas)
    }
}
