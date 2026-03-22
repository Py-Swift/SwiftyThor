# cython: language_level=3
# screenmanager.pyx — TScreen + TScreenManager

import weakref
from thorvg_cython.thorvg cimport Scene, Canvas
from thorvg_cython.thorvg import Scene as _Scene
#from thorvg_cython.cthorvg cimport Tvg_Canvas, Tvg_Scene
from kivy_thor_provider.graphics.canvas cimport ThorCanvas


cdef class TScreen:
    """A screen owns a canvas (instruction layers) + a persistent ThorVG Scene.

    The Scene is created immediately at construction.  Every widget added via
    ``add_widget`` pushes its paints into the scene on the spot.  Swift reads
    ``screen.scene`` once and calls ``tvg_canvas_add(canvas, scene._p)``.
    After that, widget property mutations go directly to stored Tvg_Paint*
    handles — ThorVG marks them dirty, Swift's next update/draw/sync renders them.
    """

    def __cinit__(self):
        self._canvas       = ThorCanvas()
        self._root_widgets = []
        self._scene        = _Scene()

    @property
    def canvas(self) -> ThorCanvas:
        return self._canvas

    @property
    def scene(self):
        """The root thorvg_cython.Scene — pass to Swift via tvg_canvas_add."""
        return self._scene

    cpdef add_widget(self, object widget):
        self._root_widgets.append(widget)
        if hasattr(widget, '_parent_ref'):
            widget._parent_ref = weakref.ref(self)
        widget.draw_on(self._scene)

    cpdef remove_widget(self, object widget):
        self._root_widgets.remove(widget)
        if hasattr(widget, '_parent_ref'):
            widget._parent_ref = None

    cdef canvas_update(self, Canvas c):
        self._canvas.draw_on(self._scene)

    cdef draw_on(self, Scene s):
        self._canvas.draw_on(s)


cdef class TScreenManager:
    """Stack of TScreens.  No canvas knowledge — Swift handles tvg_canvas_add/remove."""

    def __cinit__(self):
        self._current           = None
        self._last              = None
        self._transition_active = False

    @property
    def current(self) -> TScreen:
        return self._current

    @property
    def last(self) -> TScreen:
        return self._last

    @property
    def transition_active(self) -> bool:
        return self._transition_active

    @transition_active.setter
    def transition_active(self, bint value):
        self._transition_active = value

    cpdef switch_to(self, TScreen screen):
        self._last    = self._current
        self._current = screen
        if not self._transition_active:
            self._last = None

    cdef canvas_update(self, Canvas c):
        if self._current is not None:
            (<TScreen>self._current).canvas_update(c)
        if self._transition_active and self._last is not None:
            (<TScreen>self._last).canvas_update(c)



