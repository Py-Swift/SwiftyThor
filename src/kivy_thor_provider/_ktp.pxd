# _ktp.pxd — Cython declarations for kivy_thor_provider.h
# distutils: language = c

from libc.stdint cimport int32_t, int64_t, uint8_t

cdef extern from "thorvg_capi.h":
    ctypedef struct _Tvg_Canvas:
        pass
    ctypedef _Tvg_Canvas *Tvg_Canvas

    ctypedef struct _Tvg_Paint:
        pass
    ctypedef _Tvg_Paint *Tvg_Paint

    ctypedef int Tvg_Result
    int TVG_RESULT_SUCCESS


cdef extern from "kivy_thor_provider.h":

    # --- Opaque window handle (void* — Swift uses Unmanaged<KtpWindowState>) ---
    ctypedef void *KtpWindow

    # --- App init ---
    void ktp_app_init(bint embedded) nogil

    # --- Engine lifecycle ---
    void ktp_engine_start(unsigned int threads) nogil
    void ktp_engine_stop() nogil

    # --- Window lifecycle ---
    KtpWindow ktp_window_create(int x, int y,
                                int width, int height,
                                bint borderless,
                                bint fullscreen,
                                bint resizable,
                                int state,
                                int *out_width, int *out_height) nogil
    void ktp_window_destroy(KtpWindow win) nogil
    void ktp_window_resize(KtpWindow win, int width, int height) nogil

    # --- Frame callback ---
    ctypedef void (*KtpFrameCb)(double dt, void *ud)
    void ktp_window_set_frame_cb(KtpWindow win, KtpFrameCb cb, void *ud) nogil

    # --- Mouse callbacks ---
    ctypedef void (*KtpMouseMotionCb)(float x, float y, void *ud)
    ctypedef void (*KtpMouseButtonCb)(float x, float y, int button, void *ud)
    ctypedef void (*KtpMouseWheelCb)(float dx, float dy, void *ud)

    void ktp_window_set_mouse_motion_cb(KtpWindow win, KtpMouseMotionCb cb, void *ud) nogil
    void ktp_window_set_mouse_button_down_cb(KtpWindow win, KtpMouseButtonCb cb, void *ud) nogil
    void ktp_window_set_mouse_button_up_cb(KtpWindow win, KtpMouseButtonCb cb, void *ud) nogil
    void ktp_window_set_mouse_wheel_cb(KtpWindow win, KtpMouseWheelCb cb, void *ud) nogil

    # --- Touch callbacks ---
    ctypedef void (*KtpTouchCb)(int64_t finger_id, float x, float y,
                                float pressure, void *ud)
    void ktp_window_set_touch_down_cb(KtpWindow win, KtpTouchCb cb, void *ud) nogil
    void ktp_window_set_touch_moved_cb(KtpWindow win, KtpTouchCb cb, void *ud) nogil
    void ktp_window_set_touch_up_cb(KtpWindow win, KtpTouchCb cb, void *ud) nogil

    # --- Keyboard callbacks ---
    ctypedef void (*KtpKeyCb)(int mod, int key, int scancode,
                              const char *text, void *ud)
    ctypedef void (*KtpTextCb)(const char *text, void *ud)

    void ktp_window_set_key_down_cb(KtpWindow win, KtpKeyCb cb, void *ud) nogil
    void ktp_window_set_key_up_cb(KtpWindow win, KtpKeyCb cb, void *ud) nogil
    void ktp_window_set_text_input_cb(KtpWindow win, KtpTextCb cb, void *ud) nogil
    void ktp_window_set_text_edit_cb(KtpWindow win, KtpTextCb cb, void *ud) nogil

    # --- Window state callbacks ---
    ctypedef void (*KtpSizeCb)(int w, int h, void *ud)
    ctypedef void (*KtpPosCb)(int x, int y, void *ud)
    ctypedef void (*KtpVoidCb)(void *ud)

    void ktp_window_set_resized_cb(KtpWindow win, KtpSizeCb cb, void *ud) nogil
    void ktp_window_set_moved_cb(KtpWindow win, KtpPosCb cb, void *ud) nogil
    void ktp_window_set_close_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_focus_gained_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_focus_lost_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_minimized_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_maximized_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_restored_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_shown_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_hidden_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_exposed_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil

    # --- Cursor enter/leave ---
    void ktp_window_set_cursor_enter_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_cursor_leave_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil

    # --- Drop callbacks ---
    ctypedef void (*KtpDropCb)(const char *payload, void *ud)
    void ktp_window_set_drop_file_cb(KtpWindow win, KtpDropCb cb, void *ud) nogil
    void ktp_window_set_drop_text_cb(KtpWindow win, KtpDropCb cb, void *ud) nogil
    void ktp_window_set_drop_begin_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil
    void ktp_window_set_drop_end_cb(KtpWindow win, KtpVoidCb cb, void *ud) nogil

    # --- App lifecycle (global) ---
    void ktp_set_app_terminating_cb(KtpVoidCb cb, void *ud) nogil
    void ktp_set_app_low_memory_cb(KtpVoidCb cb, void *ud) nogil
    void ktp_set_app_will_background_cb(KtpVoidCb cb, void *ud) nogil
    void ktp_set_app_did_foreground_cb(KtpVoidCb cb, void *ud) nogil

    # --- Window properties ---
    void  ktp_window_set_title(KtpWindow win, const char *title) nogil
    void  ktp_window_set_icon(KtpWindow win, const char *filename) nogil
    void  ktp_window_set_pos(KtpWindow win, int x, int y) nogil
    void  ktp_window_get_pos(KtpWindow win, int *out_x, int *out_y) nogil
    void  ktp_window_get_size(KtpWindow win, int *out_w, int *out_h) nogil
    void  ktp_window_get_pixel_size(KtpWindow win, int *out_w, int *out_h) nogil
    bint  ktp_window_set_opacity(KtpWindow win, float opacity) nogil
    float ktp_window_get_opacity(KtpWindow win) nogil
    float ktp_window_get_pixel_density(KtpWindow win) nogil
    float ktp_window_get_display_scale(KtpWindow win) nogil
    void  ktp_window_set_minimum_size(KtpWindow win, int width, int height) nogil
    void  ktp_window_set_always_on_top(KtpWindow win, bint on) nogil
    void  ktp_window_set_allow_screensaver(KtpWindow win, bint allow) nogil
    void  ktp_window_set_border_state(KtpWindow win, bint borderless) nogil
    void  ktp_window_set_fullscreen_mode(KtpWindow win, bint fullscreen) nogil

    # --- Window state ---
    void ktp_window_maximize(KtpWindow win) nogil
    void ktp_window_minimize(KtpWindow win) nogil
    void ktp_window_restore(KtpWindow win) nogil
    void ktp_window_hide(KtpWindow win) nogil
    void ktp_window_show(KtpWindow win) nogil
    void ktp_window_raise(KtpWindow win) nogil

    # --- Cursor / mouse ---
    void ktp_window_set_cursor_visible(KtpWindow win, bint visible) nogil
    bint ktp_window_set_system_cursor(KtpWindow win, const char *name) nogil
    void ktp_window_grab_mouse(KtpWindow win, bint grab) nogil
    void ktp_window_get_relative_mouse_pos(KtpWindow win, float *out_x, float *out_y) nogil

    # --- Keyboard ---
    void ktp_window_show_keyboard(KtpWindow win, const char *input_type,
                                  bint keyboard_suggestions, int softinput_mode) nogil
    void ktp_window_hide_keyboard(KtpWindow win) nogil
    bint ktp_window_is_keyboard_shown(KtpWindow win) nogil
    int  ktp_window_get_key_modifiers(KtpWindow win) nogil

    # --- Shape ---
    bint ktp_window_is_shapable(KtpWindow win) nogil
    void ktp_window_set_shape(KtpWindow win, const uint8_t *pixels,
                              int width, int height) nogil

    # --- Screenshot ---
    void ktp_window_save_png(KtpWindow win, const char *filename,
                             const uint8_t *data, int width, int height) nogil

    # --- Custom titlebar ---
    ctypedef int KtpHitTestResult
    ctypedef KtpHitTestResult (*KtpHitTestCb)(int x, int y, void *ud)
    int ktp_window_set_custom_titlebar(KtpWindow win, KtpHitTestCb cb, void *ud) nogil

    # --- System theme (global) ---
    const char *ktp_get_system_theme() nogil

    # --- ThorVG canvas ---
    Tvg_Canvas ktp_window_get_canvas(KtpWindow win) nogil
    void ktp_window_get_canvas_size(KtpWindow win, int *out_w, int *out_h) nogil
