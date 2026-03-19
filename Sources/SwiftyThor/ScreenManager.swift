/// ScreenManager.swift — Button, Screen & ScreenManager for SwiftyThor.
///
/// • `ThorButton`        – Hit-testable rectangle rendered via ThorVG.
/// • `ThorScreen`        – Protocol for a "page" that owns a ThorVG scene.
/// • `ThorScreenManager` – Manages screens, routes input, drives slide transitions.

import AppKit
import CThorVG
import QuartzCore

// MARK: - ThorButton

/// A rectangular button rendered with ThorVG shapes.
/// Shapes are drawn at the origin and positioned via transforms so the
/// screen manager can slide them during transitions.
public final class ThorButton {

    /// Base position in canvas-pixel space (before any transition offset).
    public let baseX: Float
    public let baseY: Float
    public let width: Float
    public let height: Float
    public let label: String

    /// Called when the button is tapped.
    public var onTap: (() -> Void)?

    // ThorVG paints — created in `addToCanvas`.
    private var bgPaint: Tvg_Paint?
    private var accentPaint: Tvg_Paint?

    private let colorR: UInt8, colorG: UInt8, colorB: UInt8

    public init(x: Float, y: Float, width: Float, height: Float,
                label: String = "",
                r: UInt8 = 70, g: UInt8 = 130, b: UInt8 = 255,
                onTap: (() -> Void)? = nil) {
        self.baseX = x; self.baseY = y
        self.width = width; self.height = height
        self.label = label
        self.colorR = r; self.colorG = g; self.colorB = b
        self.onTap = onTap
    }

    /// Add the button's shapes to `canvas`.  Call once during scene setup.
    public func addToCanvas(_ canvas: Tvg_Canvas) {
        let cornerR = min(width, height) * 0.22

        // Rounded-rect background (drawn at origin, positioned by transform)
        if let bg = tvg_shape_new() {
            tvg_shape_append_rect(bg, 0, 0, width, height, cornerR, cornerR, true)
            tvg_shape_set_fill_color(bg, colorR, colorG, colorB, 220)
            tvg_shape_set_stroke_width(bg, 2)
            tvg_shape_set_stroke_color(bg, 255, 255, 255, 90)
            tvg_canvas_add(canvas, bg)
            bgPaint = bg
        }

        // Inner accent highlight
        if let ac = tvg_shape_new() {
            let m: Float = 5
            tvg_shape_append_rect(ac, m, m, width - m * 2, height - m * 2,
                                  cornerR * 0.6, cornerR * 0.6, true)
            tvg_shape_set_fill_color(ac, 255, 255, 255, 35)
            tvg_canvas_add(canvas, ac)
            accentPaint = ac
        }

        // Place at base position
        applyTransform(offsetX: 0, opacity: 255)
    }

    /// Hit-test in canvas-pixel space.  Only valid when transition offset is 0
    /// (the manager blocks clicks during transitions).
    public func hitTest(px: Float, py: Float) -> Bool {
        px >= baseX && px <= baseX + width &&
        py >= baseY && py <= baseY + height
    }

    /// Move to `(baseX + offsetX, baseY)` and set opacity.
    func applyTransform(offsetX: Float, opacity: UInt8) {
        let tx = baseX + offsetX, ty = baseY
        for paint in [bgPaint, accentPaint] {
            guard let p = paint else { continue }
            var m = Tvg_Matrix(e11: 1, e12: 0, e13: tx,
                               e21: 0, e22: 1, e23: ty,
                               e31: 0, e32: 0, e33: 1)
            tvg_paint_set_transform(p, &m)
            tvg_paint_set_opacity(p, opacity)
        }
    }
}

// MARK: - ThorScreen (protocol)

/// A single "page" that owns ThorVG paints and can animate them.
///
/// **Contract with ThorScreenManager:**
/// - The manager sets `transitionX` and `transitionAlpha` *before* each
///   `update()` call.
/// - Implementations must add `transitionX` to every paint transform's
///   `e13` (translation-x) so the slide works.
/// - When `transitionAlpha == 0`, implementations must set all paint
///   opacities to 0 (hiding the screen) and may skip animation work.
public protocol ThorScreen: AnyObject {
    var name: String { get }
    var buttons: [ThorButton] { get }

    /// Horizontal pixel offset set by the manager during slide transitions.
    var transitionX: Float { get set }

    /// Visibility factor: 0 = fully hidden, 1 = fully visible.
    var transitionAlpha: Float { get set }

    /// Add all shapes to the canvas.  Called once.
    func buildScene(canvas: Tvg_Canvas, width: Float, height: Float)

    /// Per-frame update.  Must incorporate `transitionX` / `transitionAlpha`.
    func update(t: Float, width: Float, height: Float)
}

// MARK: - ThorScreenManager

/// Manages an ordered list of `ThorScreen`s, drives a horizontal-slide
/// transition, and routes mouse clicks to the current screen's buttons.
public final class ThorScreenManager {

    public private(set) var screens: [ThorScreen] = []
    public private(set) var currentIndex: Int = 0
    public var current: ThorScreen? { screens.isEmpty ? nil : screens[currentIndex] }

    /// The most recent `t` passed to `update()` — used by `next()`/`prev()`.
    private var currentT: Float = 0

    // Transition state
    private var transitioning = false
    private var transStart: Float = 0
    private let transDuration: Float = 0.50     // seconds
    private var transFrom: Int = 0
    private var transTo: Int = 0
    private var cW: Float = 0                   // canvas width in pixels

    public init() {}

    public func add(_ screen: ThorScreen) { screens.append(screen) }

    /// Build every screen into `canvas`.  Only screen 0 is visible.
    public func buildAll(canvas: Tvg_Canvas, width: Float, height: Float) {
        cW = width
        for (i, screen) in screens.enumerated() {
            screen.transitionX = 0
            screen.transitionAlpha = (i == 0) ? 1.0 : 0.0
            screen.buildScene(canvas: canvas, width: width, height: height)
            for btn in screen.buttons { btn.addToCanvas(canvas) }
        }
        // First frame: position everything correctly
        for (i, screen) in screens.enumerated() {
            screen.update(t: 0, width: width, height: height)
            let opaque: UInt8 = (i == 0) ? 255 : 0
            for btn in screen.buttons { btn.applyTransform(offsetX: 0, opacity: opaque) }
        }
    }

    /// Call every frame.
    public func update(t: Float, width: Float, height: Float) {
        currentT = t

        if transitioning {
            let elapsed = t - transStart
            var p = min(max(elapsed / transDuration, 0), 1.0)
            // ease-in-out cubic
            p = p < 0.5
                ? 4 * p * p * p
                : 1.0 - pow(-2.0 * p + 2.0, 3.0) / 2.0

            let dir: Float = (transTo > transFrom) ? -1 : 1

            let fromS = screens[transFrom]
            let toS   = screens[transTo]

            // ── Outgoing screen slides away ──
            fromS.transitionAlpha = 1.0
            fromS.transitionX = dir * p * cW
            fromS.update(t: t, width: width, height: height)
            for btn in fromS.buttons {
                btn.applyTransform(offsetX: fromS.transitionX, opacity: 255)
            }

            // ── Incoming screen slides in ──
            toS.transitionAlpha = 1.0
            toS.transitionX = -dir * (1.0 - p) * cW
            toS.update(t: t, width: width, height: height)
            for btn in toS.buttons {
                btn.applyTransform(offsetX: toS.transitionX, opacity: 255)
            }

            // ── Transition complete? ──
            if elapsed >= transDuration {
                fromS.transitionAlpha = 0
                fromS.transitionX = 0
                fromS.update(t: t, width: width, height: height)
                for btn in fromS.buttons { btn.applyTransform(offsetX: 0, opacity: 0) }

                toS.transitionAlpha = 1.0
                toS.transitionX = 0
                currentIndex = transTo
                transitioning = false
            }
        } else if let cur = current {
            cur.transitionX = 0
            cur.transitionAlpha = 1.0
            cur.update(t: t, width: width, height: height)
            for btn in cur.buttons {
                btn.applyTransform(offsetX: 0, opacity: 255)
            }
        }
    }

    /// Switch to screen at `index` with a slide transition.
    public func goTo(index: Int) {
        guard index >= 0, index < screens.count,
              index != currentIndex, !transitioning else { return }
        transFrom = currentIndex
        transTo = index
        transStart = currentT
        transitioning = true
    }

    /// Slide to the next screen (wraps).
    public func next() {
        goTo(index: (currentIndex + 1) % screens.count)
    }

    /// Slide to the previous screen (wraps).
    public func prev() {
        goTo(index: (currentIndex - 1 + screens.count) % screens.count)
    }

    /// Route a click to the current screen's buttons.
    /// Returns `true` if a button was hit.
    @discardableResult
    public func handleClick(px: Float, py: Float) -> Bool {
        guard !transitioning, let cur = current else { return false }
        for btn in cur.buttons where btn.hitTest(px: px, py: py) {
            btn.onTap?()
            return true
        }
        return false
    }
}
