# _instructions.pxd — ThorInstruction + ThorInstructionGroup declarations
# distutils: language = c

cdef class ThorInstruction:
    """Base for every ThorVG drawing instruction."""
    cpdef draw_on(self, object scene)


cdef class ThorInstructionGroup(ThorInstruction):
    """Ordered list of ThorInstructions rendered into a ThorVG sub-Scene."""
    cdef list _instructions

    cpdef add(self, ThorInstruction instruction)
    cpdef remove(self, ThorInstruction instruction)
    cpdef insert(self, int index, ThorInstruction instruction)
    cpdef clear(self)
    cpdef draw_on(self, object scene)
