from datetime import date, timedelta

from calendar_utils import (
    business_days_between,
    federal_holidays,
    is_business_day,
    next_business_day,
)

FIXED_HOLIDAYS = [
    (1, 1),   # New Year's Day
    (6, 19),  # Juneteenth
    (7, 4),   # Independence Day
    (11, 11), # Veterans Day
    (12, 25), # Christmas Day
]


def test_fixed_holidays_present_or_observed_across_years():
    # A fixed holiday either lands on the calendar date itself, or -- if that
    # date falls on a weekend -- on its Fed-observed weekday shift (Sat -> Fri,
    # Sun -> Mon). Exactly one of the two must be true, every year.
    for year in range(2020, 2035):
        holidays = federal_holidays(year)
        for month, day in FIXED_HOLIDAYS:
            d = date(year, month, day)
            if d.weekday() == 5:  # Saturday
                assert d - timedelta(days=1) in holidays
                assert d not in holidays
            elif d.weekday() == 6:  # Sunday
                assert d + timedelta(days=1) in holidays
                assert d not in holidays
            else:
                assert d in holidays


def test_floating_holidays_land_on_expected_weekday():
    for year in range(2020, 2035):
        holidays = federal_holidays(year)
        mlk = [d for d in holidays if d.year == year and d.month == 1 and 15 <= d.day <= 21]
        assert len(mlk) == 1 and mlk[0].weekday() == 0  # 3rd Monday of Jan

        thanksgiving = [d for d in holidays if d.month == 11 and 22 <= d.day <= 28]
        assert len(thanksgiving) == 1 and thanksgiving[0].weekday() == 3  # 4th Thursday of Nov

        memorial_day = [d for d in holidays if d.month == 5 and d.day >= 25]
        assert len(memorial_day) == 1 and memorial_day[0].weekday() == 0  # last Monday of May


def test_holiday_count_is_stable():
    # 5 fixed + 6 floating federal holidays every year, regardless of how the
    # Sat/Sun observed-shift lands (it moves the date, not the count).
    for year in range(2020, 2035):
        assert len(federal_holidays(year)) == 11


def test_is_business_day_excludes_weekends():
    saturday = date(2026, 7, 11)
    sunday = date(2026, 7, 12)
    assert saturday.weekday() == 5
    assert not is_business_day(saturday)
    assert not is_business_day(sunday)


def test_is_business_day_excludes_holidays():
    new_years_2026 = date(2026, 1, 1)
    assert new_years_2026.weekday() < 5  # Thursday, not weekend-shifted
    assert not is_business_day(new_years_2026)


def test_next_business_day_skips_weekend():
    friday = date(2026, 7, 10)
    assert friday.weekday() == 4
    result = next_business_day(friday, 1)
    assert result == date(2026, 7, 13)  # Monday
    assert is_business_day(result)


def test_next_business_day_does_not_count_start_day():
    a_monday = date(2026, 7, 13)
    assert is_business_day(a_monday)
    result = next_business_day(a_monday, 0)
    assert result == a_monday


def test_business_days_between_same_day_is_zero():
    d = date(2026, 3, 2)
    assert business_days_between(d, d) == 0


def test_business_days_between_matches_next_business_day():
    start = date(2026, 3, 2)
    for n in (1, 2, 5):
        end = next_business_day(start, n)
        assert business_days_between(start, end) == n


def test_business_days_between_end_before_start_is_zero():
    assert business_days_between(date(2026, 3, 10), date(2026, 3, 1)) == 0
