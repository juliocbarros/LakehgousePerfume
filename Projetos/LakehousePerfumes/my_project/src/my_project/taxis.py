import databricks.sdk.runtime  # type: ignore[import-not-found]
from pyspark.sql import DataFrame  # type: ignore[import-not-found]


def find_all_taxis() -> DataFrame:
    """Find all taxi data."""
    return databricks.sdk.runtime.spark.read.table("samples.nyctaxi.trips")
