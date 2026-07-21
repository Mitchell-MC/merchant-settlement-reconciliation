"""Shared structured-logging setup for the Python side of the platform.

`print("error happened")` is useless at 3am -- it has no timestamp, no
module, no severity, and nothing to grep. Every generator/ingestion/load
script uses `get_logger(__name__)` from here instead, so every line an
operator sees on a red run carries when it happened, how bad it is, which
module emitted it, and the actual message/payload.

Kept intentionally dependency-free (stdlib logging only) -- this runs in CI,
in Databricks jobs, and in GitHub Actions with nothing extra installed.
"""
from __future__ import annotations

import logging
import os
import sys

_CONFIGURED = False

# Timestamp | level | module | message -- the four things you actually need
# to triage. Pass structured context in the message itself, e.g.
# logger.error("landed rows failed contract | table=%s | column=%s", t, c).
_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
_DATEFMT = "%Y-%m-%dT%H:%M:%S%z"


def configure_logging(level: int | None = None) -> None:
    """Install a single stdout handler with the structured format. Idempotent
    -- safe to call from every module's import without stacking handlers.

    Level comes from the LOG_LEVEL env var (default INFO) so a job can be dialed
    to DEBUG without a code change.
    """
    global _CONFIGURED
    if _CONFIGURED:
        return

    if level is None:
        level = getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(fmt=_FORMAT, datefmt=_DATEFMT))

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)
    _CONFIGURED = True


def get_logger(name: str) -> logging.Logger:
    """Configured logger for a module. Use `get_logger(__name__)`."""
    configure_logging()
    return logging.getLogger(name)
