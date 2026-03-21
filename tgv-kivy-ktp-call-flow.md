# KTP — what to call and when

Assumes Kivy's external provider hook is already wired and
`kivy_thor_provider` is installed and registered.

---

```python
from kivy_thor_provider._ktp import app_init, _KtpWindowStorage

# 1. Boot the platform app (once, before any window)
app_init()

# 2. Create a window  →  returns (actual_w, actual_h)
win = _KtpWindowStorage()
w, h = win.setup_window(x, y, width, height,
                         borderless, fullscreen, resizable,
                         state)          # state: 'normal' | 'maximized' | 'minimized' | 'hidden'

# 3. Hook the frame callback  (Swift calls this every vsync)
win.set_frame_handler(lambda dt: my_idle(dt))

# 4. Poll events each frame  (call inside your idle loop)
while (ev := win.poll()):
    handle(ev)        # ev is a tuple, first element is the event name

# 5. Get the ThorVG canvas  (use during draw)
canvas_ptr = win.get_canvas()       # int — pass to thorvg_cython as opaque ptr
cw, ch    = win.get_canvas_size()

# 6. Destroy
win.teardown_window()
```

---

## Event tuple formats (from `poll()`)

| First element | Rest |
|---|---|
| `'mousemotion'` | `x, y` |
| `'mousebuttondown'` / `'mousebuttonup'` | `x, y, button` |
| `'mousewheelleft'` / `'mousewheelright'` / `'mousewheelup'` / `'mousewheeldown'` | `dx, dy, None` |
| `'fingerdown'` / `'fingermotion'` / `'fingerup'` | `finger_id, x, y, pressure` |
| `'keydown'` / `'keyup'` | `mod, key, scancode, text_or_None` |
| `'textinput'` / `'textedit'` | `text` |
| `'windowresized'` | `w, h` |
| `'windowmoved'` | `x, y` |
| `'windowclose'` | — |
| `'windowfocusgained'` / `'windowfocuslost'` | — |
| `'windowminimized'` / `'windowmaximized'` / `'windowrestored'` | — |
| `'windowshown'` / `'windowhidden'` / `'windowexposed'` | — |
| `'windowenter'` / `'windowleave'` | — |
| `'dropfile'` / `'droptext'` | `payload` |
| `'dropbegin'` / `'dropend'` | — |
| `'quit'` | — |
