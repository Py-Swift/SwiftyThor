# cython: language_level=3
# instructions.pyx — ThorInstruction + ThorInstructionGroup
#
# draw_on(scene) is called ONCE at attach_canvas time.
# After that, paints live in ThorVG memory and are mutated in-place.

from thorvg_cython import Scene


cdef class ThorInstruction:
    """Base for every ThorVG drawing instruction.

    Override ``draw_on(scene)`` to create a ThorVG paint and add it to
    *scene*.  Called once when the screen's paint tree is built.  After
    attach, mutate stored paint handles directly — ThorVG marks them dirty
    and the next ``update/draw/sync`` picks up the change.

    Example::

        cdef class ThorRect(ThorInstruction):
            cdef object _shape   # thorvg_cython.Shape — kept alive

            def __cinit__(self, float x, float y, float w, float h):
                from thorvg_cython import Shape
                self._shape = Shape()
                self._shape.append_rect(x, y, w, h)
                self._shape.set_fill_color(200, 100, 50, 255)

            cpdef draw_on(self, object scene):
                scene.add(self._shape)

            def set_color(self, r, g, b, a=255):
                self._shape.set_fill_color(r, g, b, a)  # dirty — no rebuild
    """

    cpdef draw_on(self, object scene):
        """Add this instruction's paint into *scene*.  Called once at attach."""
        pass


cdef class ThorInstructionGroup(ThorInstruction):
    """Ordered list of ThorInstructions rendered into a ThorVG sub-Scene.

    ``draw_on(parent_scene)`` creates a sub-Scene, calls ``draw_on`` on
    every child (each adding their persistent paint once), then adds the
    sub-scene into *parent_scene*.  Empty groups are skipped.
    """

    def __cinit__(self):
        self._instructions = []

    cpdef add(self, ThorInstruction instruction):
        self._instructions.append(instruction)

    cpdef remove(self, ThorInstruction instruction):
        self._instructions.remove(instruction)

    cpdef insert(self, int index, ThorInstruction instruction):
        self._instructions.insert(index, instruction)

    cpdef clear(self):
        self._instructions = []

    cpdef draw_on(self, object parent_scene):
        if not self._instructions:
            return
        cdef object scene = Scene()
        for item in self._instructions:
            (<ThorInstruction>item).draw_on(scene)
        parent_scene.add(scene)
