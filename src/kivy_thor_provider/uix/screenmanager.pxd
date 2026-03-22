# screenmanager.pxd
# distutils: language = c

from thorvg_cython.thorvg cimport Scene, Canvas
#from thorvg_cython.cthorvg cimport Tvg_Canvas

from kivy_thor_provider.graphics.canvas cimport ThorCanvas


cdef class TScreen:
    cdef ThorCanvas _canvas
    cdef list       _root_widgets
    cdef Scene  _scene

    cpdef add_widget(self, object widget)
    cpdef remove_widget(self, object widget)
    cdef canvas_update(self, Canvas c)
    cdef draw_on(self, Scene s)


cdef class TScreenManager:
    cdef object _current
    cdef object _last
    cdef bint   _transition_active

    cpdef switch_to(self, TScreen screen)
    cdef canvas_update(self, Canvas c)
