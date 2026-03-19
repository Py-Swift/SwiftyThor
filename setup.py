"""
Extension config for swiftythor — called by setuptools via pyproject.toml.

Builds the Cython extension and bundles raw macOS dylibs into the wheel so
that delocate is NOT needed.  The extension + all dylibs live in the same
directory; @loader_path rpaths resolve them at runtime.
"""

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from Cython.Build import cythonize
from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext as _build_ext

HERE = Path(__file__).resolve().parent
SWIFTYTHOR_ROOT = HERE                                      # SwiftyThor/
MACOS_DYLIBS = SWIFTYTHOR_ROOT / "output" / "macos"        # raw dylibs from build_thorvg.py

HEADER_DIR = str(SWIFTYTHOR_ROOT / "Sources" / "CSwiftyThorEntry" / "include")


def _macos_sdk_path() -> str | None:
    """Return the macOS SDK path via xcrun, or None."""
    try:
        result = subprocess.run(
            ["xcrun", "--show-sdk-path"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()
    except Exception:
        return None


def _find_spm_build_dir() -> Path:
    """Locate the SPM build products directory, preferring release over debug."""
    arch = platform.machine()                               # x86_64 or arm64
    triple = f"{arch}-apple-macosx"
    spm_build = SWIFTYTHOR_ROOT / ".build"

    # Try release first, then debug, then the legacy flat layout
    for config in ("release", "debug"):
        candidate = spm_build / triple / config
        if (candidate / "libSwiftyThorDynamic.dylib").exists():
            return candidate

    # Flat layout (older SPM or symlinked)
    for config in ("release", "debug"):
        candidate = spm_build / config
        if (candidate / "libSwiftyThorDynamic.dylib").exists():
            return candidate

    # Last resort — return release path and let the caller fail with a
    # clear error message.
    return spm_build / triple / "release"


SPM_BUILD_DIR = _find_spm_build_dir()

# Map of destination name → list of source candidates (tried in order).
# SPM wraps xcframework binaries in .framework dirs without the .dylib extension.
DYLIB_SOURCES: dict[str, list[Path]] = {
    "libSwiftyThorDynamic.dylib": [
        SPM_BUILD_DIR / "libSwiftyThorDynamic.dylib",
    ],
    "libthorvg-1.dylib": [
        MACOS_DYLIBS / "libthorvg-1.dylib",
        SPM_BUILD_DIR / "ThorVG.framework" / "ThorVG",
    ],
    "libEGL.dylib": [
        MACOS_DYLIBS / "libEGL.dylib",
        SPM_BUILD_DIR / "libEGL.framework" / "libEGL",
    ],
    "libGLESv2.dylib": [
        MACOS_DYLIBS / "libGLESv2.dylib",
        SPM_BUILD_DIR / "libGLESv2.framework" / "libGLESv2",
    ],
}

# install_name_tool rewrites for libSwiftyThorDynamic.dylib:
#   SPM links against framework-wrapped paths; we rewrite them to plain dylib names.
INSTALL_NAME_REWRITES = {
    "@rpath/ThorVG.framework/ThorVG": "@rpath/libthorvg-1.dylib",
    "@rpath/libEGL.framework/libEGL": "@rpath/libEGL.dylib",
    "@rpath/libGLESv2.framework/libGLESv2": "@rpath/libGLESv2.dylib",
}


def _run(cmd: list[str]) -> None:
    subprocess.check_call(cmd)


def _resolve_source(name: str) -> Path | None:
    """Return the first existing source path for *name*, or None."""
    for candidate in DYLIB_SOURCES.get(name, []):
        if candidate.exists():
            return candidate
    return None


class build_ext(_build_ext):
    """Custom build_ext that bundles raw macOS dylibs next to the .so."""

    def run(self):
        super().run()
        if sys.platform != "darwin":
            return
        self._bundle_dylibs()

    def _bundle_dylibs(self):
        ext_path = self.get_ext_fullpath("swiftythor")
        ext_dir = Path(ext_path).parent

        # ── Copy all dylibs into ext_dir ───────────────────────
        for dest_name in DYLIB_SOURCES:
            src = _resolve_source(dest_name)
            if src is None:
                print(f"WARNING: {dest_name} not found, skipping")
                continue
            dest = ext_dir / dest_name
            shutil.copy2(str(src), str(dest))
            print(f"  Bundled: {src} → {dest}")

        # ── Fix libSwiftyThorDynamic.dylib install names ───────
        swift_dest = ext_dir / "libSwiftyThorDynamic.dylib"
        if swift_dest.exists():
            for old, new in INSTALL_NAME_REWRITES.items():
                try:
                    _run(["install_name_tool", "-change", old, new,
                          str(swift_dest)])
                    print(f"  Rewrite: {old} → {new}")
                except subprocess.CalledProcessError:
                    pass

            # Ensure @loader_path rpath is present
            try:
                _run(["install_name_tool", "-add_rpath", "@loader_path",
                      str(swift_dest)])
            except subprocess.CalledProcessError:
                pass  # already present

        # ── Fix each raw dylib: id + rpath ─────────────────────
        for name in DYLIB_SOURCES:
            dest = ext_dir / name
            if not dest.exists():
                continue
            _run(["install_name_tool", "-id", f"@rpath/{name}", str(dest)])
            # Replace @executable_path/ → @loader_path if present,
            # otherwise add @loader_path
            try:
                _run(["install_name_tool", "-rpath",
                      "@executable_path/", "@loader_path", str(dest)])
            except subprocess.CalledProcessError:
                try:
                    _run(["install_name_tool", "-add_rpath",
                          "@loader_path", str(dest)])
                except subprocess.CalledProcessError:
                    pass  # already correct

        # ── Fix the .so itself: rpath = @loader_path ──────────
        so_path = ext_dir / Path(ext_path).name
        if so_path.exists():
            try:
                _run(["install_name_tool", "-add_rpath", "@loader_path",
                      str(so_path)])
            except subprocess.CalledProcessError:
                pass


ext = Extension(
    "swiftythor",
    sources=["src/swiftythor/swiftythor.pyx"],
    include_dirs=[HEADER_DIR],
    library_dirs=[str(SPM_BUILD_DIR)],
    libraries=["SwiftyThorDynamic"],
    extra_compile_args=(
        ["-isysroot", sdk] if (sdk := _macos_sdk_path()) else []
    ),
    extra_link_args=[
        "-Wl,-rpath,@loader_path",
        "-framework", "AppKit",
        "-framework", "QuartzCore",
    ] + (["-isysroot", sdk] if sdk else []),
)

setup(
    ext_modules=cythonize([ext], language_level="3"),
    cmdclass={"build_ext": build_ext},
)
