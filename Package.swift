// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftyThor",
    platforms: [
        .macOS(.v12),
        .iOS(.v14),
    ],
    products: [
        .library(name: "SwiftyThor", targets: ["SwiftyThor"]),
        .library(name: "SwiftyThorDynamic", type: .dynamic, targets: ["SwiftyThor"]),
        .library(name: "CSwiftyThorEntry", targets: ["CSwiftyThorEntry"]),
        .executable(name: "SwiftyThorDemo", targets: ["SwiftyThorDemo"]),
    ],
    targets: [
        // ── Pre-built xcframeworks ──────────────────────────────
        .binaryTarget(
            name: "ThorVG",
            path: "output/ThorVG.xcframework"
        ),
        .binaryTarget(
            name: "libEGL",
            path: "output/libEGL.xcframework"
        ),
        .binaryTarget(
            name: "libGLESv2",
            path: "output/libGLESv2.xcframework"
        ),

        // ── C bridge: thorvg_capi.h + EGL headers ─────────────
        .target(
            name: "CThorVG",
            dependencies: ["ThorVG", "libEGL", "libGLESv2"],
            path: "Sources/CThorVG",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedFramework("QuartzCore"),
            ]
        ),

        // ── C entry-point header (shared with Cython / FFI) ───
        .target(
            name: "CSwiftyThorEntry",
            path: "Sources/CSwiftyThorEntry",
            publicHeadersPath: "include"
        ),

        // ── C header for kivy_thor_provider (Kivy window bridge) ──
        .target(
            name: "CKivyThorProvider",
            dependencies: ["CThorVG"],
            path: "Sources/CKivyThorProvider",
            publicHeadersPath: "include"
        ),

        // ── Swift wrapper (includes @_cdecl implementations) ──
        .target(
            name: "SwiftyThor",
            dependencies: ["CThorVG", "CSwiftyThorEntry", "CKivyThorProvider"],
            path: "Sources/SwiftyThor"
        ),

        // ── Demo app ──────────────────────────────────────────
        .executableTarget(
            name: "SwiftyThorDemo",
            dependencies: ["SwiftyThor"],
            path: "Sources/SwiftyThorDemo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
