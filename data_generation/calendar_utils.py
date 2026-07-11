"""US Federal Reserve holiday calendar and business-day arithmetic.

Bank/ACH settlement moves on the Federal Reserve's holiday schedule, not just
weekends -- this drives the "weekend/holiday lag" break pattern the plan
calls for. Computed algorithmically so it's correct for any year, not just a
hardcoded lookup table.
"""
from __future__ import annotations

from datetime import date, timedelta
from functools import lru_cache


def _nth_weekday_of_month(year: int, month: int, weekday: int, n: int) -> date:
    """weekday: Monday=0 ... Sunday=6. n=1 -> first occurrence, n=-1 -> last."""
    if n > 0:
        d = date(year, month, 1)
        offset = (weekday - d.weekday()) % 7
        d += timedelta(days=offset + 7 * (n - 1))
        return d
    # last occurrence: start from next month's first day and walk back
    if month == 12:
        d = date(year + 1, 1, 1)
    else:
        d = date(year, month + 1, 1)
    d -= timedelta(days=1)
    offset = (d.weekday() - weekday) % 7
    return d - timedelta(days=offset)


def _observed(d: date) -> date:
    """Federal observed-holiday rule: Sat -> preceding Fri, Sun -> following Mon."""
    if d.weekday() == 5:  # Saturday
        return d - timedelta(days=1)
    if d.weekday() == 6:  # Sunday
        return d + timedelta(days=1)
    return d


@lru_cache(maxsize=None)
def federal_holidays(year: int) -> frozenset:
    fixed = [
        date(year, 1, 1),    # New Year's Day
        date(year, 6, 19),   # Juneteenth
        date(year, 7, 4),    # Independence Day
        date(year, 11, 11),  # Veterans Day
        date(year, 12, 25),  # Christmas Day
    ]
    floating = [
        _nth_weekday_of_month(year, 1, 0, 3),    # MLK Day - 3rd Monday of Jan
        _nth_weekday_of_month(year, 2, 0, 3),    # Presidents Day - 3rd Monday of Feb
        _nth_weekday_of_month(year, 5, 0, -1),   # Memorial Day - last Monday of May
        _nth_weekday_of_month(year, 9, 0, 1),    # Labor Day - 1st Monday of Sep
        _nth_weekday_of_month(year, 10, 0, 2),   # Columbus Day - 2nd Monday of Oct
        _nth_weekday_of_month(year, 11, 3, 4),   # Thanksgiving - 4th Thursday of Nov
    ]
    return frozenset(_observed(d) for d in fixed) | frozenset(floating)


def is_business_day(d: date) -> bool:
    return d.weekday() < 5 and d not in federal_holidays(d.year)


def next_business_day(d: date, business_days_ahead: int = 1) -> date:
    """Advance d by business_days_ahead business days (does not count d itself)."""
    remaining = business_days_ahead
    cursor = d
    while remaining > 0:
        cursor += timedelta(days=1)
        if is_business_day(cursor):
            remaining -= 1
    return cursor


def business_days_between(start: date, end: date) -> int:
    """Count business days strictly between start (exclusive) and end (inclusive)."""
    if end <= start:
        return 0
    count = 0
    cursor = start
    while cursor < end:
        cursor += timedelta(days=1)
        if is_business_day(cursor):
            count += 1
    return count


def date_range(start: date, end: date):
    cursor = start
    while cursor <= end:
        yield cursor
        cursor += timedelta(days=1)
