# cython: language_level=3
# canvas.pyx — ThorCanvasBase + ThorCanvas

from thorvg_cython.cthorvg cimport Tvg_Canvas
from kivy_thor_provider.graphics.instructions cimport ThorInstruction, ThorInstructionGroup


cdef class ThorCanvasBase(ThorInstructionGroup):
    """Named InstructionGroup for a single canvas layer (before/main/after).

    Identical to ThorInstructionGroup at the C level; the distinct type
    exists for isinstance checks and future per-layer behaviour.
    """
    pass


cdef class ThorCanvas(ThorInstruction):
    """Three-layer canvas: before → main → after.

    Mirrors Kivy's ``canvas.before`` / ``canvas`` / ``canvas.after`` model.
    ``add(instruction)`` targets the *main* layer.

    Example::

        widget.canvas.before.add(ThorRect(0, 0, 800, 600, color=(30, 30, 46)))
        widget.canvas.add(ThorCircle(cx=400, cy=300, r=100))
        widget.canvas.after.add(ThorOutline(...))
    """

    def __cinit__(self):
        self._before = ThorCanvasBase()
        self._main   = ThorCanvasBase()
        self._after  = ThorCanvasBase()

    @property
    def before(self) -> ThorCanvasBase:
        return self._before

    @property
    def after(self) -> ThorCanvasBase:
        return self._after

    cpdef add(self, ThorInstruction instruction):
        self._main.add(instruction)

    cpdef remove(self, ThorInstruction instruction):
        for layer in (self._before, self._main, self._after):
            if instruction in (<ThorInstructionGroup>layer)._instructions:
                (<ThorInstructionGroup>layer).remove(instruction)
                return
        raise ValueError(f'{instruction!r} not found in any canvas layer')

    cpdef draw_on(self, object scene):
        self._before.draw_on(scene)
        self._main.draw_on(scene)
        self._after.draw_on(scene)

    cdef draw_canvas(self, Canvas c):
        print(self, c)
