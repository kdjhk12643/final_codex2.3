from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


DEFAULT_OUTPUT = Path("data/fuzhou_metro_dongjiekou_2025.csv")


def classify_time_slot(hour: int) -> str:
    if 7 <= hour < 9:
        return "morning_peak"
    if 17 <= hour < 19:
        return "evening_peak"
    if 9 <= hour < 17:
        return "daytime"
    if 19 <= hour < 23:
        return "night"
    return "late_night"


def classify_day_type(day_index: np.ndarray, day_of_week: np.ndarray) -> np.ndarray:
    day_mod = day_index % 10
    return np.select(
        [
            day_of_week >= 5,
            np.isin(day_mod, [2, 6]),
            np.isin(day_mod, [0, 9]),
        ],
        ["weekend_single", "weekday_high", "low_flow"],
        default="weekday_medium",
    )


def classify_season(month: np.ndarray) -> np.ndarray:
    return np.select(
        [
            np.isin(month, [6, 7, 8, 9]),
            np.isin(month, [12, 1, 2]),
        ],
        ["summer", "winter"],
        default="transition",
    )


def flow_profile(hour_float: np.ndarray, day_type: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    morning_peak = np.exp(-0.5 * ((hour_float - 8.0) / 0.82) ** 2)
    evening_peak = np.exp(-0.5 * ((hour_float - 18.0) / 0.92) ** 2)
    noon = np.exp(-0.5 * ((hour_float - 12.5) / 2.0) ** 2)
    weekend_leisure = np.exp(-0.5 * ((hour_float - 15.0) / 3.1) ** 2)
    daytime_plateau = 1 / (1 + np.exp(-(hour_float - 9.5) * 2.0)) * 1 / (1 + np.exp((hour_float - 17.0) * 2.0))
    low_day = np.exp(-0.5 * ((hour_float - 13.5) / 5.5) ** 2)

    high_entry = 30 + 620 * morning_peak + 420 * evening_peak + 125 * noon
    high_exit = 26 + 360 * morning_peak + 660 * evening_peak + 115 * noon

    medium_entry = 30 + 250 * daytime_plateau + 95 * noon
    medium_exit = 28 + 230 * daytime_plateau + 90 * noon

    weekend_entry = 34 + 110 * morning_peak + 390 * weekend_leisure + 160 * noon
    weekend_exit = 32 + 95 * morning_peak + 370 * weekend_leisure + 150 * noon

    low_entry = 18 + 75 * low_day + 35 * noon
    low_exit = 16 + 70 * low_day + 30 * noon

    entry = np.select(
        [day_type == "weekday_high", day_type == "weekday_medium", day_type == "weekend_single"],
        [high_entry, medium_entry, weekend_entry],
        default=low_entry,
    )
    exit_ = np.select(
        [day_type == "weekday_high", day_type == "weekday_medium", day_type == "weekend_single"],
        [high_exit, medium_exit, weekend_exit],
        default=low_exit,
    )

    closed_hours = (hour_float < 5.8) | (hour_float > 23.4)
    entry = np.where(closed_hours, entry * 0.08, entry)
    exit_ = np.where(closed_hours, exit_ * 0.08, exit_)

    return entry, exit_


def add_missing_values(
    data: pd.DataFrame,
    rng: np.random.Generator,
    missing_rate: float,
) -> pd.DataFrame:
    if missing_rate <= 0:
        return data

    result = data.copy()
    columns = ["entry_flow", "outdoor_temp", "platform_temp", "co2", "total_cooling_load_kw"]
    count = max(1, int(len(result) * missing_rate))
    for column in columns:
        indexes = rng.choice(result.index.to_numpy(), size=count, replace=False)
        result.loc[indexes, column] = np.nan
    return result


def generate_station_data(
    station: str = "Dongjiekou Station",
    line: str = "Fuzhou Metro Line 1/Line 4 Interchange",
    seed: int = 202507,
    missing_rate: float = 0.006,
) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    timestamps = pd.date_range("2025-01-01 00:00:00", "2025-12-31 23:45:00", freq="15min")
    data = pd.DataFrame({"timestamp": timestamps})

    data["station"] = station
    data["line"] = line
    data["is_weekend"] = data["timestamp"].dt.dayofweek >= 5
    data["hour"] = data["timestamp"].dt.hour
    data["time_slot"] = data["hour"].map(classify_time_slot)

    hour_float = data["timestamp"].dt.hour.to_numpy() + data["timestamp"].dt.minute.to_numpy() / 60
    day_index = data["timestamp"].dt.dayofyear.to_numpy()
    day_of_month = data["timestamp"].dt.day.to_numpy()
    month = data["timestamp"].dt.month.to_numpy()
    day_of_week = data["timestamp"].dt.dayofweek.to_numpy()
    day_type = classify_day_type(day_index, day_of_week)
    season = classify_season(month)
    data["day_type"] = day_type
    data["season"] = season

    entry_base, exit_base = flow_profile(hour_float, day_type)
    daily_factor = 1.0 + 0.035 * np.sin(2 * np.pi * (day_index - 1) / 7)
    season_flow_factor = np.select(
        [season == "summer", season == "transition", season == "winter"],
        [1.10, 0.95, 0.82],
        default=1.0,
    )
    event_factor = np.where(day_type == "weekday_high", 1.05, 1.0)
    entry_flow = rng.normal(entry_base * daily_factor * event_factor, 18).clip(0)
    exit_flow = rng.normal(exit_base * daily_factor * event_factor, 18).clip(0)
    entry_flow = entry_flow * season_flow_factor
    exit_flow = exit_flow * season_flow_factor

    data["entry_flow"] = np.rint(entry_flow).astype(int)
    data["exit_flow"] = np.rint(exit_flow).astype(int)
    rolling_people = pd.Series(data["entry_flow"] + data["exit_flow"]).rolling(4, min_periods=1).mean()
    stay_ratio = np.select(
        [day_type == "weekday_high", day_type == "weekday_medium", day_type == "weekend_single"],
        [0.40, 0.35, 0.38],
        default=0.30,
    )
    data["platform_passengers"] = np.rint((rolling_people * stay_ratio).clip(3)).astype(int)

    annual_temp = 24.2 + 8.7 * np.sin(2 * np.pi * (day_index - 105) / 365)
    day_type_temp = np.select(
        [day_type == "weekday_high", day_type == "weekday_medium", day_type == "weekend_single"],
        [0.9, 0.3, 0.6],
        default=-0.6,
    )
    diurnal_temp = annual_temp + day_type_temp + 4.1 * np.sin(2 * np.pi * (hour_float - 8) / 24)
    synoptic_temp = 1.1 * np.sin(2 * np.pi * (day_index - 3) / 11)
    outdoor_temp = rng.normal(diurnal_temp + synoptic_temp, 0.55)
    outdoor_rh = rng.normal(75 - 7 * np.sin(2 * np.pi * (hour_float - 9) / 24) + 4 * (season == "summer"), 3.0).clip(50, 98)
    daylight = np.sin(np.pi * (hour_float - 6) / 13).clip(0)
    solar_radiation = rng.normal(650 * daylight, 35).clip(0)

    data["outdoor_temp"] = outdoor_temp.round(2)
    data["outdoor_rh"] = outdoor_rh.round(2)
    data["solar_radiation"] = solar_radiation.round(2)

    passenger_effect = data["platform_passengers"].to_numpy() / 180
    running_people = pd.Series(data["platform_passengers"]).rolling(8, min_periods=1).mean().to_numpy()
    lagged_outdoor_temp = pd.Series(outdoor_temp).shift(1, fill_value=outdoor_temp[0]).to_numpy()
    platform_temp = 25.4 + 0.16 * (lagged_outdoor_temp - 30) + 0.34 * passenger_effect
    platform_rh = 64 + 0.18 * (outdoor_rh - 75) + 0.12 * passenger_effect
    co2 = 450 + 1.5 * running_people + 0.42 * data["entry_flow"].to_numpy() + rng.normal(0, 30, len(data))

    data["platform_temp"] = rng.normal(platform_temp, 0.28).round(2)
    data["platform_rh"] = rng.normal(platform_rh, 1.3).clip(50, 82).round(2)
    data["co2"] = co2.clip(420, 1350).round(1)

    people_load = 0.105 * data["platform_passengers"].to_numpy()
    fresh_air_load = (7.8 + 0.105 * data["entry_flow"].to_numpy()) * np.maximum(outdoor_temp - 24, 0) / 10
    envelope_load = 72 + 4.6 * np.maximum(outdoor_temp - 28, 0) + 0.014 * solar_radiation
    equipment_load = 48 + 0.012 * (data["entry_flow"].to_numpy() + data["exit_flow"].to_numpy())

    morning_peak = np.exp(-0.5 * ((hour_float - 8.0) / 0.82) ** 2)
    evening_peak = np.exp(-0.5 * ((hour_float - 18.0) / 0.92) ** 2)
    daytime_plateau = 1 / (1 + np.exp(-(hour_float - 9.5) * 2.0)) * 1 / (1 + np.exp((hour_float - 17.0) * 2.0))
    weekend_leisure = np.exp(-0.5 * ((hour_float - 15.0) / 3.1) ** 2)
    low_day = np.exp(-0.5 * ((hour_float - 13.5) / 5.5) ** 2)
    operation_shape = np.select(
        [day_type == "weekday_high", day_type == "weekday_medium", day_type == "weekend_single"],
        [
            0.90 + 0.30 * morning_peak + 0.30 * evening_peak,
            0.88 + 0.24 * daytime_plateau,
            0.88 + 0.34 * weekend_leisure,
        ],
        default=0.86 + 0.06 * low_day,
    )

    type_load_factor = np.select(
        [day_type == "weekday_high", day_type == "weekday_medium", day_type == "weekend_single"],
        [1.13, 1.00, 1.04],
        default=0.82,
    )
    season_load_factor = np.select(
        [season == "summer", season == "transition", season == "winter"],
        [1.04, 0.98, 0.90],
        default=1.0,
    )
    latent_internal = type_load_factor * (
        1.02
        + 0.12 * np.sin(2 * np.pi * (hour_float - 6) / 24)
        + 0.055 * np.cos(2 * np.pi * day_of_month / 11)
    )
    total_load = (people_load + fresh_air_load + envelope_load + equipment_load) * latent_internal * operation_shape * season_load_factor
    total_load = total_load + rng.normal(0, 10.0, len(data))

    load_change = pd.Series(total_load).diff().fillna(0).to_numpy()
    control_load = pd.Series(total_load).rolling(4, min_periods=1).mean().shift(1, fill_value=total_load[0]).to_numpy()
    chiller_stage = np.select([control_load < 130, control_load < 205, control_load < 270], [1, 2, 3], default=4)
    part_load_penalty = 1.0 + 0.045 * (chiller_stage - 1)
    chiller_load = control_load * 0.88 * part_load_penalty + 4.5 * chiller_stage + rng.normal(0, 10.5, len(data))
    fan_power = 16.5 + 0.012 * data["platform_passengers"].to_numpy() + 0.009 * data["entry_flow"].to_numpy() + 0.08 * np.maximum(load_change, 0)
    pump_power = 11.5 + 0.031 * total_load + 0.08 * np.maximum(load_change, 0) + rng.normal(0, 1.2, len(data))

    data["people_load_kw"] = people_load.round(2)
    data["fresh_air_load_kw"] = fresh_air_load.round(2)
    data["envelope_load_kw"] = envelope_load.round(2)
    data["equipment_load_kw"] = equipment_load.round(2)
    data["total_cooling_load_kw"] = total_load.round(2)
    data["chiller_load_kw"] = chiller_load.round(2)
    data["fan_power_kw"] = fan_power.round(2)
    data["pump_power_kw"] = pump_power.round(2)

    return add_missing_values(data, rng, missing_rate)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate synthetic full-year 2025 Fuzhou Metro station data for HVAC load research."
    )
    parser.add_argument("--station", default="Dongjiekou Station", help="Station name.")
    parser.add_argument("--line", default="Fuzhou Metro Line 1/Line 4 Interchange", help="Metro line description.")
    parser.add_argument("--seed", type=int, default=202507, help="Random seed for reproducible data.")
    parser.add_argument("--missing-rate", type=float, default=0.006, help="Missing ratio per selected column.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Output CSV path.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    data = generate_station_data(
        station=args.station,
        line=args.line,
        seed=args.seed,
        missing_rate=args.missing_rate,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(args.output, index=False, encoding="utf-8-sig")
    print(f"Wrote {len(data)} rows to {args.output}")


if __name__ == "__main__":
    main()
