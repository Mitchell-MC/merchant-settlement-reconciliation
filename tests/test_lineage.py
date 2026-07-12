import pandas as pd

from common.lineage import add_lineage, write_landed_parquet


def _sample_df() -> pd.DataFrame:
    return pd.DataFrame({"a": [1, 2, 3], "b": ["x", "y", "z"]})


def test_add_lineage_adds_expected_columns():
    landed = add_lineage(_sample_df(), source_system="unit_test", run_id="run-123")
    for col in ("_row_hash", "_source_system", "_ingestion_timestamp", "_batch_id"):
        assert col in landed.columns
    assert (landed["_source_system"] == "unit_test").all()
    assert (landed["_batch_id"] == "run-123").all()


def test_add_lineage_does_not_mutate_input():
    original = _sample_df()
    add_lineage(original, source_system="unit_test", run_id="run-123")
    assert list(original.columns) == ["a", "b"]


def test_row_hash_is_deterministic_for_identical_content():
    df1 = _sample_df()
    df2 = _sample_df()
    hash1 = add_lineage(df1, "s", "r1")["_row_hash"]
    hash2 = add_lineage(df2, "s", "r2")["_row_hash"]
    # Same row content -> same hash, independent of source_system/run_id
    # (those aren't part of the hashed frame).
    assert list(hash1) == list(hash2)


def test_row_hash_differs_for_different_content():
    df_a = pd.DataFrame({"a": [1], "b": ["x"]})
    df_b = pd.DataFrame({"a": [2], "b": ["x"]})
    hash_a = add_lineage(df_a, "s", "r")["_row_hash"].iloc[0]
    hash_b = add_lineage(df_b, "s", "r")["_row_hash"].iloc[0]
    assert hash_a != hash_b


def test_write_landed_parquet_round_trips(tmp_path):
    landed = add_lineage(_sample_df(), "unit_test", "run-123")
    out_path = write_landed_parquet(landed, str(tmp_path), "my_table")

    assert out_path == str(tmp_path / "my_table" / "my_table.parquet")
    reloaded = pd.read_parquet(out_path)
    assert list(reloaded["a"]) == [1, 2, 3]
    assert list(reloaded["_source_system"]) == ["unit_test"] * 3
