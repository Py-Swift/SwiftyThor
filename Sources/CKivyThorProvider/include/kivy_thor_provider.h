/// kivy_thor_provider.h — Platform-neutral C ABI between Swift and Cython.
///
/// Swift implements every function via @_cdecl.
/// Cython calls / registers callbacks through this header.
/// Plain C types only — zero platform references on the Cython side.
///
/// ARCHITECTURE — pure push model, multi-window capable:
///
///   Swift:
///     - Creates windows & GL contexts (platform-specific, hidden from Cython)
///     - Owns the display-link / frame timer per window
///     - Each frame: calls KtpFrameCallback → Cython draws → Swift presents
///     - On OS events: calls the matching registered callback into Cython
///
///   Cython / Kivy:
///     - Creates/destroys KtpWindow handles
///     - Registers callbacks per window for the events it cares about
///     - On frame callback: ticks Kivy's Clock, draws into the Tvg_Canvas*
///     - On event callbacks: dispatches into Kivy's event system
///
///   No polling.  No flip.  No timer.  No platform awareness on the Cython side.

#ifndef KIVY_THOR_PROVIDER_H
#define KIVY_THOR_PROVIDER_H

#include <stdint.h>
#include <stdbool.h>
#include "thorvg_capi.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a window.  Cython holds this; Swift owns the internals.
/// void* so Swift can use Unmanaged<KtpWindowState> and pass objects directly.
typedef void *KtpWindow;

// ============================================================================
// MARK: - App Init
// ============================================================================

/// Bootstrap the platform application runtime.
/// Call this once from Python/Cython before creating any windows.
///
/// @param embedded
///   false — standalone mode: Python owns the process.  Swift bootstraps
///           NSApplication, fires the AppDelegate, and starts ThorVG.
///   true  — embedded mode: NSApplication is already running (launched from
///           Xcode / a host app).  Swift skips NSApplication init and only
///           wires the AppDelegate + starts ThorVG if not already done.
void ktp_app_init(bool embedded);

// ============================================================================
// MARK: - Engine Lifecycle
// ============================================================================

/// Start the ThorVG engine with the given number of worker threads.
/// Safe to call more than once — subsequent calls are no-ops if already running.
/// Must be called before creating any windows or using the canvas.
/// @param threads  Worker thread count (0 = auto / use a sensible default).
void ktp_engine_start(uint32_t threads);

/// Stop the ThorVG engine and release its resources.
/// Call on app shutdown.  Safe to call even if the engine was never started.
void ktp_engine_stop(void);

// ============================================================================
// MARK: - Window Lifecycle
// ============================================================================

/// Create a new window.  Returns NULL on failure.
/// `state`: 0 = normal, 1 = maximized, 2 = minimized, 3 = hidden
KtpWindow ktp_window_create(int x, int y,
                            int width, int height,
                            bool borderless,
                            bool fullscreen,
                            bool resizable,
                            int  state,
                            int *out_width, int *out_height);

/// Destroy a window and free all resources.
void ktp_window_destroy(KtpWindow win);

/// Resize the window.
void ktp_window_resize(KtpWindow win, int width, int height);

// ============================================================================
// MARK: - Frame Callback  (Swift → Cython, per window)
// ============================================================================

typedef void (*KtpFrameCb)(double dt, void *ud);

void ktp_window_set_frame_cb(KtpWindow win, KtpFrameCb cb, void *ud);

// ============================================================================
// MARK: - Event Callbacks  (Swift → Cython, pushed from OS events)
// ============================================================================
//
// All coordinates are in window points (not pixels).
// NULL callback = ignore that event.

// --- Mouse ---

typedef void (*KtpMouseMotionCb)(float x, float y, void *ud);
typedef void (*KtpMouseButtonCb)(float x, float y, int button, void *ud);
typedef void (*KtpMouseWheelCb)(float dx, float dy, void *ud);

void ktp_window_set_mouse_motion_cb(KtpWindow win, KtpMouseMotionCb cb, void *ud);
void ktp_window_set_mouse_button_down_cb(KtpWindow win, KtpMouseButtonCb cb, void *ud);
void ktp_window_set_mouse_button_up_cb(KtpWindow win, KtpMouseButtonCb cb, void *ud);
void ktp_window_set_mouse_wheel_cb(KtpWindow win, KtpMouseWheelCb cb, void *ud);

// --- Touch (mobile) ---

typedef void (*KtpTouchCb)(int64_t finger_id,
                           float x, float y, float pressure,
                           void *ud);

void ktp_window_set_touch_down_cb(KtpWindow win, KtpTouchCb cb, void *ud);
void ktp_window_set_touch_moved_cb(KtpWindow win, KtpTouchCb cb, void *ud);
void ktp_window_set_touch_up_cb(KtpWindow win, KtpTouchCb cb, void *ud);

// --- Keyboard ---

typedef void (*KtpKeyCb)(int mod, int key, int scancode,
                         const char *text, void *ud);
typedef void (*KtpTextCb)(const char *text, void *ud);

void ktp_window_set_key_down_cb(KtpWindow win, KtpKeyCb cb, void *ud);
void ktp_window_set_key_up_cb(KtpWindow win, KtpKeyCb cb, void *ud);
void ktp_window_set_text_input_cb(KtpWindow win, KtpTextCb cb, void *ud);
void ktp_window_set_text_edit_cb(KtpWindow win, KtpTextCb cb, void *ud);

// --- Window state ---

typedef void (*KtpSizeCb)(int w, int h, void *ud);
typedef void (*KtpPosCb)(int x, int y, void *ud);
typedef void (*KtpVoidCb)(void *ud);

void ktp_window_set_resized_cb(KtpWindow win, KtpSizeCb cb, void *ud);
void ktp_window_set_moved_cb(KtpWindow win, KtpPosCb cb, void *ud);
void ktp_window_set_close_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_focus_gained_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_focus_lost_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_minimized_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_maximized_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_restored_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_shown_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_hidden_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_exposed_cb(KtpWindow win, KtpVoidCb cb, void *ud);

// --- Cursor enter / leave ---

void ktp_window_set_cursor_enter_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_cursor_leave_cb(KtpWindow win, KtpVoidCb cb, void *ud);

// --- Drag & drop ---

typedef void (*KtpDropCb)(const char *payload, void *ud);

void ktp_window_set_drop_file_cb(KtpWindow win, KtpDropCb cb, void *ud);
void ktp_window_set_drop_text_cb(KtpWindow win, KtpDropCb cb, void *ud);
void ktp_window_set_drop_begin_cb(KtpWindow win, KtpVoidCb cb, void *ud);
void ktp_window_set_drop_end_cb(KtpWindow win, KtpVoidCb cb, void *ud);

// --- App lifecycle (mobile background/foreground) ---
// These are app-global, not per-window.

void ktp_set_app_terminating_cb(KtpVoidCb cb, void *ud);
void ktp_set_app_low_memory_cb(KtpVoidCb cb, void *ud);
void ktp_set_app_will_background_cb(KtpVoidCb cb, void *ud);
void ktp_set_app_did_foreground_cb(KtpVoidCb cb, void *ud);

// ============================================================================
// MARK: - Window Properties
// ============================================================================

void  ktp_window_set_title(KtpWindow win, const char *title);
void  ktp_window_set_icon(KtpWindow win, const char *filename);

void  ktp_window_set_pos(KtpWindow win, int x, int y);
void  ktp_window_get_pos(KtpWindow win, int *out_x, int *out_y);

void  ktp_window_get_size(KtpWindow win, int *out_w, int *out_h);
void  ktp_window_get_pixel_size(KtpWindow win, int *out_w, int *out_h);

bool  ktp_window_set_opacity(KtpWindow win, float opacity);
float ktp_window_get_opacity(KtpWindow win);

float ktp_window_get_pixel_density(KtpWindow win);
float ktp_window_get_display_scale(KtpWindow win);

void  ktp_window_set_minimum_size(KtpWindow win, int width, int height);
void  ktp_window_set_always_on_top(KtpWindow win, bool on);
void  ktp_window_set_allow_screensaver(KtpWindow win, bool allow);
void  ktp_window_set_border_state(KtpWindow win, bool borderless);
void  ktp_window_set_fullscreen_mode(KtpWindow win, bool fullscreen);

// ============================================================================
// MARK: - Window State
// ============================================================================

void ktp_window_maximize(KtpWindow win);
void ktp_window_minimize(KtpWindow win);
void ktp_window_restore(KtpWindow win);
void ktp_window_hide(KtpWindow win);
void ktp_window_show(KtpWindow win);
void ktp_window_raise(KtpWindow win);

// ============================================================================
// MARK: - Cursor / Mouse
// ============================================================================

void ktp_window_set_cursor_visible(KtpWindow win, bool visible);
bool ktp_window_set_system_cursor(KtpWindow win, const char *name);
void ktp_window_grab_mouse(KtpWindow win, bool grab);
void ktp_window_get_relative_mouse_pos(KtpWindow win, float *out_x, float *out_y);

// ============================================================================
// MARK: - Keyboard
// ============================================================================

void ktp_window_show_keyboard(KtpWindow win, const char *input_type,
                              bool keyboard_suggestions, int softinput_mode);
void ktp_window_hide_keyboard(KtpWindow win);
bool ktp_window_is_keyboard_shown(KtpWindow win);
int  ktp_window_get_key_modifiers(KtpWindow win);

// ============================================================================
// MARK: - Shaped / Transparent Window
// ============================================================================

bool ktp_window_is_shapable(KtpWindow win);
void ktp_window_set_shape(KtpWindow win, const uint8_t *pixels, int width, int height);

// ============================================================================
// MARK: - Screenshot
// ============================================================================

void ktp_window_save_png(KtpWindow win, const char *filename,
                         const uint8_t *data, int width, int height);

// ============================================================================
// MARK: - Custom Titlebar
// ============================================================================

typedef enum {
    KTP_HIT_NORMAL = 0,
    KTP_HIT_DRAGGABLE,
    KTP_HIT_RESIZE_TOPLEFT,
    KTP_HIT_RESIZE_TOP,
    KTP_HIT_RESIZE_TOPRIGHT,
    KTP_HIT_RESIZE_RIGHT,
    KTP_HIT_RESIZE_BOTTOMRIGHT,
    KTP_HIT_RESIZE_BOTTOM,
    KTP_HIT_RESIZE_BOTTOMLEFT,
    KTP_HIT_RESIZE_LEFT,
} KtpHitTestResult;

typedef KtpHitTestResult (*KtpHitTestCb)(int x, int y, void *ud);

int ktp_window_set_custom_titlebar(KtpWindow win, KtpHitTestCb cb, void *ud);

// ============================================================================
// MARK: - System Theme  (app-global)
// ============================================================================

const char *ktp_get_system_theme(void);

// ============================================================================
// MARK: - ThorVG Canvas Access  (per window)
// ============================================================================
//
// ONE Tvg_Canvas per window — tied to the EGL/GL surface Swift created.
// Cython uses Scenes (tvg_scene_new / tvg_scene_add) from thorvg_capi.h
// for layering.  Scenes are just Tvg_Paint — managed directly via the C API.

/// The ThorVG canvas for this window.
Tvg_Canvas ktp_window_get_canvas(KtpWindow win);

/// Canvas size in pixels (accounts for display density).
void ktp_window_get_canvas_size(KtpWindow win, int *out_w, int *out_h);

#ifdef __cplusplus
}
#endif

#endif /* KIVY_THOR_PROVIDER_H */
