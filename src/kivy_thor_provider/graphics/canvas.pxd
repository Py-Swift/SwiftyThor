# canvas.pxd — ThorCanvasBase + ThorCanvas declarations
# distutils: language = c

from kivy_thor_provider.graphics.instructions cimport ThorInstruction, ThorInstructionGroup
from thorvg_cython.thorvg cimport Canvas



cdef class ThorCanvasBase(ThorInstructionGroup):
    """Named layer group (before / main / after)."""
    pass


cdef class ThorCanvas(ThorInstruction):
    """Three-layer canvas: before → main → after.

    Mirrors kivy.graphics.Canvas — ``add()`` targets the main layer.
    """
    cdef ThorCanvasBase _before
    cdef ThorCanvasBase _main
    cdef ThorCanvasBase _after

    cpdef add(self, ThorInstruction instruction)
    cpdef remove(self, ThorInstruction instruction)
    cpdef draw_on(self, object scene)
    cdef draw_canvas(self, Canvas c)
