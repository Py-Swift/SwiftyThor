# swiftythor.pyx — Cython module that calls into SwiftyThor's C ABI.
# distutils: language = c

cdef extern from "swiftythor_entry.h":
    void swiftythor_run_app() nogil
    void swiftythor_run_app_sized(int width, int height) nogil


def run_app():
    """Launch the SwiftyThor demo window (blocks until window closes)."""
    with nogil:
        swiftythor_run_app()


def run_app_sized(int width, int height):
    """Launch with explicit window size (blocks until window closes)."""
    with nogil:
        swiftythor_run_app_sized(width, height)
