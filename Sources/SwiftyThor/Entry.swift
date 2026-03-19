/// Entry.swift — @_cdecl implementations of the C entry points declared
/// in CSwiftyThorEntry/swiftythor_entry.h.
///
/// These are plain C-ABI symbols — no @objc, no ObjC runtime dependency.
/// Any FFI consumer (Cython, ctypes, JNI, …) can call them directly.

import AppKit
import QuartzCore
import CThorVG

// Import the SwiftyThor module's types (same package)
// ThorVGEngine, ThorVGRenderer, AngleEGLContext etc.

// MARK: - C entry points

@_cdecl("swiftythor_run_app")
public func swiftythor_run_app() {
    swiftythor_run_app_sized(800, 600)
}

@_cdecl("swiftythor_run_app_sized")
public func swiftythor_run_app_sized(_ width: Int32, _ height: Int32) {
    do {
        try ThorVGEngine.start(threads: 2)
    } catch {
        print("[SwiftyThor] Engine init failed: \(error)")
        return
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)          // appear in Dock + Cmd-Tab
    let delegate = _EntryAppDelegate(width: CGFloat(width), height: CGFloat(height))
    app.delegate = delegate
    app.run()                    // blocks until window closes
    ThorVGEngine.stop()
}

// MARK: - Internal AppDelegate (not @objc-exported, just NSObject subclass)

private final class _EntryAppDelegate: NSObject, NSApplicationDelegate {
    let winW: CGFloat
    let winH: CGFloat

    init(width: CGFloat, height: CGFloat) {
        self.winW = width
        self.winH = height
        super.init()
    }

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 200, y: 200, width: winW, height: winH)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftyThor (from Python)"
        window.contentView = _EntryThorVGView(
            frame: NSRect(origin: .zero, size: rect.size)
        )
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

// MARK: - Reusable ThorVG view (same animated demo, self-contained)

private final class _EntryThorVGView: NSView {
    private var renderer: ThorVGRenderer?
    private var displayLink: CVDisplayLink?
    private var startTime: CFAbsoluteTime = 0
    private var background: Tvg_Paint?
    private var gradientRect: Tvg_Paint?
    private var mainCircle: Tvg_Paint?
    private let numGroups = 6
    private let dotsPerGroup = 5
    private var orbitGlows: [Tvg_Paint] = []
    private var orbitDots: [Tvg_Paint] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let l = CALayer()
        l.isOpaque = true
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        return l
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, renderer == nil, let layer = self.layer else { return }
        let w = Int(bounds.width  * layer.contentsScale)
        let h = Int(bounds.height * layer.contentsScale)
        do {
            renderer = try ThorVGRenderer(layer: layer, width: w, height: h)
            buildScene()
            startTime = CFAbsoluteTimeGetCurrent()
            startDisplayLink()
        } catch {
            print("[SwiftyThor] Renderer init failed:", error)
        }
    }

    // MARK: Scene

    private func buildScene() {
        guard let r = renderer else { return }
        let W = Float(r.width), H = Float(r.height)

        if let bg = tvg_shape_new() {
            tvg_shape_append_rect(bg, 0, 0, W, H, 0, 0, true)
            tvg_shape_set_fill_color(bg, 30, 30, 46, 255)
            tvg_canvas_add(r.canvas, bg)
            background = bg
        }

        if let gr = tvg_shape_new() {
            tvg_shape_append_rect(gr, -150, -100, 300, 200, 16, 16, true)
            if let grad = tvg_linear_gradient_new() {
                tvg_linear_gradient_set(grad, -150, -100, 150, 100)
                var stops: [Tvg_Color_Stop] = [
                    .init(offset: 0.0, r: 255, g: 95,  b: 31,  a: 255),
                    .init(offset: 0.5, r: 200, g: 50,  b: 180, a: 255),
                    .init(offset: 1.0, r: 30,  g: 144, b: 255, a: 255),
                ]
                tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                tvg_shape_set_gradient(gr, grad)
            }
            tvg_canvas_add(r.canvas, gr)
            gradientRect = gr
        }

        if let c = tvg_shape_new() {
            tvg_shape_append_circle(c, 0, 0, 100, 100, true)
            tvg_shape_set_fill_color(c, 0, 200, 120, 220)
            tvg_canvas_add(r.canvas, c)
            mainCircle = c
        }

        let total = numGroups * dotsPerGroup
        for i in 0..<total {
            let hue = Float(i) / Float(total)
            let (cr, cg, cb) = hsvToRGB(h: hue, s: 0.85, v: 1.0)

            if let glow = tvg_shape_new() {
                tvg_shape_append_circle(glow, 0, 0, 40, 40, true)
                if let grad = tvg_radial_gradient_new() {
                    tvg_radial_gradient_set(grad, 0, 0, 40, 0, 0, 0)
                    var stops: [Tvg_Color_Stop] = [
                        .init(offset: 0.0, r: cr, g: cg, b: cb, a: 180),
                        .init(offset: 0.5, r: cr, g: cg, b: cb, a: 60),
                        .init(offset: 1.0, r: cr, g: cg, b: cb, a: 0),
                    ]
                    tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                    tvg_shape_set_gradient(glow, grad)
                }
                tvg_canvas_add(r.canvas, glow)
                orbitGlows.append(glow)
            }

            if let dot = tvg_shape_new() {
                tvg_shape_append_circle(dot, 0, 0, 12, 12, true)
                tvg_shape_set_fill_color(dot, cr, cg, cb, 240)
                tvg_canvas_add(r.canvas, dot)
                orbitDots.append(dot)
            }
        }
    }

    // MARK: Per-frame

    private func updateScene() {
        guard let r = renderer else { return }
        let t = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let W = Float(r.width), H = Float(r.height)
        let cx = W / 2, cy = H / 2

        if let gr = gradientRect {
            let a = t * 0.4
            let px: Float = W * 0.28, py: Float = H * 0.32
            let cs = cosf(a), sn = sinf(a)
            var m = Tvg_Matrix(e11: cs, e12: -sn, e13: px,
                               e21: sn, e22:  cs, e23: py,
                               e31: 0,  e32:  0,  e33: 1)
            tvg_paint_set_transform(gr, &m)
        }

        if let mc = mainCircle {
            let sc = 1.0 + 0.2 * sinf(t * 1.8)
            var m = Tvg_Matrix(e11: sc, e12: 0,  e13: cx,
                               e21: 0,  e22: sc, e23: cy,
                               e31: 0,  e32: 0,  e33: 1)
            tvg_paint_set_transform(mc, &m)
        }

        let bigR: Float = min(W, H) * 0.32
        let smallR: Float = 50.0
        let nG = Float(numGroups), nD = Float(dotsPerGroup)

        for (i, dot) in orbitDots.enumerated() {
            let group = Float(i / dotsPerGroup)
            let idx   = Float(i % dotsPerGroup)
            let ga = (group / nG) * 2 * .pi + t * 0.5
            let gx = cx + bigR * cosf(ga)
            let gy = cy + bigR * sinf(ga)
            let da = (idx / nD) * 2 * .pi - t * 2.2 + group
            let dx = gx + smallR * cosf(da)
            let dy = gy + smallR * sinf(da)

            let s: Float = 0.8 + 0.25 * sinf(t * 2 + Float(i) * 0.5)
            var m = Tvg_Matrix(e11: s, e12: 0, e13: dx,
                               e21: 0, e22: s, e23: dy,
                               e31: 0, e32: 0, e33: 1)
            tvg_paint_set_transform(dot, &m)

            if i < orbitGlows.count {
                let gp: Float = 1.2 + 0.6 * sinf(t * 3 + Float(i) * 0.7)
                let gv = min(max(120 + 100 * sinf(t * 2.5 + Float(i) * 0.9), 0), 255)
                var gm = Tvg_Matrix(e11: gp, e12: 0,  e13: dx,
                                    e21: 0,  e22: gp, e23: dy,
                                    e31: 0,  e32: 0,  e33: 1)
                tvg_paint_set_transform(orbitGlows[i], &gm)
                tvg_paint_set_opacity(orbitGlows[i], UInt8(gv))
            }
        }

        do { try r.render() } catch { print("[SwiftyThor] Render:", error) }
    }

    // MARK: Display link

    private func startDisplayLink() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let link = dl else { return }
        displayLink = link
        let view = Unmanaged.passUnretained(self)
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, ctx) -> CVReturn in
            let v = Unmanaged<_EntryThorVGView>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { v.updateScene() }
            return kCVReturnSuccess
        }, view.toOpaque())
        CVDisplayLinkStart(link)
    }

    deinit { if let dl = displayLink { CVDisplayLinkStop(dl) } }

    private func hsvToRGB(h: Float, s: Float, v: Float) -> (UInt8, UInt8, UInt8) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Float(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Float, Float, Float)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}
