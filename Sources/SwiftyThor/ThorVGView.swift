//
//  ThorVGView.swift
//  SwiftyThor
//
//  Created by CodeBuilder on 21/03/2026.
//
import AppKit
import CThorVG
import CKivyThorProvider

final class ThorVGView: NSView {
    private var renderer: ThorVGRenderer?
    private var displayLink: CVDisplayLink?
    private var startTime: CFAbsoluteTime = 0

    // Keep paint handles so we can transform them each frame
    private var background: Tvg_Paint?
    private var gradientRect: Tvg_Paint?
    private var mainCircle: Tvg_Paint?
    private var strokedRect: Tvg_Paint?
    private let numGroups  = 6       // clusters on the main ring
    private let dotsPerGroup = 5       // dots in each sub-circle
    private var orbitGlows: [Tvg_Paint] = []  // glow halos (drawn first, behind dots)
    private var orbitDots: [Tvg_Paint] = []   // numGroups × dotsPerGroup

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.isOpaque = true
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        return layer
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
            print("ThorVGRenderer init failed:", error)
        }
    }

    // MARK: Build the initial scene (shapes added once, transformed each frame)

    private func buildScene() {
        guard let r = renderer else { return }
        let W = Float(r.width)
        let H = Float(r.height)

        // 1) Background — stays put
        if let bg = tvg_shape_new() {
            tvg_shape_append_rect(bg, 0, 0, W, H, 0, 0, true)
            tvg_shape_set_fill_color(bg, 30, 30, 46, 255)
            tvg_canvas_add(r.canvas, bg)
            background = bg
        }

        // 2) Gradient rectangle — will rotate slowly
        if let gr = tvg_shape_new() {
            tvg_shape_append_rect(gr, -150, -100, 300, 200, 16, 16, true)
            if let grad = tvg_linear_gradient_new() {
                tvg_linear_gradient_set(grad, -150, -100, 150, 100)
                var stops: [Tvg_Color_Stop] = [
                    Tvg_Color_Stop(offset: 0.0, r: 255, g: 95,  b: 31,  a: 255),
                    Tvg_Color_Stop(offset: 0.5, r: 200, g: 50,  b: 180, a: 255),
                    Tvg_Color_Stop(offset: 1.0, r: 30,  g: 144, b: 255, a: 255),
                ]
                tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                tvg_shape_set_gradient(gr, grad)
            }
            tvg_canvas_add(r.canvas, gr)
            gradientRect = gr
        }

        // 3) Main pulsing circle — drawn at origin, translated each frame
        if let c = tvg_shape_new() {
            tvg_shape_append_circle(c, 0, 0, 100, 100, true)
            tvg_shape_set_fill_color(c, 0, 200, 120, 220)
            tvg_canvas_add(r.canvas, c)
            mainCircle = c
        }

        // 4) Stroked rectangle — bobs up and down
        if let sr = tvg_shape_new() {
            tvg_shape_append_rect(sr, -115, -65, 230, 130, 8, 8, true)
            tvg_shape_set_fill_color(sr, 50, 50, 80, 200)
            tvg_shape_set_stroke_width(sr, 4)
            tvg_shape_set_stroke_color(sr, 255, 220, 50, 255)
            tvg_canvas_add(r.canvas, sr)
            strokedRect = sr
        }

        // 5) Circle-of-circles: 6 groups × 5 dots each
        //    Each dot gets a glow halo (radial gradient) drawn behind it
        let totalDots = numGroups * dotsPerGroup
        for i in 0..<totalDots {
            let hue = Float(i) / Float(totalDots)
            let (cr, cg, cb) = hsvToRGB(h: hue, s: 0.85, v: 1.0)

            // Glow halo — large soft radial gradient circle
            if let glow = tvg_shape_new() {
                tvg_shape_append_circle(glow, 0, 0, 40, 40, true)
                if let grad = tvg_radial_gradient_new() {
                    tvg_radial_gradient_set(grad, 0, 0, 40, 0, 0, 0)
                    var stops: [Tvg_Color_Stop] = [
                        Tvg_Color_Stop(offset: 0.0, r: cr, g: cg, b: cb, a: 180),
                        Tvg_Color_Stop(offset: 0.5, r: cr, g: cg, b: cb, a: 60),
                        Tvg_Color_Stop(offset: 1.0, r: cr, g: cg, b: cb, a: 0),
                    ]
                    tvg_gradient_set_color_stops(grad, &stops, UInt32(stops.count))
                    tvg_shape_set_gradient(glow, grad)
                }
                tvg_canvas_add(r.canvas, glow)
                orbitGlows.append(glow)
            }

            // Solid dot on top
            if let dot = tvg_shape_new() {
                tvg_shape_append_circle(dot, 0, 0, 12, 12, true)
                tvg_shape_set_fill_color(dot, cr, cg, cb, 240)
                tvg_canvas_add(r.canvas, dot)
                orbitDots.append(dot)
            }
        }
    }

    // MARK: Per-frame update

    private func updateScene() {
        guard let r = renderer else { return }
        let t = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let W = Float(r.width)
        let H = Float(r.height)
        let cx = W / 2
        let cy = H / 2

        // Gradient rect: rotate around its center at top-left area
        if let gr = gradientRect {
            var m = Tvg_Matrix(
                e11: 1, e12: 0, e13: 0,
                e21: 0, e22: 1, e23: 0,
                e31: 0, e32: 0, e33: 1
            )
            let angle = t * 0.4          // slow rotation (radians)
            let px: Float = W * 0.28
            let py: Float = H * 0.32
            let c = cosf(angle), s = sinf(angle)
            m.e11 = c;  m.e12 = -s; m.e13 = px
            m.e21 = s;  m.e22 =  c; m.e23 = py
            tvg_paint_set_transform(gr, &m)
        }

        // Main circle: breathe (pulse scale) at center
        if let mc = mainCircle {
            let scale = 1.0 + 0.2 * sinf(t * 1.8)
            var m = Tvg_Matrix(
                e11: scale, e12: 0,     e13: cx,
                e21: 0,     e22: scale, e23: cy,
                e31: 0,     e32: 0,     e33: 1
            )
            tvg_paint_set_transform(mc, &m)
        }

        // Stroked rect: bob up/down on the right side
        if let sr = strokedRect {
            let bobY = cy + 40.0 * sinf(t * 1.2)
            var m = Tvg_Matrix(
                e11: 1, e12: 0, e13: W * 0.75,
                e21: 0, e22: 1, e23: bobY,
                e31: 0, e32: 0, e33: 1
            )
            tvg_paint_set_transform(sr, &m)
        }

        // Circle-of-circles: main ring spins, each group is a
        // visible sub-circle of dots that also spins independently
        let bigR: Float = min(W, H) * 0.32         // main ring radius
        let smallR: Float = 50.0                    // sub-circle radius (big enough to see!)
        let ringSpeed: Float = 0.5                  // main ring rotation
        let subSpeed: Float  = 2.2                  // sub-circle rotation
        let nG = Float(numGroups)
        let nD = Float(dotsPerGroup)

        for (i, dot) in orbitDots.enumerated() {
            let group = Float(i / dotsPerGroup)     // which cluster (0..<6)
            let idx   = Float(i % dotsPerGroup)     // position within cluster (0..<5)

            // group center on the main ring
            let groupAngle = (group / nG) * 2.0 * .pi + t * ringSpeed
            let gx = cx + bigR * cosf(groupAngle)
            let gy = cy + bigR * sinf(groupAngle)

            // dot position on the sub-circle (spins the other way)
            let dotAngle = (idx / nD) * 2.0 * .pi - t * subSpeed + group * 1.0
            let dx = gx + smallR * cosf(dotAngle)
            let dy = gy + smallR * sinf(dotAngle)

            let s: Float = 0.8 + 0.25 * sinf(t * 2.0 + Float(i) * 0.5)
            var m = Tvg_Matrix(
                e11: s,  e12: 0,  e13: dx,
                e21: 0,  e22: s,  e23: dy,
                e31: 0,  e32: 0,  e33: 1
            )
            tvg_paint_set_transform(dot, &m)

            // Glow halo: same position, larger scale, pulsing opacity
            if i < orbitGlows.count {
                let glowPulse: Float = 1.2 + 0.6 * sinf(t * 3.0 + Float(i) * 0.7)
                let glowVal = min(max(120.0 + 100.0 * sinf(t * 2.5 + Float(i) * 0.9), 0), 255)
                let glowOpacity = UInt8(glowVal)
                var gm = Tvg_Matrix(
                    e11: glowPulse, e12: 0,         e13: dx,
                    e21: 0,         e22: glowPulse, e23: dy,
                    e31: 0,         e32: 0,         e33: 1
                )
                tvg_paint_set_transform(orbitGlows[i], &gm)
                tvg_paint_set_opacity(orbitGlows[i], glowOpacity)
            }
        }

        // Render
        do {
            try r.render()
        } catch {
            print("[Demo] Render error:", error)
        }
    }

    // MARK: Display link

    private func startDisplayLink() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let link = dl else { return }
        displayLink = link

        let view = Unmanaged.passUnretained(self)
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, userInfo) -> CVReturn in
            let v = Unmanaged<ThorVGView>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async { v.updateScene() }
            return kCVReturnSuccess
        }, view.toOpaque())

        CVDisplayLinkStart(link)
        print("[Demo] Display link started")
        
    }

    deinit {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
        }
    }

    // MARK: HSV helper

    private func hsvToRGB(h: Float, s: Float, v: Float) -> (UInt8, UInt8, UInt8) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Float(Int(h * 6))
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
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
