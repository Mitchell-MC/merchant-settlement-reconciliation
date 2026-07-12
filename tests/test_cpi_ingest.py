from cpi_ingest import _parse_response

SAMPLE_BODY = {
    "status": "REQUEST_SUCCEEDED",
    "Results": {
        "series": [
            {
                "seriesID": "CUUR0000SA0",
                "data": [
                    {
                        "year": "2026",
                        "period": "M02",
                        "periodName": "February",
                        "value": "315.123",
                        "footnotes": [{"code": ""}],
                    },
                    {
                        # Not-yet-released month: BLS uses "-" as a placeholder.
                        "year": "2026",
                        "period": "M03",
                        "periodName": "March",
                        "value": "-",
                        "footnotes": [{"code": ""}],
                    },
                ],
            },
            {
                "seriesID": "CUSR0000SA0",
                "data": [
                    {
                        "year": "2026",
                        "period": "M02",
                        "periodName": "February",
                        "value": "314.500",
                        "footnotes": [{"code": "R"}],
                    },
                ],
            },
        ]
    },
}


def test_parse_response_skips_unreleased_placeholder_values():
    df = _parse_response(SAMPLE_BODY)
    # Only 2 real data points should survive; the "-" placeholder is dropped,
    # not coerced to 0 or NaN.
    assert len(df) == 2
    assert not (df["value"] == 0).any()


def test_parse_response_maps_series_type():
    df = _parse_response(SAMPLE_BODY)
    types = set(df["series_type"])
    assert types == {"not_seasonally_adjusted", "seasonally_adjusted"}


def test_parse_response_parses_value_as_float():
    df = _parse_response(SAMPLE_BODY)
    row = df[df["series_id"] == "CUUR0000SA0"].iloc[0]
    assert row["value"] == 315.123


def test_parse_response_captures_footnote_codes():
    df = _parse_response(SAMPLE_BODY)
    row = df[df["series_id"] == "CUSR0000SA0"].iloc[0]
    assert row["footnote_codes"] == "R"
