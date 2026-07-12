from cbp_ingest import _is_target_sector_row


def test_two_digit_sector_row_matches():
    assert _is_target_sector_row("11----", 2)
    assert _is_target_sector_row("44----", 2)


def test_six_digit_detail_row_does_not_match_two_digit_filter():
    assert not _is_target_sector_row("111120", 2)


def test_three_digit_row_does_not_match_two_digit_filter():
    assert not _is_target_sector_row("221---", 2)


def test_naics_total_row_does_not_match_two_digit_filter():
    # "------" is the all-industries county total, not a sector -- must be
    # excluded so it isn't double-counted alongside real 2-digit sectors.
    assert not _is_target_sector_row("------", 2)


def test_digits_parameter_controls_grain():
    assert _is_target_sector_row("221---", 3)
    assert not _is_target_sector_row("221---", 2)
