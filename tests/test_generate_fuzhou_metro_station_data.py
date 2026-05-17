import importlib.util
from pathlib import Path
import re


MODULE_PATH = Path(__file__).resolve().parents[1] / "generate_fuzhou_metro_station_data.py"


def load_generator_module():
    spec = importlib.util.spec_from_file_location("generator", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_generates_full_2025_quarter_hour_dataset():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507)

    assert len(data) == 365 * 24 * 4
    assert str(data["timestamp"].iloc[0]) == "2025-01-01 00:00:00"
    assert str(data["timestamp"].iloc[-1]) == "2025-12-31 23:45:00"
    assert data["timestamp"].diff().dropna().dt.total_seconds().eq(15 * 60).all()
    assert generator.DEFAULT_OUTPUT == Path("data/fuzhou_metro_dongjiekou_2025.csv")


def test_full_year_dataset_contains_seasonal_load_structure():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507, missing_rate=0)

    assert "season" in data.columns
    assert set(data["season"]) == {"winter", "transition", "summer"}

    monthly_load = data.groupby(data["timestamp"].dt.month)["total_cooling_load_kw"].mean()
    assert monthly_load.loc[7] > monthly_load.loc[4] * 1.25
    assert monthly_load.loc[7] > monthly_load.loc[1] * 1.45


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


def test_day_type_profiles_are_separated_for_four_mode_clustering():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507, missing_rate=0)
    hourly = data.groupby(["day_type", data["timestamp"].dt.hour])["total_cooling_load_kw"].mean().unstack()
    daily_mean = data.groupby("day_type")["total_cooling_load_kw"].mean()

    assert set(daily_mean.index) == {"weekday_high", "weekday_medium", "weekend_single", "low_flow"}
    assert daily_mean["weekday_high"] > daily_mean["weekend_single"] * 1.08
    assert daily_mean["weekend_single"] > daily_mean["weekday_medium"] * 1.05
    assert daily_mean["weekday_medium"] > daily_mean["low_flow"] * 1.35

    assert hourly.loc["weekday_high", 8] > hourly.loc["weekday_high", 15] * 1.45
    assert hourly.loc["weekday_high", 18] > hourly.loc["weekday_high", 15] * 1.35
    assert hourly.loc["weekend_single", 15] > hourly.loc["weekend_single", 8] * 1.55
    assert hourly.loc["weekday_medium", 12] > hourly.loc["weekday_medium", 8] * 1.45
    assert hourly.loc["low_flow"].max() < hourly.loc["weekday_medium"].max() * 0.68


def test_default_dataset_includes_missing_values_for_preprocessing_demo():
    generator = load_generator_module()

    data = generator.generate_station_data(seed=202507)
    missing_columns = ["entry_flow", "outdoor_temp", "platform_temp", "co2", "total_cooling_load_kw"]

    assert data[missing_columns].isna().sum().sum() > 0


def test_forbidden_result_overrides_are_removed_from_matlab_pipeline():
    root = Path(__file__).resolve().parents[1]
    step3 = read_text(root / "step3_load_prediction.m")
    step4 = read_text(root / "step4_capacity_optimization.m")
    step2 = read_text(root / "step2_analysis_cluster.m")

    assert "alignPredictionMetricsToTarget" not in step3
    assert "Keep the reported synthetic benchmark" not in step3
    assert "lstm.RMSE = min(max(lstm.RMSE" not in step3
    assert "bp.RMSE = min(max(bp.RMSE" not in step3
    assert "redundancyRate(2) = cfg.targetOptimizedRedundancyRate" not in step4
    assert "lifecycleCost(2) = lifecycleCost(1) * (1 - cfg.targetCostReductionRate)" not in step4
    assert "energySavingRate(2) = cfg.targetEnergySavingRate" not in step4
    assert "meanSilhouette(preferredIdx) = min(max(meanSilhouette(preferredIdx), 0.65), 0.70)" not in step2
    assert "bestIdx = preferredIdx" not in step2


def test_config_targets_are_set_for_natural_optimization():
    root = Path(__file__).resolve().parents[1]
    config = read_text(root / "config.m")

    expected_snippets = [
        "cfg.baselineRedundancyRate = 0.28;",
        "cfg.loadLagSteps = [1, 4, 8, 96];",
        "cfg.topFeatureNum = 10;",
        "cfg.clusterKRange = 2:4;",
        "cfg.normalizeDailyClusterCurves = false;",
        "cfg.chillerSafetyFactor = 1.09;",
        "cfg.fanSafetyFactor = 1.07;",
        "cfg.pumpSafetyFactor = 1.07;",
        "cfg.ahuSafetyFactor = 1.05;",
        "cfg.topsisWeights = [0.55, 0.45];",
        "cfg.designConfidenceLevel = 0.90;",
        "cfg.extremeConfidenceLevel = 0.99;",
        "cfg.sequenceLength = 16;",
        "cfg.miniBatchSize = 32;",
        "cfg.maxEpochs = 120;",
        "cfg.validationPatience = 50;",
    ]
    for snippet in expected_snippets:
        assert snippet in config

    assert re.search(r"cfg\.preferredClusterK\s*=\s*4;", config)
