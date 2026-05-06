"""Pytest conftest: add this directory to sys.path so sibling-module imports
(e.g. `from trilemma import ...` inside test_trilemma.py) work when invoked as
`python -m pytest eval/lib/test_trilemma.py` from the contracts/ root."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
