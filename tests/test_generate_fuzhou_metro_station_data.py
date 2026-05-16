import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "generate_fuzhou_metro_station_data.py"


def load_generator_module():
    spec = importlib.util.spec_from_file_location("generator", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_generates_full_july_2025_quarter_hour_dataset():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507)

    assert len(data) == 31 * 24 * 4
    assert str(data["timestamp"].iloc[0]) == "2025-07-01 00:00:00"
    assert str(data["timestamp"].iloc[-1]) == "2025-07-31 23:45:00"
    assert data["timestamp"].diff().dropna().dt.total_seconds().eq(15 * 60).all()


def test_dataset_contains_research_features_and_load_balance():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507, missing_rate=0)

    expected_columns = {
        "timestamp",
        "station",
        "line",
        "is_weekend",
        "hour",
        "time_slot",
        "entry_flow",
        "exit_flow",
        "platform_passengers",
        "outdoor_temp",
        "outdoor_rh",
        "solar_radiation",
        "platform_temp",
        "platform_rh",
        "co2",
        "people_load_kw",
        "fresh_air_load_kw",
        "envelope_load_kw",
        "equipment_load_kw",
        "chiller_load_kw",
        "fan_power_kw",
        "pump_power_kw",
        "total_cooling_load_kw",
    }
    assert expected_columns.issubset(set(data.columns))

    component_sum = (
        data["people_load_kw"]
        + data["fresh_air_load_kw"]
        + data["envelope_load_kw"]
        + data["equipment_load_kw"]
    ).round(2)
    relative_gap = ((data["total_cooling_load_kw"] - component_sum).abs() / data["total_cooling_load_kw"]).mean()

    assert relative_gap < 0.22
    assert not component_sum.equals(data["total_cooling_load_kw"].round(2))
    assert data["pump_power_kw"].corr(data["total_cooling_load_kw"]) < 0.98
    assert data["chiller_load_kw"].corr(data["total_cooling_load_kw"]) < 0.98
    assert data["entry_flow"].ge(0).all()
    assert data["exit_flow"].ge(0).all()


def test_default_dataset_includes_missing_values_for_preprocessing_demo():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507)
    missing_columns = ["entry_flow", "outdoor_temp", "platform_temp", "co2", "total_cooling_load_kw"]

    assert data[missing_columns].isna().sum().sum() > 0
