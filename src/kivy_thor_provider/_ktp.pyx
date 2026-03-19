# _ktp.pyx — Cython wrapper for kivy_thor_provider.h
# distutils: language = c
#
# Pure push model: Swift fires C callbacks → trampolines queue events →
# Python-side WindowThor drains via poll() exactly like WindowSDL.
# Frame callback is special — it drives a full Kivy idle cycle.

from libc.stdint cimport uintptr_t, int64_t, uint8_t
from collections import deque


# =============================================================================
# Module-level callback trampolines  (called from Swift without GIL)
# =============================================================================
# Each one acquires the GIL, casts `ud` to _KtpWindowStorage, and either
# queues a Kivy-style event tuple or calls a handler directly.


# --- Frame (display-link) ---------------------------------------------------

cdef void _cb_frame(double dt, void *ud) noexcept with gil:
    """Called by Swift each vsync.  Drives one full Kivy idle cycle."""
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    handler = s._frame_handler
    if handler is not None:
        handler(dt)


# --- Mouse -------------------------------------------------------------------

cdef void _cb_mouse_motion(float x, float y, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('mousemotion', x, y))


cdef void _cb_mouse_button_down(float x, float y, int button,
                                void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('mousebuttondown', x, y, button))


cdef void _cb_mouse_button_up(float x, float y, int button,
                              void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('mousebuttonup', x, y, button))


cdef void _cb_mouse_wheel(float dx, float dy, void *ud) noexcept with gil:
    cdef str suffix
    if dx != 0:
        suffix = 'left' if dx > 0 else 'right'
    elif dy != 0:
        suffix = 'down' if dy > 0 else 'up'
    else:
        return
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('mousewheel' + suffix, dx, dy, None))


# --- Touch -------------------------------------------------------------------

cdef void _cb_touch_down(int64_t fid, float x, float y,
                         float pressure, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('fingerdown', fid, x, y, pressure))


cdef void _cb_touch_moved(int64_t fid, float x, float y,
                          float pressure, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('fingermotion', fid, x, y, pressure))


cdef void _cb_touch_up(int64_t fid, float x, float y,
                       float pressure, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('fingerup', fid, x, y, pressure))


# --- Keyboard ----------------------------------------------------------------

cdef void _cb_key_down(int mod, int key, int scancode,
                       const char *text, void *ud) noexcept with gil:
    cdef str t = None
    if text != NULL:
        t = text.decode('utf-8')
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('keydown', mod, key, scancode, t))


cdef void _cb_key_up(int mod, int key, int scancode,
                     const char *text, void *ud) noexcept with gil:
    cdef str t = None
    if text != NULL:
        t = text.decode('utf-8')
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('keyup', mod, key, scancode, t))


cdef void _cb_text_input(const char *text, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('textinput', text.decode('utf-8')))


cdef void _cb_text_edit(const char *text, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('textedit', text.decode('utf-8')))


# --- Window state ------------------------------------------------------------

cdef void _cb_resized(int w, int h, void *ud) noexcept with gil:
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    # Live‑resize: call event_filter directly (same as SDL3 behaviour
    # which forces an immediate EventLoop.idle inside the resize drag).
    if s._event_filter is not None:
        s._event_filter('windowresized', w, h)
    else:
        s._event_queue.append(('windowresized', w, h))


cdef void _cb_moved(int x, int y, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowmoved', x, y))


cdef void _cb_close(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowclose',))


cdef void _cb_focus_gained(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowfocusgained',))


cdef void _cb_focus_lost(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowfocuslost',))


cdef void _cb_minimized(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowminimized',))


cdef void _cb_maximized(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowmaximized',))


cdef void _cb_restored(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowrestored',))


cdef void _cb_shown(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowshown',))


cdef void _cb_hidden(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowhidden',))


cdef void _cb_exposed(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowexposed',))


# --- Cursor enter/leave ------------------------------------------------------

cdef void _cb_cursor_enter(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowenter',))


cdef void _cb_cursor_leave(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('windowleave',))


# --- Drop --------------------------------------------------------------------

cdef void _cb_drop_file(const char *payload, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('dropfile', payload.decode('utf-8')))


cdef void _cb_drop_text(const char *payload, void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(
        ('droptext', payload.decode('utf-8')))


cdef void _cb_drop_begin(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('dropbegin',))


cdef void _cb_drop_end(void *ud) noexcept with gil:
    (<_KtpWindowStorage>ud)._event_queue.append(('dropend',))


# --- App lifecycle (global) --------------------------------------------------
# These are app‑wide, so we route to the first window's filter/queue.

cdef void _cb_app_terminating(void *ud) noexcept with gil:
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    if s._event_filter is not None:
        s._event_filter('app_terminating')
    else:
        s._event_queue.append(('quit',))


cdef void _cb_app_low_memory(void *ud) noexcept with gil:
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    if s._event_filter is not None:
        s._event_filter('app_lowmemory')


cdef void _cb_app_will_background(void *ud) noexcept with gil:
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    if s._event_filter is not None:
        s._event_filter('app_willenterbackground')


cdef void _cb_app_did_foreground(void *ud) noexcept with gil:
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    if s._event_filter is not None:
        s._event_filter('app_didenterforeground')


# --- Custom titlebar hit‑test ------------------------------------------------

cdef KtpHitTestResult _cb_hit_test(int x, int y,
                                   void *ud) noexcept with gil:
    cdef _KtpWindowStorage s = <_KtpWindowStorage>ud
    if s._titlebar_handler is not None:
        return <KtpHitTestResult>s._titlebar_handler(x, y)
    return <KtpHitTestResult>0  # KTP_HIT_NORMAL


# =============================================================================
# Storage class  (one per window — wraps a KtpWindow handle)
# =============================================================================

cdef class _KtpWindowStorage:
    """Low‑level Cython wrapper around a single KtpWindow.

    Mirrors the interface of _WindowSDL3Storage so that the Python‑side
    WindowThor class (≈ WindowSDL) can be written with minimal changes.

    Events pushed from Swift land in ``_event_queue`` and are drained by
    ``poll()``.  The frame callback is handled separately via the
    ``_frame_handler`` callable.
    """

    cdef KtpWindow _win
    cdef object _event_queue       # deque of event tuples
    cdef object _event_filter      # callable(action, *args) or None
    cdef object _frame_handler     # callable(dt) or None
    cdef object _titlebar_handler  # callable(x, y) → int or None

    def __cinit__(self):
        self._win = NULL
        self._event_queue = deque()
        self._event_filter = None
        self._frame_handler = None
        self._titlebar_handler = None

    def __dealloc__(self):
        if self._win != NULL:
            ktp_window_destroy(self._win)
            self._win = NULL

    # -----------------------------------------------------------------
    # Event filter / frame handler
    # -----------------------------------------------------------------

    def set_event_filter(self, event_filter):
        self._event_filter = event_filter

    def set_frame_handler(self, handler):
        """Set a callable(dt) invoked every vsync by Swift's display‑link."""
        self._frame_handler = handler

    # -----------------------------------------------------------------
    # Window lifecycle
    # -----------------------------------------------------------------

    def setup_window(self, x, y, width, height,
                     bint borderless, bint fullscreen,
                     bint resizable, state):
        """Create the native window.  Returns (width, height)."""
        cdef int out_w = 0, out_h = 0
        cdef int _state = 0

        if state == 'maximized':
            _state = 1
        elif state == 'minimized':
            _state = 2
        elif state == 'hidden':
            _state = 3

        cdef int _x = x if x is not None else -1
        cdef int _y = y if y is not None else -1

        self._win = ktp_window_create(
            _x, _y, width, height,
            borderless, fullscreen, resizable,
            _state, &out_w, &out_h)

        if self._win == NULL:
            raise RuntimeError('Failed to create KTP window')

        # Register all push‑model callbacks with self as userdata
        self._register_callbacks()

        return out_w, out_h

    cdef void _register_callbacks(self):
        cdef void *ud = <void *>self

        # Frame
        ktp_window_set_frame_cb(self._win, _cb_frame, ud)

        # Mouse
        ktp_window_set_mouse_motion_cb(self._win, _cb_mouse_motion, ud)
        ktp_window_set_mouse_button_down_cb(
            self._win, _cb_mouse_button_down, ud)
        ktp_window_set_mouse_button_up_cb(
            self._win, _cb_mouse_button_up, ud)
        ktp_window_set_mouse_wheel_cb(self._win, _cb_mouse_wheel, ud)

        # Touch
        ktp_window_set_touch_down_cb(self._win, _cb_touch_down, ud)
        ktp_window_set_touch_moved_cb(self._win, _cb_touch_moved, ud)
        ktp_window_set_touch_up_cb(self._win, _cb_touch_up, ud)

        # Keyboard
        ktp_window_set_key_down_cb(self._win, _cb_key_down, ud)
        ktp_window_set_key_up_cb(self._win, _cb_key_up, ud)
        ktp_window_set_text_input_cb(self._win, _cb_text_input, ud)
        ktp_window_set_text_edit_cb(self._win, _cb_text_edit, ud)

        # Window state
        ktp_window_set_resized_cb(self._win, _cb_resized, ud)
        ktp_window_set_moved_cb(self._win, _cb_moved, ud)
        ktp_window_set_close_cb(self._win, _cb_close, ud)
        ktp_window_set_focus_gained_cb(self._win, _cb_focus_gained, ud)
        ktp_window_set_focus_lost_cb(self._win, _cb_focus_lost, ud)
        ktp_window_set_minimized_cb(self._win, _cb_minimized, ud)
        ktp_window_set_maximized_cb(self._win, _cb_maximized, ud)
        ktp_window_set_restored_cb(self._win, _cb_restored, ud)
        ktp_window_set_shown_cb(self._win, _cb_shown, ud)
        ktp_window_set_hidden_cb(self._win, _cb_hidden, ud)
        ktp_window_set_exposed_cb(self._win, _cb_exposed, ud)

        # Cursor enter/leave
        ktp_window_set_cursor_enter_cb(self._win, _cb_cursor_enter, ud)
        ktp_window_set_cursor_leave_cb(self._win, _cb_cursor_leave, ud)

        # Drop
        ktp_window_set_drop_file_cb(self._win, _cb_drop_file, ud)
        ktp_window_set_drop_text_cb(self._win, _cb_drop_text, ud)
        ktp_window_set_drop_begin_cb(self._win, _cb_drop_begin, ud)
        ktp_window_set_drop_end_cb(self._win, _cb_drop_end, ud)

        # App lifecycle (global — attached to this window's filter)
        ktp_set_app_terminating_cb(_cb_app_terminating, ud)
        ktp_set_app_low_memory_cb(_cb_app_low_memory, ud)
        ktp_set_app_will_background_cb(_cb_app_will_background, ud)
        ktp_set_app_did_foreground_cb(_cb_app_did_foreground, ud)

    def teardown_window(self):
        if self._win != NULL:
            ktp_window_destroy(self._win)
            self._win = NULL

    def resize_window(self, int w, int h):
        if self._win != NULL:
            ktp_window_resize(self._win, w, h)

    # -----------------------------------------------------------------
    # Event queue  (drain from Python — same contract as _WindowSDL3Storage)
    # -----------------------------------------------------------------

    def poll(self):
        """Return the next event tuple, or ``False`` if the queue is empty.

        Format matches the SDL3 storage tuples so that the Python‑level
        WindowThor mainloop can be nearly identical to WindowSDL.
        """
        try:
            return self._event_queue.popleft()
        except IndexError:
            return False

    # -----------------------------------------------------------------
    # Window properties
    # -----------------------------------------------------------------

    def set_window_title(self, title):
        cdef bytes b = title.encode('utf-8')
        ktp_window_set_title(self._win, b)

    def set_window_icon(self, filename):
        cdef bytes b = filename.encode('utf-8')
        ktp_window_set_icon(self._win, b)

    def set_window_pos(self, x, y):
        cdef int _x = x if x is not None else -1
        cdef int _y = y if y is not None else -1
        ktp_window_set_pos(self._win, _x, _y)

    def get_window_pos(self):
        cdef int x, y
        ktp_window_get_pos(self._win, &x, &y)
        return x, y

    @property
    def window_size(self):
        cdef int w, h
        ktp_window_get_size(self._win, &w, &h)
        return [w, h]

    @property
    def window_pixel_size(self):
        cdef int w, h
        ktp_window_get_pixel_size(self._win, &w, &h)
        return w, h

    def set_window_opacity(self, float opacity):
        if not ktp_window_set_opacity(self._win, opacity):
            return False
        return True

    def get_window_opacity(self):
        return ktp_window_get_opacity(self._win)

    def get_window_pixel_density(self):
        cdef float d = ktp_window_get_pixel_density(self._win)
        return d if d != 0.0 else 1.0

    def get_window_display_scale(self):
        cdef float s = ktp_window_get_display_scale(self._win)
        return s if s != 0.0 else 1.0

    def set_minimum_size(self, int w, int h):
        ktp_window_set_minimum_size(self._win, w, h)

    def set_always_on_top(self, bint on):
        ktp_window_set_always_on_top(self._win, on)

    def set_allow_screensaver(self, bint allow):
        ktp_window_set_allow_screensaver(self._win, allow)

    def set_border_state(self, bint borderless):
        ktp_window_set_border_state(self._win, borderless)

    def set_fullscreen_mode(self, mode):
        cdef bint fs = True if mode is True else False
        ktp_window_set_fullscreen_mode(self._win, fs)

    # -----------------------------------------------------------------
    # Window state
    # -----------------------------------------------------------------

    def maximize_window(self):
        ktp_window_maximize(self._win)

    def minimize_window(self):
        ktp_window_minimize(self._win)

    def restore_window(self):
        ktp_window_restore(self._win)

    def hide_window(self):
        ktp_window_hide(self._win)

    def show_window(self):
        ktp_window_show(self._win)

    def raise_window(self):
        ktp_window_raise(self._win)

    # -----------------------------------------------------------------
    # Cursor / mouse
    # -----------------------------------------------------------------

    def _set_cursor_state(self, bint visible):
        ktp_window_set_cursor_visible(self._win, visible)

    def set_system_cursor(self, str name):
        cdef bytes b = name.encode('utf-8')
        return ktp_window_set_system_cursor(self._win, b)

    def grab_mouse(self, bint grab):
        ktp_window_grab_mouse(self._win, grab)

    def get_relative_mouse_pos(self):
        cdef float x, y
        ktp_window_get_relative_mouse_pos(self._win, &x, &y)
        return x, y

    # -----------------------------------------------------------------
    # Keyboard
    # -----------------------------------------------------------------

    def show_keyboard(self, system_keyboard, softinput_mode,
                      input_type, keyboard_suggestions=True):
        cdef bytes b_input_type = input_type.encode('utf-8')
        ktp_window_show_keyboard(self._win, b_input_type,
                                 keyboard_suggestions, 0)

    def hide_keyboard(self):
        ktp_window_hide_keyboard(self._win)

    def is_keyboard_shown(self):
        return ktp_window_is_keyboard_shown(self._win)

    def get_current_key_modifiers(self):
        return ktp_window_get_key_modifiers(self._win)

    # -----------------------------------------------------------------
    # Shape / transparency
    # -----------------------------------------------------------------

    def is_window_shapable(self):
        return ktp_window_is_shapable(self._win)

    cpdef set_shape(self, shape_image):
        cdef int w = shape_image.width
        cdef int h = shape_image.height
        cdef bytes px = shape_image.texture.pixels
        ktp_window_set_shape(self._win, <const uint8_t *>px, w, h)

    # -----------------------------------------------------------------
    # Screenshot
    # -----------------------------------------------------------------

    def save_bytes_in_png(self, filename, data, int width, int height):
        cdef bytes b_fn = filename.encode('utf-8')
        cdef bytes b_data = data
        ktp_window_save_png(self._win, b_fn,
                            <const uint8_t *>b_data, width, height)

    # -----------------------------------------------------------------
    # Custom titlebar
    # -----------------------------------------------------------------

    def set_custom_titlebar(self, titlebar_widget):
        """Register a hit-test handler.

        ``titlebar_widget`` is stored and used from the trampoline.
        The actual hit-test logic lives in Python (WindowThor).
        """
        self._titlebar_handler = titlebar_widget
        return ktp_window_set_custom_titlebar(
            self._win, _cb_hit_test, <void *>self)

    # -----------------------------------------------------------------
    # System theme (global)
    # -----------------------------------------------------------------

    cpdef str get_system_theme(self):
        cdef const char *t = ktp_get_system_theme()
        if t == NULL:
            return 'unknown'
        return t.decode('utf-8')

    # -----------------------------------------------------------------
    # ThorVG canvas access
    # -----------------------------------------------------------------

    def get_canvas(self):
        """Return the raw Tvg_Canvas pointer as a Python int (capsule-free).

        Intended for passing to thorvg_cython helpers that accept an
        opaque pointer.
        """
        cdef Tvg_Canvas c = ktp_window_get_canvas(self._win)
        return <uintptr_t>c

    def get_canvas_size(self):
        cdef int w, h
        ktp_window_get_canvas_size(self._win, &w, &h)
        return w, h
