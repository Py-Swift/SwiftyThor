#!/usr/bin/env python3
"""
Build ThorVG xcframeworks for Swift Package consumption.

Produces:
    output/ThorVG.xcframework     — thorvg (GL via ANGLE + OpenMP)
    output/libEGL.xcframework     — ANGLE EGL   (iOS)
    output/libGLESv2.xcframework  — ANGLE GLESv2 (iOS)
    output/libomp.xcframework     — libomp shared dylib (iOS)
    output/macos/                 — macOS fat dylibs (thorvg + ANGLE + libomp)

Reuses the cross-compile infrastructure from thorvg-cython's
build_thorvg.py (cross files, libomp, ANGLE download, patches).

Usage:
    python build_thorvg.py              # macOS + iOS
    python build_thorvg.py macos        # macOS only
    python build_thorvg.py ios          # iOS only
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

# ---------------------------------------------------------------------------
#  Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE  = SCRIPT_DIR.parent                         # thorvg-development/
THORVG_SRC = WORKSPACE / "thorvg"                      # thorvg C++ source
TOOLS_DIR  = WORKSPACE / "thorvg-cython" / "tools"     # reuse cross files etc.
CROSS_DIR  = TOOLS_DIR / "cross"

BUILD_ROOT = SCRIPT_DIR / "build"
OUTPUT_DIR = SCRIPT_DIR / "output"
PATCHES_DIR = SCRIPT_DIR / "patches"

GPU = "angle"   # always — this is the Swift/Apple build

# ANGLE pre-built binaries (from kivy/angle-builder)
ANGLE_DIR  = BUILD_ROOT / "angle"

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
def _run(cmd: list[str] | str, *, cwd: Path | None = None,
         env: dict | None = None, capture: bool = False) -> subprocess.CompletedProcess:
    if isinstance(cmd, list):
        print(f"  $ {' '.join(str(c) for c in cmd)}")
    else:
        print(f"  $ {cmd}")
    return subprocess.run(cmd, cwd=cwd, env=env, check=True,
                          capture_output=capture, text=True)


def _ensure_tool(name: str) -> None:
    if shutil.which(name):
        return
    if name in ("meson", "ninja"):
        print(f"[build] Installing {name} via pip ...")
        _run([sys.executable, "-m", "pip", "install", name])
    else:
        sys.exit(f"ERROR: '{name}' not found on PATH")


def _xcode_dev() -> str:
    try:
        r = _run(["xcode-select", "-p"], capture=True)
        return r.stdout.strip()
    except Exception:
        return "/Applications/Xcode.app/Contents/Developer"


def _apple_sdk(platform_name: str) -> str:
    dev = _xcode_dev()
    return f"{dev}/Platforms/{platform_name}.platform/Developer/SDKs/{platform_name}.sdk"


# ---------------------------------------------------------------------------
#  Meson arguments
# ---------------------------------------------------------------------------
def _meson_common() -> list[str]:
    return [
        "--buildtype=release",
        "--default-library=shared",
        "-Dthreads=true",
        "-Dbindings=capi",
        "-Dloaders=svg,lottie,ttf",
        "-Dengines=sw,gl",
        f"-Dextra=lottie_exp,openmp,opengl_es",
    ]


# ---------------------------------------------------------------------------
#  Cross-file OpenMP injection  (ported from thorvg-cython)
# ---------------------------------------------------------------------------
def _inject_cross_list(content: str, key: str, values: list[str]) -> str:
    import re
    escaped = [f"'{v}'" for v in values]
    pattern = re.compile(
        rf"^(\s*{re.escape(key)}\s*=\s*\[)(.*?)(]\s*)$",
        re.MULTILINE,
    )
    match = pattern.search(content)
    if match:
        existing = match.group(2).strip()
        addition = (", " if existing else "") + ", ".join(escaped)
        content = content[:match.end(2)] + addition + content[match.start(3):]
    else:
        print(f"  [openmp] Warning: could not find '{key}' in cross file")
    return content


def _inject_openmp_cross_file(template: Path, output: Path,
                               libomp: Path, omp_h_dir: Path,
                               *, framework_dir: Path | None = None) -> Path:
    content = template.read_text()
    content = _inject_cross_list(content, "cpp_args",
                                 ["-Xclang", "-fopenmp", f"-I{omp_h_dir}"])
    if framework_dir:
        content = _inject_cross_list(
            content, "cpp_link_args",
            [f"-F{framework_dir}", "-framework", "libomp"],
        )
    else:
        content = _inject_cross_list(content, "cpp_link_args", [str(libomp)])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content)
    print(f"  [openmp] Injected flags → {output}")
    return output


# ---------------------------------------------------------------------------
#  libomp  (delegates to thorvg-cython's build_thorvg.py helpers)
# ---------------------------------------------------------------------------
def _prepare_libomp(targets: list[dict], *, shared: bool = False
                    ) -> dict[str, tuple[Path, Path]]:
    """Calls the thorvg-cython build_thorvg module to build libomp."""
    sys.path.insert(0, str(TOOLS_DIR))
    from build_thorvg import _prepare_libomp_apple  # type: ignore
    return _prepare_libomp_apple(THORVG_SRC, targets, shared=shared)


# ---------------------------------------------------------------------------
#  ANGLE download + tvgGl patch
# ---------------------------------------------------------------------------
def _download_angle_libs() -> None:
    """Download pre-built ANGLE for macOS + iOS via thorvg-cython helper."""
    sys.path.insert(0, str(TOOLS_DIR))
    from build_thorvg import download_angle  # type: ignore

    # macOS universal (arm64 + x86_64 fat dylibs)
    macos_angle = ANGLE_DIR / "macos"
    if not (macos_angle / "angle" / "libEGL.dylib").exists():
        print(">>> Downloading ANGLE for macOS...")
        download_angle("macos-universal", macos_angle)
    else:
        print("[angle] macOS ANGLE already present — skipping")

    # iOS (xcframeworks: device + simulator)
    ios_angle = ANGLE_DIR / "ios"
    if not (ios_angle / "angle").exists():
        print(">>> Downloading ANGLE for iOS...")
        download_angle("ios", ios_angle)
    else:
        print("[angle] iOS ANGLE already present — skipping")


def _apply_angle_patch() -> None:
    """Apply the tvgGl ANGLE patch so ThorVG can dlopen ANGLE on Apple."""
    patch_file = PATCHES_DIR / "tvgGl_angle_apple.patch"
    sentinel = THORVG_SRC / ".patched_tvgGl_angle_apple"

    if not patch_file.exists():
        print(f"[patch] WARNING: {patch_file} not found — skipping")
        return
    if sentinel.exists():
        print("[patch] tvgGl ANGLE patch already applied — skipping")
        return

    print(">>> Applying tvgGl ANGLE patch...")
    _run(["patch", "-p1", "--forward", "-i", str(patch_file)], cwd=THORVG_SRC)
    sentinel.write_text("Applied by SwiftyThor/build_thorvg.py\n")
    print("<<< Patch applied\n")


# ---------------------------------------------------------------------------
#  Framework bundling
# ---------------------------------------------------------------------------
def _make_framework(dylib: Path, name: str, headers_dir: Path,
                    dest: Path, *, min_os: str = "13.0",
                    sibling_dylibs: list[tuple[str, str]] | None = None) -> Path:
    """Wrap a dylib + headers in a .framework bundle."""
    fw = dest / f"{name}.framework"
    if fw.exists():
        shutil.rmtree(fw)
    fw.mkdir(parents=True)
    (fw / "Headers").mkdir()

    # Copy binary
    shutil.copy2(str(dylib), str(fw / name))
    _run(["install_name_tool", "-id",
          f"@rpath/{name}.framework/{name}", str(fw / name)])
    # Add @loader_path so dlopen of sibling dylibs resolves
    _run(["install_name_tool", "-add_rpath", "@loader_path/", str(fw / name)])

    # Symlinks for runtime dlopen resolution
    if sibling_dylibs:
        for bare_name, rel_target in sibling_dylibs:
            link = fw / bare_name
            link.symlink_to(rel_target)
            print(f"    Symlink: {bare_name} → {rel_target}")

    # Copy headers
    for h in headers_dir.iterdir():
        if h.suffix in (".h", ".hpp"):
            shutil.copy2(str(h), str(fw / "Headers" / h.name))

    # Info.plist
    (fw / "Info.plist").write_text(textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>{name}</string>
            <key>CFBundleIdentifier</key>
            <string>org.thorvg.{name}</string>
            <key>CFBundleName</key>
            <string>{name}</string>
            <key>CFBundlePackageType</key>
            <string>FMWK</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>MinimumOSVersion</key>
            <string>{min_os}</string>
        </dict>
        </plist>
    """))
    print(f"  Created: {fw}")
    return fw


def _make_angle_framework(dylib: Path, name: str, dest: Path,
                          *, min_os: str = "11.0",
                          sibling_dylibs: list[tuple[str, str]] | None = None) -> Path:
    """Wrap an ANGLE dylib in a minimal .framework bundle (no headers).

    sibling_dylibs: list of (bare_name, framework_binary) for symlinks so
        dlopen("bare_name") resolves via @loader_path.
        e.g. [("libGLESv2.dylib", "../libGLESv2.framework/libGLESv2")]
    """
    fw = dest / f"{name}.framework"
    if fw.exists():
        shutil.rmtree(fw)
    fw.mkdir(parents=True)
    shutil.copy2(str(dylib), str(fw / name))
    _run(["install_name_tool", "-id",
          f"@rpath/{name}.framework/{name}", str(fw / name)])

    # Replace @executable_path with @loader_path so dlopen can find siblings
    # (ANGLE ships with @executable_path/ — no header room to add a new rpath)
    _run(["install_name_tool", "-rpath", "@executable_path/", "@loader_path/",
          str(fw / name)])

    # Symlinks so bare-name dlopen finds sibling framework binaries
    if sibling_dylibs:
        for bare_name, rel_target in sibling_dylibs:
            link = fw / bare_name
            link.symlink_to(rel_target)
            print(f"    Symlink: {bare_name} → {rel_target}")

    (fw / "Info.plist").write_text(textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>{name}</string>
            <key>CFBundleIdentifier</key>
            <string>com.angle.{name}</string>
            <key>CFBundleName</key>
            <string>{name}</string>
            <key>CFBundlePackageType</key>
            <string>FMWK</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>MinimumOSVersion</key>
            <string>{min_os}</string>
        </dict>
        </plist>
    """))
    print(f"  Created: {fw}")
    return fw


def _make_libomp_framework(dylib: Path, omp_h: Path, dest: Path) -> Path:
    """Wrap libomp dylib in a .framework."""
    fw = dest / "libomp.framework"
    if fw.exists():
        shutil.rmtree(fw)
    fw.mkdir(parents=True)
    (fw / "Headers").mkdir()
    shutil.copy2(str(dylib), str(fw / "libomp"))
    _run(["install_name_tool", "-id",
          "@rpath/libomp.framework/libomp", str(fw / "libomp")])
    shutil.copy2(str(omp_h), str(fw / "Headers" / "omp.h"))
    (fw / "Info.plist").write_text(textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>libomp</string>
            <key>CFBundleIdentifier</key>
            <string>org.llvm.libomp</string>
            <key>CFBundleName</key>
            <string>libomp</string>
            <key>CFBundlePackageType</key>
            <string>FMWK</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>MinimumOSVersion</key>
            <string>13.0</string>
        </dict>
        </plist>
    """))
    print(f"  Created: {fw}")
    return fw


# ---------------------------------------------------------------------------
#  Build: single arch
# ---------------------------------------------------------------------------
def _build_arch(name: str, cross_file: Path) -> Path:
    """Meson setup + ninja for one (arch, sdk) pair.

    Returns the build directory path.
    """
    bd = BUILD_ROOT / name
    if bd.exists():
        shutil.rmtree(bd)
    print(f">>> Building: {name}")
    _run(["meson", "setup", str(bd),
          "--cross-file", str(cross_file)] + _meson_common(),
         cwd=THORVG_SRC)
    _run(["ninja", "-C", str(bd)], cwd=THORVG_SRC)
    print(f"<<< Done: {name}\n")
    return bd


def _dylib_from_build(bd: Path) -> Path:
    """Find the libthorvg dylib in a meson build dir."""
    p = bd / "src" / "libthorvg-1.dylib"
    if p.exists():
        return p
    # fallback: glob
    candidates = list((bd / "src").glob("libthorvg*.dylib"))
    if candidates:
        return candidates[0]
    sys.exit(f"ERROR: no libthorvg dylib found in {bd / 'src'}")


# ---------------------------------------------------------------------------
#  Build: macOS  (arm64 + x86_64 → fat)
# ---------------------------------------------------------------------------
def build_macos() -> Path | None:
    """Build for macOS, return fat dylib path (or None on skip)."""
    _ensure_tool("meson")
    _ensure_tool("ninja")

    print("═══ macOS ═══")
    macos_sdk = _apple_sdk("MacOSX")

    # libomp (static for macOS)
    omp_targets = [
        dict(name="macos_arm64",  system_name="Darwin", sysroot=macos_sdk,
             arch_cmake="arm64",  arch_omp="aarch64",
             deployment_target="11.0", deployment_flag="-mmacosx-version-min=11.0"),
        dict(name="macos_x86_64", system_name="Darwin", sysroot=macos_sdk,
             arch_cmake="x86_64", arch_omp="x86_64",
             deployment_target="11.0", deployment_flag="-mmacosx-version-min=11.0"),
    ]
    omp = _prepare_libomp(omp_targets)

    # Cross files with OpenMP
    gen_cross = BUILD_ROOT / "cross"
    gen_cross.mkdir(parents=True, exist_ok=True)

    cross_files = {}
    for name, tmpl in [("macos_arm64",  "macos_arm64.txt"),
                       ("macos_x86_64", "macos_x86_64.txt")]:
        libomp, omp_h = omp[name]
        cross_files[name] = _inject_openmp_cross_file(
            CROSS_DIR / tmpl, gen_cross / tmpl,
            libomp, omp_h.parent,
        )

    # Build both archs
    bd_arm = _build_arch("macos_arm64",  cross_files["macos_arm64"])
    bd_x86 = _build_arch("macos_x86_64", cross_files["macos_x86_64"])

    # Lipo → fat
    fat_dir = BUILD_ROOT / "macos_fat"
    fat_dir.mkdir(parents=True, exist_ok=True)
    fat_dylib = fat_dir / "libthorvg-1.dylib"

    print(">>> Lipo: macOS fat dylib")
    _run(["lipo", "-create",
          str(_dylib_from_build(bd_arm)),
          str(_dylib_from_build(bd_x86)),
          "-output", str(fat_dylib)])
    _run(["install_name_tool", "-id",
          "@rpath/libthorvg-1.dylib", str(fat_dylib)])
    print(f"<<< {fat_dylib}\n")

    # Copy ANGLE dylibs into the fat dir (they'll go into output later)
    angle_macos = ANGLE_DIR / "macos" / "angle"
    for lib_name in ("libEGL.dylib", "libGLESv2.dylib"):
        src = angle_macos / lib_name
        if src.exists():
            shutil.copy2(str(src), str(fat_dir / lib_name))
            print(f"  Copied ANGLE: {lib_name}")
        else:
            print(f"  WARNING: {src} not found")

    return fat_dylib


# ---------------------------------------------------------------------------
#  Build: iOS  (device arm64 + sim arm64/x86_64)
# ---------------------------------------------------------------------------
def build_ios() -> tuple[Path | None, Path | None, dict]:
    """Build for iOS, return (device_dylib, sim_fat_dylib, omp_fw_dirs)."""
    _ensure_tool("meson")
    _ensure_tool("ninja")

    print("═══ iOS ═══")
    ios_sdk = _apple_sdk("iPhoneOS")
    sim_sdk = _apple_sdk("iPhoneSimulator")

    # libomp (shared for iOS — framework embedding)
    omp_targets = [
        dict(name="ios_arm64",     system_name="iOS", sysroot=ios_sdk,
             arch_cmake="arm64",  arch_omp="aarch64",
             deployment_target="13.0", deployment_flag="-miphoneos-version-min=13.0"),
        dict(name="ios_sim_arm64", system_name="iOS", sysroot=sim_sdk,
             arch_cmake="arm64",  arch_omp="aarch64",
             deployment_target="13.0", deployment_flag="-mios-simulator-version-min=13.0",
             tag="ios-sim-arm64",
             target_triple="arm64-apple-ios13.0-simulator"),
        dict(name="ios_sim_x86_64", system_name="iOS", sysroot=sim_sdk,
             arch_cmake="x86_64", arch_omp="x86_64",
             deployment_target="13.0", deployment_flag="-mios-simulator-version-min=13.0",
             tag="ios-sim-x86_64",
             target_triple="x86_64-apple-ios13.0-simulator"),
    ]
    omp = _prepare_libomp(omp_targets, shared=True)

    # libomp .framework bundles
    print(">>> libomp .framework bundles")
    omp_fw_staging = BUILD_ROOT / "libomp_frameworks"
    omp_fw_dirs: dict[str, Path] = {}
    for name in ("ios_arm64", "ios_sim_arm64", "ios_sim_x86_64"):
        dylib, omp_h = omp[name]
        omp_fw_dirs[name] = _make_libomp_framework(
            dylib, omp_h, omp_fw_staging / name)
    print()

    # Cross files with OpenMP framework flags
    gen_cross = BUILD_ROOT / "cross"
    gen_cross.mkdir(parents=True, exist_ok=True)

    cross_files = {}
    for name, tmpl in [("ios_arm64",      "ios_arm64.txt"),
                       ("ios_sim_arm64",  "ios_simulator_arm64.txt"),
                       ("ios_sim_x86_64", "ios_simulator_x86_64.txt")]:
        libomp, omp_h = omp[name]
        cross_files[name] = _inject_openmp_cross_file(
            CROSS_DIR / tmpl, gen_cross / tmpl,
            libomp, omp_h.parent,
            framework_dir=omp_fw_dirs[name].parent,
        )

    # Build all three
    bd_dev = _build_arch("ios_arm64",      cross_files["ios_arm64"])
    bd_sim_a = _build_arch("ios_sim_arm64",  cross_files["ios_sim_arm64"])
    bd_sim_x = _build_arch("ios_sim_x86_64", cross_files["ios_sim_x86_64"])

    dev_dylib = _dylib_from_build(bd_dev)

    # Simulator fat
    sim_fat_dir = BUILD_ROOT / "ios_sim_fat"
    sim_fat_dir.mkdir(parents=True, exist_ok=True)
    sim_fat_dylib = sim_fat_dir / "libthorvg-1.dylib"

    print(">>> Lipo: iOS simulator fat dylib")
    _run(["lipo", "-create",
          str(_dylib_from_build(bd_sim_a)),
          str(_dylib_from_build(bd_sim_x)),
          "-output", str(sim_fat_dylib)])
    print()

    return dev_dylib, sim_fat_dylib, omp_fw_dirs


# ---------------------------------------------------------------------------
#  XCFramework assembly
# ---------------------------------------------------------------------------
def create_xcframeworks(*, macos_dylib: Path | None = None,
                        ios_dev_dylib: Path | None = None,
                        ios_sim_dylib: Path | None = None,
                        omp_fw_dirs: dict[str, Path] | None = None) -> None:
    """Assemble xcframeworks and copy macOS dylibs."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    headers_dir = THORVG_SRC / "inc"

    # ── ThorVG.xcframework ──────────────────────────────────────
    print(">>> Creating ThorVG.xcframework")
    xcf = OUTPUT_DIR / "ThorVG.xcframework"
    if xcf.exists():
        shutil.rmtree(xcf)

    args: list[str] = ["xcodebuild", "-create-xcframework"]

    # ThorVG dlopen's libGLESv2.dylib and libEGL.dylib at runtime
    thorvg_siblings = [
        ("libGLESv2.dylib", "../libGLESv2.framework/libGLESv2"),
        ("libEGL.dylib", "../libEGL.framework/libEGL"),
    ]

    if macos_dylib:
        fw_dir = BUILD_ROOT / "fw_macos"
        _make_framework(macos_dylib, "ThorVG", headers_dir, fw_dir,
                        min_os="11.0", sibling_dylibs=thorvg_siblings)
        args += ["-framework", str(fw_dir / "ThorVG.framework")]

    if ios_dev_dylib:
        fw_dir = BUILD_ROOT / "fw_ios_dev"
        _make_framework(ios_dev_dylib, "ThorVG", headers_dir, fw_dir,
                        min_os="13.0", sibling_dylibs=thorvg_siblings)
        args += ["-framework", str(fw_dir / "ThorVG.framework")]

    if ios_sim_dylib:
        fw_dir = BUILD_ROOT / "fw_ios_sim"
        _make_framework(ios_sim_dylib, "ThorVG", headers_dir, fw_dir,
                        min_os="13.0", sibling_dylibs=thorvg_siblings)
        args += ["-framework", str(fw_dir / "ThorVG.framework")]

    args += ["-output", str(xcf)]
    _run(args)
    print(f"<<< {xcf}\n")

    # ── macOS: plain dylibs with @rpath install names ─────────
    #    No framework wrapping — just raw .dylib files for wheels.
    if macos_dylib:
        macos_out = OUTPUT_DIR / "macos"
        macos_out.mkdir(parents=True, exist_ok=True)
        fat_dir = macos_dylib.parent
        for f in fat_dir.glob("*.dylib"):
            dest = macos_out / f.name
            shutil.copy2(str(f), str(dest))
            # Set install name to @rpath/<name>.dylib
            _run(["install_name_tool", "-id",
                  f"@rpath/{f.name}", str(dest)])
            # Ensure the only rpath is @loader_path.
            # First try replacing @executable_path/ (ANGLE ships with it):
            try:
                _run(["install_name_tool", "-rpath",
                      "@executable_path/", "@loader_path",
                      str(dest)])
            except subprocess.CalledProcessError:
                # No @executable_path/ rpath — try adding @loader_path
                try:
                    _run(["install_name_tool", "-add_rpath",
                          "@loader_path", str(dest)])
                except subprocess.CalledProcessError:
                    pass  # @loader_path already present
            print(f"  → {dest}  (install name: @rpath/{f.name})")

    # ── ANGLE xcframeworks (iOS-only) ──────────────────────────
    ios_angle   = ANGLE_DIR / "ios"   / "angle"

    for lib_name in ("libEGL", "libGLESv2"):
        print(f">>> Creating {lib_name}.xcframework (iOS-only)")
        angle_xcf = OUTPUT_DIR / f"{lib_name}.xcframework"
        if angle_xcf.exists():
            shutil.rmtree(angle_xcf)

        angle_args: list[str] = ["xcodebuild", "-create-xcframework"]

        # iOS slices — from pre-built iOS xcframework
        ios_xcfw = ios_angle / f"{lib_name}.xcframework"
        if ios_xcfw.exists():
            for slice_dir in ios_xcfw.iterdir():
                if slice_dir.is_dir() and (slice_dir / f"{lib_name}.framework").exists():
                    angle_args += ["-framework",
                                   str(slice_dir / f"{lib_name}.framework")]

        angle_args += ["-output", str(angle_xcf)]
        _run(angle_args)
        print(f"<<< {angle_xcf}\n")

    # ── libomp.xcframework ──────────────────────────────────────
    if omp_fw_dirs:
        print(">>> Creating libomp.xcframework")
        omp_xcf = OUTPUT_DIR / "libomp.xcframework"
        if omp_xcf.exists():
            shutil.rmtree(omp_xcf)

        omp_args: list[str] = ["xcodebuild", "-create-xcframework"]

        if "ios_arm64" in omp_fw_dirs:
            omp_args += ["-framework", str(omp_fw_dirs["ios_arm64"])]

        # Simulator fat libomp
        if "ios_sim_arm64" in omp_fw_dirs and "ios_sim_x86_64" in omp_fw_dirs:
            sim_fat = BUILD_ROOT / "libomp_sim_fat"
            sim_fat.mkdir(parents=True, exist_ok=True)
            _run(["lipo", "-create",
                  str(omp_fw_dirs["ios_sim_arm64"] / "libomp"),
                  str(omp_fw_dirs["ios_sim_x86_64"] / "libomp"),
                  "-output", str(sim_fat / "libomp")])
            any_omp_h = omp_fw_dirs["ios_sim_arm64"] / "Headers" / "omp.h"
            sim_fat_fw = _make_libomp_framework(
                sim_fat / "libomp", any_omp_h, sim_fat)
            (sim_fat / "libomp").unlink(missing_ok=True)
            omp_args += ["-framework", str(sim_fat_fw)]

        omp_args += ["-output", str(omp_xcf)]
        _run(omp_args)
        print(f"<<< {omp_xcf}\n")


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build ThorVG xcframeworks for Swift Package")
    parser.add_argument("target", nargs="?", default="all",
                        choices=["macos", "ios", "all"],
                        help="Platform to build (default: all)")
    parser.add_argument("--clean", action="store_true",
                        help="Remove build/ before starting")
    args = parser.parse_args()

    print("ThorVG Swift xcframework builder")
    print(f"  ThorVG source:  {THORVG_SRC}")
    print(f"  Cross files:    {CROSS_DIR}")
    print(f"  GPU:            {GPU}")
    print(f"  Target:         {args.target}")
    print()

    if args.clean and BUILD_ROOT.exists():
        print("Cleaning build/...")
        shutil.rmtree(BUILD_ROOT)

    # Download ANGLE + apply patch before any builds
    _download_angle_libs()
    _apply_angle_patch()

    macos_dylib = None
    ios_dev_dylib = None
    ios_sim_dylib = None
    omp_fw_dirs: dict[str, Path] = {}

    if args.target in ("macos", "all"):
        macos_dylib = build_macos()

    if args.target in ("ios", "all"):
        ios_dev_dylib, ios_sim_dylib, omp_fw_dirs = build_ios()

    create_xcframeworks(
        macos_dylib=macos_dylib,
        ios_dev_dylib=ios_dev_dylib,
        ios_sim_dylib=ios_sim_dylib,
        omp_fw_dirs=omp_fw_dirs or None,
    )

    print("═══ Build complete ═══")
    print(f"Output: {OUTPUT_DIR}/")
    for p in sorted(OUTPUT_DIR.rglob("*")):
        if p.is_file() and p.suffix in (".dylib", "", ".h"):
            rel = p.relative_to(OUTPUT_DIR)
            print(f"  {rel}")


if __name__ == "__main__":
    main()
