from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


DEFAULT_OUTPUT = Path("data/fuzhou_metro_dongjiekou_2025_07.csv")


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


def flow_profile(hour_float: np.ndarray, is_weekend: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    morning_peak = np.exp(-0.5 * ((hour_float - 8.0) / 0.85) ** 2)
    evening_peak = np.exp(-0.5 * ((hour_float - 18.0) / 0.95) ** 2)
    noon = np.exp(-0.5 * ((hour_float - 12.5) / 2.0) ** 2)
    weekend_leisure = np.exp(-0.5 * ((hour_float - 15.0) / 3.2) ** 2)

    entry = 28 + 520 * morning_peak + 360 * evening_peak + 150 * noon
    exit_ = 24 + 310 * morning_peak + 560 * evening_peak + 140 * noon

    entry = np.where(is_weekend, 35 + 250 * weekend_leisure + 170 * noon, entry)
    exit_ = np.where(is_weekend, 32 + 240 * weekend_leisure + 160 * noon, exit_)

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
    station: str = "东街口站",
    line: str = "福州地铁1号线/4号线换乘站",
    seed: int = 202507,
    missing_rate: float = 0.006,
) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    timestamps = pd.date_range("2025-07-01 00:00:00", "2025-07-31 23:45:00", freq="15min")
    data = pd.DataFrame({"timestamp": timestamps})

    data["station"] = station
    data["line"] = line
    data["is_weekend"] = data["timestamp"].dt.dayofweek >= 5
    data["hour"] = data["timestamp"].dt.hour
    data["time_slot"] = data["hour"].map(classify_time_slot)

    hour_float = data["timestamp"].dt.hour.to_numpy() + data["timestamp"].dt.minute.to_numpy() / 60
    day_index = data["timestamp"].dt.day.to_numpy()
    is_weekend = data["is_weekend"].to_numpy()

    entry_base, exit_base = flow_profile(hour_float, is_weekend)
    holiday_wave = 1.0 + 0.05 * np.sin(2 * np.pi * (day_index - 2) / 13)
    daily_factor = 1.0 + 0.08 * np.sin(2 * np.pi * (day_index - 1) / 7)
    weather_flow_adjustment = 1.0 + 0.012 * np.maximum(35 - np.abs(31 - (30.2 + 4.6 * np.sin(2 * np.pi * (hour_float - 8) / 24))), 0)
    entry_flow = rng.normal(entry_base * daily_factor * holiday_wave * weather_flow_adjustment, 26).clip(0)
    exit_flow = rng.normal(exit_base * daily_factor * holiday_wave * weather_flow_adjustment, 26).clip(0)

    data["entry_flow"] = np.rint(entry_flow).astype(int)
    data["exit_flow"] = np.rint(exit_flow).astype(int)
    rolling_people = pd.Series(data["entry_flow"] + data["exit_flow"]).rolling(4, min_periods=1).mean()
    data["platform_passengers"] = np.rint((rolling_people * rng.uniform(0.28, 0.42, len(data))).clip(3)).astype(int)

    diurnal_temp = 30.2 + 4.6 * np.sin(2 * np.pi * (hour_float - 8) / 24)
    synoptic_temp = 1.1 * np.sin(2 * np.pi * (day_index - 3) / 9)
    outdoor_temp = rng.normal(diurnal_temp + synoptic_temp, 0.55)
    outdoor_rh = rng.normal(76 - 9 * np.sin(2 * np.pi * (hour_float - 9) / 24), 3.0).clip(55, 96)
    daylight = np.sin(np.pi * (hour_float - 6) / 13).clip(0)
    solar_radiation = rng.normal(690 * daylight, 30).clip(0)

    data["outdoor_temp"] = outdoor_temp.round(2)
    data["outdoor_rh"] = outdoor_rh.round(2)
    data["solar_radiation"] = solar_radiation.round(2)

    passenger_effect = data["platform_passengers"].to_numpy() / 180
    running_mean_passengers = pd.Series(data["platform_passengers"]).rolling(8, min_periods=1).mean().to_numpy()
    lagged_outdoor_temp = pd.Series(outdoor_temp).shift(1, fill_value=outdoor_temp[0]).to_numpy()
    platform_temp = 25.4 + 0.16 * (lagged_outdoor_temp - 30) + 0.34 * passenger_effect + 0.05 * np.sin(2 * np.pi * hour_float / 24)
    platform_rh = 64 + 0.18 * (outdoor_rh - 75) + 0.12 * passenger_effect - 0.04 * np.cos(2 * np.pi * hour_float / 24)
    co2 = 450 + 1.55 * running_mean_passengers + 0.45 * data["entry_flow"].to_numpy() + rng.normal(0, 28, len(data))

    data["platform_temp"] = rng.normal(platform_temp, 0.25).round(2)
    data["platform_rh"] = rng.normal(platform_rh, 1.2).clip(50, 82).round(2)
    data["co2"] = co2.clip(420, 1350).round(1)

    people_load = 0.105 * data["platform_passengers"].to_numpy()
    fresh_air_load = (7.8 + 0.11 * data["entry_flow"].to_numpy()) * np.maximum(outdoor_temp - 24, 0) / 10
    envelope_load = 52 + 4.8 * np.maximum(outdoor_temp - 28, 0) + 0.014 * solar_radiation
    equipment_load = 38 + 0.012 * (data["entry_flow"].to_numpy() + data["exit_flow"].to_numpy())

    latent_internal = 1.05 + 0.18 * np.sin(2 * np.pi * (hour_float - 6) / 24) + 0.12 * np.cos(2 * np.pi * day_index / 11)
    total_load = (
        people_load
        + fresh_air_load
        + envelope_load
        + equipment_load
    ) * latent_internal
    total_load = total_load + rng.normal(0, 4.5, len(data))

    load_change = pd.Series(total_load).diff().fillna(0).to_numpy()
    control_load = pd.Series(total_load).rolling(4, min_periods=1).mean().shift(1, fill_value=total_load[0]).to_numpy()
    chiller_stage = np.select(
        [control_load < 130, control_load < 205, control_load < 270],
        [1, 2, 3],
        default=4,
    )
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
        description="Generate synthetic July 2025 Fuzhou Metro station data for HVAC load research."
    )
    parser.add_argument("--station", default="东街口站", help="Station name.")
    parser.add_argument("--line", default="福州地铁1号线/4号线换乘站", help="Metro line description.")
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
