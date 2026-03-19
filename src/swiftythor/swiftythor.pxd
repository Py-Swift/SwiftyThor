# swiftythor.pxd — Cython declaration file for SwiftyThor C entry points
cdef extern from "swiftythor_entry.h":
    void swiftythor_run_app() nogil
    void swiftythor_run_app_sized(int width, int height) nogil
