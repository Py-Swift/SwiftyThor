# kivy_thor_provider — Cython bridge between Swift and Kivy's window system.
#
# The low-level C⟷Cython wrapper lives in _ktp.pyx / _ktp.pxd.
# The Python-level WindowThor class (≈ WindowSDL) will import from here.

from kivy_thor_provider._ktp import *
