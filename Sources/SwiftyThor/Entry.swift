/// Entry.swift — @_cdecl implementations of the C entry points declared
/// in CSwiftyThorEntry/swiftythor_entry.h.
///
/// These are plain C-ABI symbols — no @objc, no ObjC runtime dependency.
/// Any FFI consumer (Cython, ctypes, JNI, …) can call them directly.

import AppKit
import QuartzCore
import CThorVG

// MARK: - C entry points

@_cdecl("swiftythor_run_app")
public func swiftythor_run_app() {
    swiftythor_run_app_sized(1800, 900)
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
    app.setActivationPolicy(.regular)
    let delegate = _EntryAppDelegate(width: CGFloat(width), height: CGFloat(height))
    app.delegate = delegate
    app.run()
    ThorVGEngine.stop()
}

// MARK: - AppDelegate

private final class _EntryAppDelegate: NSObject, NSApplicationDelegate {
    let winW: CGFloat
    let winH: CGFloat
    init(width: CGFloat, height: CGFloat) { self.winW = width; self.winH = height; super.init() }
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 200, y: 200, width: winW, height: winH)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "SwiftyThor (from Python)"
        window.contentView = _EntryThorVGView(frame: NSRect(origin: .zero, size: rect.size))
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

// MARK: - Main view — driven by ThorScreenManager

private final class _EntryThorVGView: NSView {
    private var renderer: ThorVGRenderer?
    private var displayLink: CVDisplayLink?
    private var startTime: CFAbsoluteTime = 0
    private let manager = ThorScreenManager()

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let l = CALayer(); l.isOpaque = true
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
            setupScreens()
            startTime = CFAbsoluteTimeGetCurrent()
            startDisplayLink()
        } catch { print("[SwiftyThor] Renderer init failed:", error) }
    }

    // MARK: Setup

    private func setupScreens() {
        guard let r = renderer else { return }
        let W = Float(r.width), H = Float(r.height)
        manager.add(OrbitScreen(name: "Orbits",    manager: manager))
        manager.add(PulseScreen(name: "Pulse",     manager: manager))
        manager.add(ParticleScreen(name: "Particles", manager: manager))
        manager.buildAll(canvas: r.canvas, width: W, height: H)
    }

    // MARK: Per-frame

    private func tick() {
        guard let r = renderer else { return }
        let t = Float(CFAbsoluteTimeGetCurrent() - startTime)
        manager.update(t: t, width: Float(r.width), height: Float(r.height))
        do { try r.render() } catch { print("[SwiftyThor] Render:", error) }
    }

    // MARK: Mouse → ScreenManager

    override func mouseDown(with event: NSEvent) {
        guard let layer = self.layer else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let scale = Float(layer.contentsScale)
        let px = Float(loc.x) * scale
        let py = Float(bounds.height - loc.y) * scale   // flip Y
        manager.handleClick(px: px, py: py)
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
            DispatchQueue.main.async { v.tick() }
            return kCVReturnSuccess
        }, view.toOpaque())
        CVDisplayLinkStart(link)
    }

    deinit { if let dl = displayLink { CVDisplayLinkStop(dl) } }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: ─── Screen 1: Orbiting Dots ─────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════

/// Animated orbiting dots with a pulsing centre circle on a dark background.
private final class OrbitScreen: ThorScreen {
    let name: String
    var buttons: [ThorButton] = []
    var transitionX: Float = 0
    var transitionAlpha: Float = 1.0

    private weak var mgr: ThorScreenManager?
    private var allPaints: [Tvg_Paint] = []
    private var background: Tvg_Paint?
    private var gradientRect: Tvg_Paint?
    private var mainCircle: Tvg_Paint?
    private var orbitGlows: [Tvg_Paint] = []
    private var orbitDots: [Tvg_Paint] = []
    private let numGroups = 6
    private let dotsPerGroup = 5

    init(name: String, manager: ThorScreenManager) {
        self.name = name; self.mgr = manager
    }

    func buildScene(canvas: Tvg_Canvas, width W: Float, height H: Float) {
        // ── Dark background ──
        if let bg = tvg_shape_new() {
            tvg_shape_append_rect(bg, 0, 0, W, H, 0, 0, true)
            tvg_shape_set_fill_color(bg, 24, 24, 42, 255)
            tvg_canvas_add(canvas, bg)
            background = bg; allPaints.append(bg)
        }

        // ── Rotating gradient rectangle ──
        if let gr = tvg_shape_new() {
            tvg_shape_append_rect(gr, -180, -120, 360, 240, 20, 20, true)
            if let grad = tvg_linear_gradient_new() {
                tvg_linear_gradient_set(grad, -180, -120, 180, 120)
                var stops: [Tvg_Color_Stop] = [
                    .init(offset: 0.0, r: 255, g: 80,  b: 30,  a: 255),
                    .init(offset: 0.5, r: 200, g: 40,  b: 180, a: 255),
                    .init(offset: 1.0, r: 30,  g: 140, b: 255, a: 255),
                ]
                tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                tvg_shape_set_gradient(gr, grad)
            }
            tvg_canvas_add(canvas, gr)
            gradientRect = gr; allPaints.append(gr)
        }

        // ── Pulsing centre circle ──
        if let c = tvg_shape_new() {
            tvg_shape_append_circle(c, 0, 0, 110, 110, true)
            tvg_shape_set_fill_color(c, 0, 210, 130, 210)
            tvg_canvas_add(canvas, c)
            mainCircle = c; allPaints.append(c)
        }

        // ── Orbiting dots + glow halos ──
        let total = numGroups * dotsPerGroup
        for i in 0..<total {
            let hue = Float(i) / Float(total)
            let (cr, cg, cb) = hsvToRGB(h: hue, s: 0.85, v: 1.0)

            if let glow = tvg_shape_new() {
                tvg_shape_append_circle(glow, 0, 0, 44, 44, true)
                if let grad = tvg_radial_gradient_new() {
                    tvg_radial_gradient_set(grad, 0, 0, 44, 0, 0, 0)
                    var stops: [Tvg_Color_Stop] = [
                        .init(offset: 0.0, r: cr, g: cg, b: cb, a: 180),
                        .init(offset: 0.5, r: cr, g: cg, b: cb, a: 50),
                        .init(offset: 1.0, r: cr, g: cg, b: cb, a: 0),
                    ]
                    tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                    tvg_shape_set_gradient(glow, grad)
                }
                tvg_canvas_add(canvas, glow)
                orbitGlows.append(glow); allPaints.append(glow)
            }

            if let dot = tvg_shape_new() {
                tvg_shape_append_circle(dot, 0, 0, 13, 13, true)
                tvg_shape_set_fill_color(dot, cr, cg, cb, 240)
                tvg_canvas_add(canvas, dot)
                orbitDots.append(dot); allPaints.append(dot)
            }
        }

        // ── "Next →" button (bottom-right) ──
        let btn = ThorButton(x: W - 220, y: H - 90, width: 200, height: 66,
                             label: "Next", r: 40, g: 110, b: 230)
        btn.onTap = { [weak self] in self?.mgr?.next() }
        buttons.append(btn)
    }

    func update(t: Float, width W: Float, height H: Float) {
        let ox = transitionX

        // ── Hidden? Zero-out everything and bail ──
        if transitionAlpha <= 0 {
            for p in allPaints { tvg_paint_set_opacity(p, 0) }
            return
        }

        // ── Background (just translate) ──
        if let bg = background {
            var m = Tvg_Matrix(e11: 1, e12: 0, e13: ox,
                               e21: 0, e22: 1, e23: 0,
                               e31: 0, e32: 0, e33: 1)
            tvg_paint_set_transform(bg, &m)
            tvg_paint_set_opacity(bg, 255)
        }

        let cx = W / 2 + ox, cy = H / 2

        // ── Rotating gradient rect ──
        if let gr = gradientRect {
            let a  = t * 0.4
            let px = W * 0.28 + ox, py = H * 0.32
            let cs = cosf(a), sn = sinf(a)
            var m = Tvg_Matrix(e11: cs, e12: -sn, e13: px,
                               e21: sn, e22:  cs, e23: py,
                               e31: 0,  e32:  0,  e33: 1)
            tvg_paint_set_transform(gr, &m)
            tvg_paint_set_opacity(gr, 255)
        }

        // ── Pulsing centre circle ──
        if let mc = mainCircle {
            let sc = 1.0 + 0.22 * sinf(t * 1.8)
            var m = Tvg_Matrix(e11: sc, e12: 0,  e13: cx,
                               e21: 0,  e22: sc, e23: cy,
                               e31: 0,  e32: 0,  e33: 1)
            tvg_paint_set_transform(mc, &m)
            tvg_paint_set_opacity(mc, 210)
        }

        // ── Orbiting dots & glows ──
        let bigR: Float = min(W, H) * 0.32
        let smallR: Float = 55.0
        let nG = Float(numGroups), nD = Float(dotsPerGroup)

        for (i, dot) in orbitDots.enumerated() {
            let group = Float(i / dotsPerGroup)
            let idx   = Float(i % dotsPerGroup)
            let ga  = (group / nG) * 2 * .pi + t * 0.5
            let gx  = cx + bigR * cosf(ga)
            let gy  = cy + bigR * sinf(ga)
            let da  = (idx / nD) * 2 * .pi - t * 2.2 + group
            let dx  = gx + smallR * cosf(da)
            let dy  = gy + smallR * sinf(da)

            let s: Float = 0.8 + 0.3 * sinf(t * 2 + Float(i) * 0.5)
            var dm = Tvg_Matrix(e11: s, e12: 0, e13: dx,
                                e21: 0, e22: s, e23: dy,
                                e31: 0, e32: 0, e33: 1)
            tvg_paint_set_transform(dot, &dm)
            tvg_paint_set_opacity(dot, 240)

            if i < orbitGlows.count {
                let gp: Float = 1.3 + 0.7 * sinf(t * 3 + Float(i) * 0.7)
                let gv = UInt8(min(max(120 + 100 * sinf(t * 2.5 + Float(i) * 0.9), 0), 255))
                var gm = Tvg_Matrix(e11: gp, e12: 0,  e13: dx,
                                    e21: 0,  e22: gp, e23: dy,
                                    e31: 0,  e32: 0,  e33: 1)
                tvg_paint_set_transform(orbitGlows[i], &gm)
                tvg_paint_set_opacity(orbitGlows[i], gv)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: ─── Screen 2: Neon Pulse ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════

/// Deep-purple background with concentric radar rings and spinning neon shapes.
private final class PulseScreen: ThorScreen {
    let name: String
    var buttons: [ThorButton] = []
    var transitionX: Float = 0
    var transitionAlpha: Float = 0.0

    private weak var mgr: ThorScreenManager?
    private var allPaints: [Tvg_Paint] = []
    private var background: Tvg_Paint?
    private var rings: [Tvg_Paint] = []
    private var floaters: [Tvg_Paint] = []
    private var sweepLine: Tvg_Paint?
    private let ringCount = 5
    private let floaterCount = 18

    init(name: String, manager: ThorScreenManager) {
        self.name = name; self.mgr = manager
    }

    func buildScene(canvas: Tvg_Canvas, width W: Float, height H: Float) {
        // ── Gradient background ──
        if let bg = tvg_shape_new() {
            tvg_shape_append_rect(bg, 0, 0, W, H, 0, 0, true)
            if let grad = tvg_linear_gradient_new() {
                tvg_linear_gradient_set(grad, 0, 0, W, H)
                var stops: [Tvg_Color_Stop] = [
                    .init(offset: 0.0, r: 12,  g: 6,   b: 36,  a: 255),
                    .init(offset: 0.5, r: 55,  g: 15,  b: 80,  a: 255),
                    .init(offset: 1.0, r: 10,  g: 30,  b: 60,  a: 255),
                ]
                tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                tvg_shape_set_gradient(bg, grad)
            }
            tvg_canvas_add(canvas, bg)
            background = bg; allPaints.append(bg)
        }

        // ── Concentric radar rings ──
        let maxR = min(W, H) * 0.42
        for i in 1...ringCount {
            if let ring = tvg_shape_new() {
                let r = maxR * Float(i) / Float(ringCount)
                tvg_shape_append_circle(ring, 0, 0, r, r, true)
                tvg_shape_set_fill_color(ring, 0, 0, 0, 0)         // no fill
                tvg_shape_set_stroke_width(ring, 1.5)
                tvg_shape_set_stroke_color(ring, 120, 80, 255, UInt8(40 + i * 15))
                tvg_canvas_add(canvas, ring)
                rings.append(ring); allPaints.append(ring)
            }
        }

        // ── Sweep line (radial) ──
        if let sw = tvg_shape_new() {
            tvg_shape_append_rect(sw, 0, -2, maxR, 4, 2, 2, true)
            if let grad = tvg_linear_gradient_new() {
                tvg_linear_gradient_set(grad, 0, 0, maxR, 0)
                var stops: [Tvg_Color_Stop] = [
                    .init(offset: 0.0, r: 160, g: 120, b: 255, a: 200),
                    .init(offset: 0.6, r: 100, g: 60,  b: 255, a: 80),
                    .init(offset: 1.0, r: 60,  g: 30,  b: 200, a: 0),
                ]
                tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                tvg_shape_set_gradient(sw, grad)
            }
            tvg_canvas_add(canvas, sw)
            sweepLine = sw; allPaints.append(sw)
        }

        // ── Floating neon shapes ──
        for i in 0..<floaterCount {
            if let shape = tvg_shape_new() {
                // Alternate between circles and rounded rects
                if i % 3 == 0 {
                    let r = Float.random(in: 15...35)
                    tvg_shape_append_circle(shape, 0, 0, r, r, true)
                } else {
                    let w = Float.random(in: 30...80)
                    let h = Float.random(in: 20...50)
                    tvg_shape_append_rect(shape, -w/2, -h/2, w, h, 8, 8, true)
                }
                let hue = Float(i) / Float(floaterCount)
                let (cr, cg, cb) = hsvToRGB(h: hue, s: 0.75, v: 1.0)
                tvg_shape_set_fill_color(shape, cr, cg, cb, 160)
                tvg_canvas_add(canvas, shape)
                floaters.append(shape); allPaints.append(shape)
            }
        }

        // ── "← Prev" button (bottom-left) ──
        let btnPrev = ThorButton(x: 20, y: H - 90, width: 200, height: 66,
                             label: "Prev", r: 200, g: 60, b: 60)
        btnPrev.onTap = { [weak self] in self?.mgr?.prev() }
        buttons.append(btnPrev)

        // ── "Next →" button (bottom-right) ──
        let btnNext = ThorButton(x: W - 220, y: H - 90, width: 200, height: 66,
                             label: "Next", r: 40, g: 110, b: 230)
        btnNext.onTap = { [weak self] in self?.mgr?.next() }
        buttons.append(btnNext)
    }

    func update(t: Float, width W: Float, height H: Float) {
        let ox = transitionX

        // ── Hidden? ──
        if transitionAlpha <= 0 {
            for p in allPaints { tvg_paint_set_opacity(p, 0) }
            return
        }

        // ── Background ──
        if let bg = background {
            var m = Tvg_Matrix(e11: 1, e12: 0, e13: ox,
                               e21: 0, e22: 1, e23: 0,
                               e31: 0, e32: 0, e33: 1)
            tvg_paint_set_transform(bg, &m)
            tvg_paint_set_opacity(bg, 255)
        }

        let cx = W / 2 + ox, cy = H / 2

        // ── Rings: pulse radius ──
        for (i, ring) in rings.enumerated() {
            let fi = Float(i + 1)
            let pulse = 1.0 + 0.06 * sinf(t * 2.0 + fi * 0.8)
            let sc = pulse
            var m = Tvg_Matrix(e11: sc, e12: 0,  e13: cx,
                               e21: 0,  e22: sc, e23: cy,
                               e31: 0,  e32: 0,  e33: 1)
            tvg_paint_set_transform(ring, &m)
            let alpha = UInt8(min(max(50 + 30 * sinf(t * 1.5 + fi), 30), 120))
            tvg_paint_set_opacity(ring, alpha)
        }

        // ── Sweep line rotates ──
        if let sw = sweepLine {
            let angle = t * 1.4
            let cs = cosf(angle), sn = sinf(angle)
            var m = Tvg_Matrix(e11: cs, e12: -sn, e13: cx,
                               e21: sn, e22:  cs, e23: cy,
                               e31: 0,  e32:  0,  e33: 1)
            tvg_paint_set_transform(sw, &m)
            tvg_paint_set_opacity(sw, 200)
        }

        // ── Floating shapes: orbit + spin ──
        for (i, shape) in floaters.enumerated() {
            let fi = Float(i)
            let layer = fi.truncatingRemainder(dividingBy: 3)

            // Each "layer" orbits at a different speed/radius
            let speed   = 0.25 + layer * 0.12 + fi * 0.03
            let orbitR  = W * (0.12 + layer * 0.1) + 40 * sinf(t * 0.4 + fi)
            let angle   = t * speed + fi * (2 * .pi / Float(floaterCount))
            let px      = cx + orbitR * cosf(angle)
            let py      = cy + orbitR * sinf(angle) * (0.6 + 0.15 * layer)

            let rot = t * (0.6 + fi * 0.12)
            let cs = cosf(rot), sn = sinf(rot)
            let sc: Float = 0.6 + 0.4 * sinf(t * 1.1 + fi * 0.7)

            var m = Tvg_Matrix(
                e11: sc * cs, e12: -sc * sn, e13: px,
                e21: sc * sn, e22:  sc * cs, e23: py,
                e31: 0,       e32:  0,       e33: 1
            )
            tvg_paint_set_transform(shape, &m)
            let alpha = UInt8(min(max(80 + 140 * sinf(t * 0.9 + fi * 0.5), 30), 220))
            tvg_paint_set_opacity(shape, alpha)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: ─── Screen 3: Particle Fountain ─────────────────────────────
// ═══════════════════════════════════════════════════════════════════════

/// Per-particle state — value type for tight packing / cache friendliness.
private struct Particle {
    var x: Float = 0
    var y: Float = 0
    var vx: Float = 0
    var vy: Float = 0
    var age: Float = 0
    var lifetime: Float = 3
    var baseRadius: Float = 6
    var r: UInt8 = 255
    var g: UInt8 = 180
    var b: UInt8 = 60
    var alive: Bool = false
}

/// Port of screen_5.py — fountain of ThorVG circles that spawn,
/// arc under gravity, fade out and recycle.
private final class ParticleScreen: ThorScreen {
    let name: String
    var buttons: [ThorButton] = []
    var transitionX: Float = 0
    var transitionAlpha: Float = 0.0

    private weak var mgr: ThorScreenManager?
    private var allPaints: [Tvg_Paint] = []     // bg only
    private var background: Tvg_Paint?
    private var particlePaints: [Tvg_Paint] = []
    private var particles: [Particle] = []
    private var prevT: Float = 0

    // Tunables (matching screen_5.py defaults)
    private let maxParticles = 800
    private let spawnRate    = 10            // per frame
    private let gravity: Float = -280       // px/s² (negative = falls in canvas coords)
    private let baseLifetime: Float = 3.0
    private let speedMul: Float = 1.0
    private let sizeMul: Float  = 1.0

    init(name: String, manager: ThorScreenManager) {
        self.name = name; self.mgr = manager
    }

    func buildScene(canvas: Tvg_Canvas, width W: Float, height H: Float) {
        // ── Background — warm dark ──
        if let bg = tvg_shape_new() {
            tvg_shape_append_rect(bg, 0, 0, W, H, 0, 0, true)
            tvg_shape_set_fill_color(bg, 10, 10, 20, 255)
            tvg_canvas_add(canvas, bg)
            background = bg; allPaints.append(bg)
        }

        // ── Pre-allocate particle circles (all offscreen / invisible) ──
        particles.reserveCapacity(maxParticles)
        particlePaints.reserveCapacity(maxParticles)
        for _ in 0..<maxParticles {
            if let shape = tvg_shape_new() {
                tvg_shape_append_circle(shape, 0, 0, 1, 1, true)
                tvg_shape_set_fill_color(shape, 0, 0, 0, 0)
                tvg_canvas_add(canvas, shape)
                particlePaints.append(shape)
            }
            particles.append(Particle())
        }

        // ── "← Prev" button (bottom-left) ──
        let btn = ThorButton(x: 20, y: H - 90, width: 200, height: 66,
                             label: "Prev", r: 200, g: 60, b: 60)
        btn.onTap = { [weak self] in self?.mgr?.prev() }
        buttons.append(btn)
    }

    // MARK: Update

    func update(t: Float, width W: Float, height H: Float) {
        let ox = transitionX

        // ── Hidden → zero everything ──
        if transitionAlpha <= 0 {
            for p in allPaints { tvg_paint_set_opacity(p, 0) }
            for pp in particlePaints { tvg_paint_set_opacity(pp, 0) }
            prevT = t
            return
        }

        // ── Background ──
        if let bg = background {
            var m = Tvg_Matrix(e11: 1, e12: 0, e13: ox,
                               e21: 0, e22: 1, e23: 0,
                               e31: 0, e32: 0, e33: 1)
            tvg_paint_set_transform(bg, &m)
            tvg_paint_set_opacity(bg, 255)
        }

        // ── dt (clamped to avoid huge jumps on first frame / resume) ──
        let dt = min(t - prevT, 0.05)
        prevT = t

        let scale = (W + H) / 1200.0   // reference size factor

        // Spawn point: centre-bottom of canvas
        let spawnX = W / 2 + ox
        let spawnY = H * 0.75           // 75 % down from top

        // ── Spawn new particles ──
        var spawned = 0
        for i in 0..<maxParticles where spawned < spawnRate {
            if !particles[i].alive {
                spawn(&particles[i], sx: spawnX, sy: spawnY, scale: scale)
                spawned += 1
            }
        }

        // ── Simulate + render each particle ──
        let grav = gravity * scale  // canvas-space gravity (negative → downward)

        for i in 0..<maxParticles {
            let paint = particlePaints[i]

            if !particles[i].alive {
                tvg_paint_set_opacity(paint, 0)
                continue
            }

            particles[i].age += dt
            if particles[i].age >= particles[i].lifetime {
                particles[i].alive = false
                tvg_paint_set_opacity(paint, 0)
                continue
            }

            // Physics: gravity points downward (+Y = down in canvas)
            particles[i].vy -= grav * dt    // grav is negative, so vy increases → particle falls
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt

            let life = particles[i].age / particles[i].lifetime  // 0→1

            // Fade + shrink
            let alpha = UInt8(max(0, min(255, 255.0 * (1.0 - life * life))))
            let radius = particles[i].baseRadius * max(0.15, 1.0 - life * 0.7)

            // Transform: translate + uniform scale
            let px = particles[i].x
            let py = particles[i].y
            var tm = Tvg_Matrix(e11: radius, e12: 0,      e13: px,
                                e21: 0,      e22: radius, e23: py,
                                e31: 0,      e32: 0,      e33: 1)
            tvg_paint_set_transform(paint, &tm)

            // Colour — set once at spawn via fill, but alpha changes each frame.
            // Re-set fill colour with current alpha.
            tvg_shape_set_fill_color(paint,
                                     particles[i].r, particles[i].g,
                                     particles[i].b, alpha)
            tvg_paint_set_opacity(paint, alpha)
        }
    }

    // MARK: Spawn helper

    private func spawn(_ p: inout Particle, sx: Float, sy: Float, scale: Float) {
        // Fan upward: 50 – 130 ° (in canvas coords where -Y is up)
        let angle = Float.random(in: 50...130) * (.pi / 180.0)
        let speed = Float.random(in: 200...420) * scale * speedMul

        p.x = sx + Float.random(in: -24...24) * scale
        p.y = sy
        p.vx = cosf(angle) * speed + Float.random(in: -35...35) * scale
        p.vy = -sinf(angle) * speed + Float.random(in: -25...25) * scale  // negative = upward
        p.age = 0
        p.lifetime = Float.random(in: baseLifetime * 0.55 ... baseLifetime)
        p.baseRadius = Float.random(in: 3...10) * scale * sizeMul

        // Warm palette: oranges, yellows, pinks, magentas
        let roll = Float.random(in: 0...1)
        if roll < 0.3 {
            p.r = 255; p.g = UInt8.random(in: 60...180); p.b = UInt8.random(in: 0...40)
        } else if roll < 0.55 {
            p.r = 255; p.g = UInt8.random(in: 180...255); p.b = UInt8.random(in: 0...60)
        } else if roll < 0.75 {
            p.r = UInt8.random(in: 200...255); p.g = UInt8.random(in: 0...80); p.b = UInt8.random(in: 150...255)
        } else {
            p.r = 255; p.g = UInt8.random(in: 220...255); p.b = UInt8.random(in: 160...255)
        }
        p.alive = true
    }
}

// MARK: - Colour helper

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
