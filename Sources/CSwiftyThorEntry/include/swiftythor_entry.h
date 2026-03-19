/// swiftythor_entry.h — Pure C ABI entry points for SwiftyThor.
/// Shared between Swift (@_cdecl), Cython, and any FFI consumer.
/// No Objective-C, no @objc — works on macOS, Linux, Windows, Android.

#ifndef SWIFTYTHOR_ENTRY_H
#define SWIFTYTHOR_ENTRY_H

#ifdef __cplusplus
extern "C" {
#endif

/// Launch the SwiftyThor demo app (blocks until window closes).
/// On macOS this starts an NSApplication run loop with an ANGLE-backed
/// ThorVG GlCanvas window.
void swiftythor_run_app(void);

/// Launch with explicit window size.
void swiftythor_run_app_sized(int width, int height);

#ifdef __cplusplus
}
#endif

#endif /* SWIFTYTHOR_ENTRY_H */
