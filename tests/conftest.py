"""Puts the project's bare-import modules (data_generation/, ingestion/,
common/) on sys.path the same way generate.py / *_ingest.py already do when
run directly, so tests can `import config`, `import calendar_utils`, etc.
without turning those directories into installable packages.
"""
from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

for p in (PROJECT_ROOT, PROJECT_ROOT / "data_generation", PROJECT_ROOT / "ingestion"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))
