#!/usr/bin/env python3
"""Test script — imports the Cython swiftythor module and launches the demo."""

import swiftythor

print("Launching SwiftyThor from Python via Cython → C ABI → Swift...")
swiftythor.run_app()
print("Window closed.")
