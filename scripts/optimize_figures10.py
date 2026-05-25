from __future__ import annotations

import math
import re
import zipfile
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from docx import Document
from docx.shared import Inches
from matplotlib import font_manager
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle
from matplotlib.ticker import FuncFormatter, MaxNLocator
from PIL import Image, ImageDraw


ROOT = Path.cwd()
TABLE_DIR = ROOT / "output" / "tables"
DATA_DIR = ROOT / "data"
FIG_DIR = ROOT / "output" / "draft10_figures"
INPUT_DOCX_PATTERN = "*09*.docx"
OUTPUT_DOCX = ROOT / "毕业设计论文初稿10_图片优化修订稿.docx"


TARGET_DIMS_IN = [
    (5.90, 2.08),  # 图1-1
    (5.55, 2.20),  # 图2-1
    (5.45, 3.60),  # 图3-1
    (5.50, 3.20),  # 图3-2
    (5.50, 3.40),  # 图3-3
    (5.30, 3.35),  # 图3-4
    (5.60, 3.45),  # 图3-5
    (5.60, 1.25),  # 图4-1
    (5.90, 1.75),  # 图4-2
    (5.60, 1.65),  # 图4-3
    (5.70, 3.45),  # 图4-4
    (5.70, 3.45),  # 图4-5
    (5.20, 3.25),  # 图4-6
    (5.80, 1.85),  # 图5-1
    (5.30, 3.55),  # 图5-2
    (5.20, 3.05),  # 图6-1
]


PAL = {
    "blue": "#2563A7",
    "blue2": "#4C9BD6",
    "sky": "#DCECF9",
    "green": "#2F8F67",
    "green2": "#66B77B",
    "mint": "#E2F3EA",
    "orange": "#E28A2E",
    "orange2": "#F4B261",
    "red": "#C2412E",
    "purple": "#6D5FD0",
    "slate": "#334155",
    "gray": "#64748B",
    "light": "#F6F8FB",
    "line": "#CBD5E1",
    "dark": "#1F2937",
}


def setup_matplotlib() -> None:
    font_candidates = [
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
        Path("C:/Windows/Fonts/simsun.ttc"),
    ]
    font_name = "DejaVu Sans"
    for font_path in font_candidates:
        if font_path.exists():
            font_manager.fontManager.addfont(str(font_path))
            font_name = font_manager.FontProperties(fname=str(font_path)).get_name()
            break

    plt.rcParams.update(
        {
            "font.sans-serif": [font_name, "Microsoft YaHei", "SimHei", "DejaVu Sans"],
            "axes.unicode_minus": False,
            "font.size": 9,
            "axes.titlesize": 10,
            "axes.labelsize": 9,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
            "legend.fontsize": 8,
            "figure.dpi": 150,
            "savefig.dpi": 300,
            "axes.edgecolor": "#64748B",
            "axes.linewidth": 0.8,
            "grid.color": "#E2E8F0",
            "grid.linewidth": 0.7,
            "lines.linewidth": 1.5,
        }
    )


def read_table(name: str) -> pd.DataFrame:
    return pd.read_csv(TABLE_DIR / name, encoding="utf-8-sig")


def new_axes(idx: int, frame: bool = False):
    width, height = TARGET_DIMS_IN[idx - 1]
    fig, ax = plt.subplots(figsize=(width, height))
    fig.patch.set_facecolor("white")
    if not frame:
        ax.set_axis_off()
    return fig, ax


def save_chart(fig, out_path: Path, tight: bool = True) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if tight:
        fig.tight_layout(pad=0.55)
    fig.savefig(out_path, facecolor="white")
    plt.close(fig)


def save_diagram(fig, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)
    fig.savefig(out_path, facecolor="white")
    plt.close(fig)


def add_box(
    ax,
    x: float,
    y: float,
    w: float,
    h: float,
    title: str,
    body: str = "",
    fc: str = "#F8FAFC",
    ec: str = "#2563A7",
    title_color: str = PAL["dark"],
    lw: float = 1.2,
    round_size: float = 0.03,
    title_size: float = 9,
    body_size: float = 7.2,
):
    patch = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle=f"round,pad=0.015,rounding_size={round_size}",
        linewidth=lw,
        edgecolor=ec,
        facecolor=fc,
    )
    ax.add_patch(patch)
    if body:
        ax.text(x + w / 2, y + h * 0.64, title, ha="center", va="center", fontsize=title_size, weight="bold", color=title_color)
        ax.text(x + w / 2, y + h * 0.35, body, ha="center", va="center", fontsize=body_size, color=PAL["slate"], linespacing=1.25)
    else:
        ax.text(x + w / 2, y + h / 2, title, ha="center", va="center", fontsize=title_size, weight="bold", color=title_color)
    return patch


def add_arrow(ax, start, end, color: str = PAL["gray"], lw: float = 1.2, ms: int = 10, rad: float = 0.0):
    arrow = FancyArrowPatch(
        start,
        end,
        arrowstyle="-|>",
        mutation_scale=ms,
        linewidth=lw,
        color=color,
        connectionstyle=f"arc3,rad={rad}",
        shrinkA=2,
        shrinkB=2,
    )
    ax.add_patch(arrow)
    return arrow


def figure_1_1(out_path: Path) -> None:
    fig, ax = new_axes(1)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)

    ax.text(0.03, 0.93, "研究技术路线", fontsize=10, weight="bold", color=PAL["dark"], ha="left", va="center")
    ax.plot([0.03, 0.97], [0.88, 0.88], color=PAL["line"], lw=0.9)

    top = [
        ("数据获取与预处理", "15 min 数据\n缺失/异常处理"),
        ("负荷特性分析", "Pearson 筛选\n分项负荷分解"),
        ("典型日聚类", "K-Means\nK=4 模式识别"),
        ("负荷预测", "LSTM 与 BP\n精度对比"),
    ]
    bottom = [
        ("设计负荷转换", "P95/P99\n误差裕量校核"),
        ("容量多目标优化", "NSGA-II\n成本-冗余目标"),
        ("方案评价输出", "TOPSIS 排序\n工程约束校核"),
    ]

    xs = [0.035, 0.275, 0.515, 0.755]
    for i, (title, body) in enumerate(top):
        add_box(ax, xs[i], 0.56, 0.19, 0.22, title, body, fc="#EAF3FB", ec=PAL["blue"], title_size=8.4)
        ax.text(xs[i] + 0.013, 0.74, f"{i + 1}", color="white", fontsize=7, weight="bold", ha="center", va="center",
                bbox=dict(boxstyle="circle,pad=0.14", fc=PAL["blue"], ec=PAL["blue"]))
        if i < len(top) - 1:
            add_arrow(ax, (xs[i] + 0.19, 0.67), (xs[i + 1], 0.67), PAL["blue"])

    add_arrow(ax, (0.85, 0.56), (0.30, 0.41), PAL["gray"], rad=0.18)

    bx = [0.20, 0.43, 0.66]
    for i, (title, body) in enumerate(bottom):
        add_box(ax, bx[i], 0.16, 0.20, 0.22, title, body, fc="#EAF7EF", ec=PAL["green"], title_size=8.4)
        ax.text(bx[i] + 0.013, 0.34, f"{i + 5}", color="white", fontsize=7, weight="bold", ha="center", va="center",
                bbox=dict(boxstyle="circle,pad=0.14", fc=PAL["green"], ec=PAL["green"]))
        if i < len(bottom) - 1:
            add_arrow(ax, (bx[i] + 0.20, 0.27), (bx[i + 1], 0.27), PAL["green"])

    ax.text(0.03, 0.055, "逻辑关系：先识别负荷形成规律，再建立预测模型，最后将预测负荷转化为容量配置边界。", fontsize=7.5, color=PAL["gray"], ha="left")
    save_diagram(fig, out_path)


def figure_2_1(out_path: Path) -> None:
    fig, ax = new_axes(2)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)

    ax.text(0.03, 0.92, "地铁车站通风空调系统组成", fontsize=10, weight="bold", color=PAL["dark"], ha="left", va="center")
    ax.plot([0.03, 0.97], [0.86, 0.86], color=PAL["line"], lw=0.9)

    add_box(ax, 0.05, 0.54, 0.16, 0.20, "冷水机组", "提供冷冻水", fc="#EAF3FB", ec=PAL["blue"], title_size=8.5)
    add_box(ax, 0.26, 0.54, 0.16, 0.20, "冷冻水泵", "输送冷量", fc="#EAF3FB", ec=PAL["blue"], title_size=8.5)
    add_box(ax, 0.47, 0.54, 0.18, 0.20, "空气处理机组", "表冷器/过滤/加湿", fc="#EAF3FB", ec=PAL["blue"], title_size=8.5)
    add_box(ax, 0.72, 0.54, 0.20, 0.20, "站台区域", "人员、设备、围护结构\n形成空调负荷", fc="#FFF3E6", ec=PAL["orange"], title_size=8.5)

    add_box(ax, 0.09, 0.17, 0.20, 0.17, "冷却水与冷却塔", "排出冷凝热", fc="#F1F5F9", ec=PAL["gray"], title_size=8.0)
    add_box(ax, 0.39, 0.17, 0.18, 0.17, "送风机/风道", "送风至站台", fc="#EAF7EF", ec=PAL["green"], title_size=8.0)
    add_box(ax, 0.68, 0.17, 0.22, 0.17, "回风/排风系统", "回风再处理\n余热余湿排出", fc="#EAF7EF", ec=PAL["green"], title_size=8.0)

    add_arrow(ax, (0.21, 0.64), (0.26, 0.64), PAL["blue"])
    add_arrow(ax, (0.42, 0.64), (0.47, 0.64), PAL["blue"])
    add_arrow(ax, (0.65, 0.64), (0.72, 0.64), PAL["green"])
    add_arrow(ax, (0.48, 0.54), (0.48, 0.34), PAL["green"])
    add_arrow(ax, (0.57, 0.25), (0.68, 0.25), PAL["green"])
    add_arrow(ax, (0.72, 0.26), (0.57, 0.55), PAL["green"], rad=-0.15)
    add_arrow(ax, (0.18, 0.54), (0.18, 0.34), PAL["gray"])
    add_arrow(ax, (0.29, 0.25), (0.47, 0.55), PAL["blue"], rad=-0.12)

    ax.plot([0.05, 0.43], [0.47, 0.47], color=PAL["blue"], lw=2.0)
    ax.text(0.24, 0.43, "冷冻水/冷却水回路", color=PAL["blue"], fontsize=7.4, ha="center")
    ax.plot([0.48, 0.90], [0.45, 0.45], color=PAL["green"], lw=2.0)
    ax.text(0.69, 0.41, "送风-回风-排风回路", color=PAL["green"], fontsize=7.4, ha="center")
    save_diagram(fig, out_path)


def figure_3_1(out_path: Path) -> None:
    df = read_table("step1_clean_data.csv")
    df["时间"] = pd.to_datetime(df["时间"])
    ts = df.set_index("时间")["总冷负荷_kW"].sort_index()
    daily = ts.resample("D").mean()
    roll = daily.rolling(7, center=True, min_periods=1).mean()
    p95, p99 = ts.quantile([0.95, 0.99])

    fig, ax = new_axes(3, frame=True)
    ax.plot(daily.index, daily.values, color="#9CC7E6", lw=1.0, label="日均负荷")
    ax.plot(roll.index, roll.values, color=PAL["blue"], lw=1.8, label="7日滑动平均")
    ax.axhline(p95, color=PAL["orange"], ls="--", lw=1.1, label=f"P95={p95:.1f} kW")
    ax.axhline(p99, color=PAL["red"], ls="--", lw=1.1, label=f"P99={p99:.1f} kW")
    ax.set_title("站台总冷负荷全年变化")
    ax.set_ylabel("总冷负荷 / kW")
    ax.set_xlabel("月份")
    ax.grid(True, axis="y")
    ax.legend(loc="upper left", ncol=2, frameon=False)
    ax.xaxis.set_major_locator(mdates.MonthLocator(interval=1))
    ax.xaxis.set_major_formatter(FuncFormatter(lambda x, pos: f"{mdates.num2date(x).month}月"))
    ax.set_ylim(0, max(ts.quantile(0.995) * 1.08, 350))
    save_chart(fig, out_path)


def figure_3_2(out_path: Path) -> None:
    raw_path = next(DATA_DIR.glob("fuzhou_metro_dongjiekou_2025.csv"))
    df = pd.read_csv(raw_path, encoding="utf-8-sig")
    name_map = {
        "entry_flow": "进站客流",
        "total_cooling_load_kw": "总冷负荷",
        "co2": "CO2浓度",
        "platform_temp": "站台温度",
        "outdoor_temp": "室外温度",
    }
    missing = df[list(name_map)].isna().sum().rename(index=name_map).sort_values()
    rate = missing / len(df) * 100

    fig, ax = new_axes(4, frame=True)
    y = np.arange(len(missing))
    ax.barh(y, missing.values, color=PAL["blue2"], height=0.55)
    for i, (cnt, pct) in enumerate(zip(missing.values, rate.values)):
        ax.text(cnt + 3, i, f"{cnt} 条（{pct:.2f}%）", va="center", fontsize=8, color=PAL["dark"])
    ax.set_yticks(y)
    ax.set_yticklabels(missing.index)
    ax.set_title("原始数据缺失值统计")
    ax.set_xlabel("缺失记录数 / 条")
    ax.set_xlim(0, max(missing.max() * 1.22, 10))
    ax.grid(True, axis="x")
    save_chart(fig, out_path)


def figure_3_3(out_path: Path) -> None:
    df = read_table("step2_pearson_features.csv").head(10).copy()
    df = df.iloc[::-1]
    colors = []
    for name in df["特征"]:
        if "滞后" in name:
            colors.append(PAL["blue"])
        elif "客流" in name or "人数" in name:
            colors.append(PAL["orange"])
        else:
            colors.append(PAL["green"])

    fig, ax = new_axes(5, frame=True)
    y = np.arange(len(df))
    vals = df["绝对Pearson相关系数"].values
    ax.barh(y, vals, color=colors, height=0.58)
    for i, val in enumerate(vals):
        ax.text(val + 0.012, i, f"{val:.3f}", va="center", fontsize=7.8, color=PAL["dark"])
    ax.axvline(0.80, color=PAL["red"], ls="--", lw=1.0)
    ax.text(0.805, len(df) - 0.25, "|r|=0.80", color=PAL["red"], fontsize=7.5, ha="left", va="top")
    ax.set_yticks(y)
    ax.set_yticklabels(df["特征"])
    ax.set_xlim(0, 1.03)
    ax.set_xlabel("|Pearson 相关系数|")
    ax.set_title("关键影响因素相关性排序")
    ax.grid(True, axis="x")
    save_chart(fig, out_path)


def figure_3_4(out_path: Path) -> None:
    df = read_table("step2_load_component_ratio.csv").copy()
    df = df.sort_values("平均负荷_kW", ascending=True)
    fig, ax = new_axes(6, frame=True)
    y = np.arange(len(df))
    colors = [PAL["purple"], PAL["blue2"], PAL["orange2"], PAL["green"]]
    bars = ax.barh(y, df["平均负荷_kW"], color=colors, height=0.56)
    for bar, (_, row) in zip(bars, df.iterrows()):
        ax.text(
            bar.get_width() + 1.5,
            bar.get_y() + bar.get_height() / 2,
            f"{row['平均负荷_kW']:.1f} kW / {row['占比'] * 100:.1f}%",
            va="center",
            fontsize=8,
            color=PAL["dark"],
        )
    ax.set_yticks(y)
    ax.set_yticklabels(df["分项负荷"])
    ax.set_xlabel("平均负荷 / kW")
    ax.set_title("显式分项负荷及其占总冷负荷比例")
    ax.grid(True, axis="x")
    ax.set_xlim(0, df["平均负荷_kW"].max() * 1.32)
    save_chart(fig, out_path)


def figure_3_5(out_path: Path) -> None:
    df = read_table("step2_daily_cluster_curves.csv")
    curve_cols = [c for c in df.columns if re.fullmatch(r"Var\d+", c)]
    hours = np.arange(len(curve_cols)) / 4.0
    label_map = {
        2: "高负荷双峰型",
        3: "午后高峰型",
        1: "常规中负荷型",
        4: "低负荷平稳型",
    }
    color_map = {
        2: PAL["red"],
        3: PAL["orange"],
        1: PAL["blue"],
        4: PAL["green"],
    }
    order = [2, 3, 1, 4]

    fig, ax = new_axes(7, frame=True)
    for cl in order:
        group = df[df["cluster"] == cl]
        if group.empty:
            continue
        center = group[curve_cols].mean().values.astype(float)
        ax.plot(hours, center, color=color_map[cl], lw=1.8, label=f"{label_map[cl]}（{len(group)}天）")
    ax.set_title("典型日负荷曲线聚类结果")
    ax.set_xlabel("日内时刻 / h")
    ax.set_ylabel("总冷负荷 / kW")
    ax.set_xlim(0, 23.75)
    ax.set_xticks(np.arange(0, 25, 4))
    ax.grid(True, axis="both")
    ax.legend(loc="upper left", frameon=False)
    save_chart(fig, out_path)


def figure_4_1(out_path: Path) -> None:
    fig, ax = new_axes(8)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)

    ax.text(0.035, 0.88, "预测样本构造：4 h 历史窗口预测下一时刻负荷", fontsize=9.6, weight="bold", color=PAL["dark"], ha="left")
    x0, y0, w, h, gap = 0.05, 0.43, 0.055, 0.22, 0.012
    labels = [r"$x_{t-15}$", r"$x_{t-14}$", r"$x_{t-13}$", "…", r"$x_{t-1}$", r"$x_t$"]
    for i, lab in enumerate(labels):
        xx = x0 + i * (w + gap)
        add_box(ax, xx, y0, w, h, lab, "", fc="#EAF3FB", ec=PAL["blue"], title_size=8.0, round_size=0.02)
    ax.text(0.22, 0.30, "16 个时间步 × 多维特征（客流、气象、环境、时间、滞后负荷）", fontsize=7.5, color=PAL["gray"], ha="center")
    add_arrow(ax, (0.45, 0.54), (0.58, 0.54), PAL["gray"], ms=12)
    add_box(ax, 0.59, 0.38, 0.15, 0.30, "LSTM/BP", "模型输入层", fc="#EAF7EF", ec=PAL["green"], title_size=8.2)
    add_arrow(ax, (0.74, 0.54), (0.82, 0.54), PAL["gray"], ms=12)
    add_box(ax, 0.83, 0.41, 0.12, 0.25, "下一时刻\n总冷负荷", "", fc="#FFF3E6", ec=PAL["orange"], title_size=7.5)
    ax.text(0.05, 0.15, "采样间隔：15 min；序列长度 T=16；输出变量：站台区域总冷负荷/kW。", fontsize=7.4, color=PAL["slate"], ha="left")
    save_diagram(fig, out_path)


def figure_4_2(out_path: Path) -> None:
    fig, ax = new_axes(9)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.text(0.03, 0.88, "LSTM 网络结构", fontsize=9.6, weight="bold", color=PAL["dark"], ha="left")
    nodes = [
        (0.04, "序列输入", "16 × F"),
        (0.21, "LSTM层1", "96 hidden"),
        (0.38, "LSTM层2", "48 hidden"),
        (0.55, "全连接层", "1 neuron"),
        (0.72, "回归输出", "kW"),
    ]
    for x, title, body in nodes:
        add_box(ax, x, 0.42, 0.13, 0.24, title, body, fc="#EAF3FB" if "LSTM" in title or "序列" in title else "#F8FAFC", ec=PAL["blue"], title_size=8.4)
    for i in range(len(nodes) - 1):
        add_arrow(ax, (nodes[i][0] + 0.13, 0.54), (nodes[i + 1][0], 0.54), PAL["blue"])
    add_box(ax, 0.87, 0.43, 0.09, 0.22, "损失函数", "MSE", fc="#FFF3E6", ec=PAL["orange"], title_size=8.0)
    add_arrow(ax, (0.85, 0.54), (0.87, 0.54), PAL["orange"])
    ax.text(0.05, 0.22, "适用性：利用历史状态捕捉客流高峰持续、围护结构蓄热和负荷滞后响应。", fontsize=7.4, color=PAL["slate"], ha="left")
    ax.text(0.05, 0.12, "训练设置：时间顺序划分训练/验证/测试集，预测目标为下一时刻总冷负荷。", fontsize=7.4, color=PAL["gray"], ha="left")
    save_diagram(fig, out_path)


def figure_4_3(out_path: Path) -> None:
    fig, ax = new_axes(10)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.text(0.035, 0.88, "BP 神经网络结构", fontsize=9.6, weight="bold", color=PAL["dark"], ha="left")
    nodes = [
        (0.05, "静态特征输入", "客流/气象/环境/时间"),
        (0.29, "隐含层1", "ReLU"),
        (0.48, "隐含层2", "ReLU"),
        (0.67, "输出层", "总冷负荷/kW"),
    ]
    widths = [0.18, 0.13, 0.13, 0.16]
    for (x, title, body), w in zip(nodes, widths):
        add_box(ax, x, 0.43, w, 0.24, title, body, fc="#F8FAFC", ec=PAL["purple"], title_size=8.4)
    for i in range(len(nodes) - 1):
        start_x = nodes[i][0] + widths[i]
        end_x = nodes[i + 1][0]
        add_arrow(ax, (start_x, 0.55), (end_x, 0.55), PAL["purple"])
    add_box(ax, 0.86, 0.43, 0.10, 0.24, "基准模型", "无序列记忆", fc="#FFF3E6", ec=PAL["orange"], title_size=7.8)
    add_arrow(ax, (0.83, 0.55), (0.86, 0.55), PAL["orange"])
    ax.text(0.055, 0.22, "用途：作为传统前馈神经网络基准，用于检验 LSTM 时序记忆结构带来的预测改进。", fontsize=7.4, color=PAL["slate"], ha="left")
    save_diagram(fig, out_path)


def prediction_plot(out_path: Path, csv_name: str, model_name: str, idx: int) -> None:
    series = read_table(csv_name)
    metrics = read_table("step3_prediction_metrics.csv").set_index("模型").loc[model_name]

    fig, ax = new_axes(idx, frame=True)
    x = series["sample"].values
    ax.plot(x, series["actual_kw"].values, color=PAL["blue"], lw=0.85, label="实测值")
    ax.plot(x, series["predicted_kw"].values, color=PAL["orange"], lw=0.85, alpha=0.9, label="预测值")
    ax.set_title(f"{model_name} 测试集负荷预测结果")
    ax.set_xlabel("测试样本序号")
    ax.set_ylabel("总冷负荷 / kW")
    ax.grid(True, axis="y")
    ax.legend(loc="upper right", frameon=False)
    ax.set_xlim(x.min(), x.max())
    ax.set_ylim(0, max(series[["actual_kw", "predicted_kw"]].to_numpy().max() * 1.12, 320))
    metrics_text = (
        f"RMSE={metrics['均方根误差_kW']:.2f} kW\n"
        f"MAE={metrics['平均绝对误差_kW']:.2f} kW\n"
        f"MAPE={metrics['平均绝对百分比误差_百分比']:.2f}%\n"
        f"R²={metrics['决定系数R2']:.4f}"
    )
    ax.text(
        0.015,
        0.96,
        metrics_text,
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=7.8,
        color=PAL["dark"],
        bbox=dict(boxstyle="round,pad=0.35", fc="white", ec=PAL["line"], lw=0.8, alpha=0.94),
    )
    save_chart(fig, out_path)


def figure_4_6(out_path: Path) -> None:
    df = read_table("step3_prediction_metrics.csv").set_index("模型").loc[["LSTM", "BP"]]
    err_cols = ["均方根误差_kW", "平均绝对误差_kW", "平均绝对百分比误差_百分比"]
    labels = ["RMSE/kW", "MAE/kW", "MAPE/%"]

    fig, axes = plt.subplots(1, 2, figsize=TARGET_DIMS_IN[12], gridspec_kw={"width_ratios": [2.9, 1.05]})
    fig.patch.set_facecolor("white")
    ax = axes[0]
    x = np.arange(len(err_cols))
    width = 0.34
    ax.bar(x - width / 2, df.loc["LSTM", err_cols].values, width, color=PAL["blue"], label="LSTM")
    ax.bar(x + width / 2, df.loc["BP", err_cols].values, width, color=PAL["orange"], label="BP")
    for i, col in enumerate(err_cols):
        for j, model in enumerate(["LSTM", "BP"]):
            value = df.loc[model, col]
            xpos = i + (-width / 2 if model == "LSTM" else width / 2)
            ax.text(xpos, value + 0.55, f"{value:.2f}", ha="center", va="bottom", fontsize=7.2)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_title("误差指标（越低越好）")
    ax.set_ylabel("指标值")
    ax.grid(True, axis="y")
    ax.legend(frameon=False, loc="upper left")
    ax.set_ylim(0, max(df[err_cols].to_numpy().max() * 1.22, 10))

    ax2 = axes[1]
    r2 = df["决定系数R2"].values
    ax2.bar(["LSTM", "BP"], r2, color=[PAL["blue"], PAL["orange"]], width=0.55)
    for i, v in enumerate(r2):
        ax2.text(i, v + 0.01, f"{v:.4f}", ha="center", va="bottom", fontsize=7.2)
    ax2.set_title("R²（越高越好）")
    ax2.set_ylim(0, 1.08)
    ax2.grid(True, axis="y")
    save_chart(fig, out_path)


def figure_5_1(out_path: Path) -> None:
    fig, ax = new_axes(14)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.text(0.035, 0.88, "NSGA-II 与 TOPSIS 容量优化流程", fontsize=9.6, weight="bold", color=PAL["dark"], ha="left")
    nodes = [
        (0.04, "预测负荷", "LSTM曲线\nP99+RMSE"),
        (0.22, "决策变量", "冷机/风机/水泵\n容量与台数"),
        (0.41, "约束校核", "需求满足\n设备边界"),
        (0.60, "NSGA-II", "生成 Pareto\n候选解集"),
        (0.79, "TOPSIS", "成本-冗余\n综合排序"),
    ]
    for x, title, body in nodes:
        fc = "#EAF3FB" if title in {"预测负荷", "NSGA-II"} else "#F8FAFC"
        add_box(ax, x, 0.42, 0.14, 0.25, title, body, fc=fc, ec=PAL["blue"], title_size=8.3, body_size=7.0)
    for i in range(len(nodes) - 1):
        add_arrow(ax, (nodes[i][0] + 0.14, 0.55), (nodes[i + 1][0], 0.55), PAL["blue"])
    add_box(ax, 0.20, 0.15, 0.20, 0.15, "目标1", "全生命周期成本最小", fc="#FFF3E6", ec=PAL["orange"], title_size=7.6)
    add_box(ax, 0.46, 0.15, 0.20, 0.15, "目标2", "综合容量冗余率最小", fc="#EAF7EF", ec=PAL["green"], title_size=7.6)
    add_box(ax, 0.72, 0.15, 0.20, 0.15, "输出", "推荐容量方案与工程评价", fc="#F3E8FF", ec=PAL["purple"], title_size=7.6)
    add_arrow(ax, (0.50, 0.42), (0.50, 0.30), PAL["gray"], ms=9)
    add_arrow(ax, (0.86, 0.42), (0.83, 0.30), PAL["gray"], ms=9)
    save_diagram(fig, out_path)


def figure_5_2(out_path: Path) -> None:
    df = read_table("step4_topsis_ranking.csv").copy()
    df["成本_万元"] = df["生命周期成本"] / 10000
    df["冗余率_pct"] = df["综合冗余率"] * 100
    main = df[df["冗余率_pct"] < 60].copy()
    outliers = len(df) - len(main)
    best_idx = main["TOPSIS得分"].idxmax()
    best = main.loc[best_idx]

    fig, ax = new_axes(15, frame=True)
    scatter = ax.scatter(
        main["成本_万元"],
        main["冗余率_pct"],
        c=main["TOPSIS得分"],
        cmap="viridis",
        s=46,
        edgecolor="white",
        linewidth=0.5,
        alpha=0.95,
    )
    sorted_main = main.sort_values("成本_万元")
    ax.plot(sorted_main["成本_万元"], sorted_main["冗余率_pct"], color=PAL["gray"], lw=1.0, alpha=0.55, ls="--")
    ax.scatter([best["成本_万元"]], [best["冗余率_pct"]], marker="*", s=190, color=PAL["red"], edgecolor="white", linewidth=0.8, zorder=5)
    ax.annotate(
        "推荐方案",
        xy=(best["成本_万元"], best["冗余率_pct"]),
        xytext=(best["成本_万元"] + 3.5, best["冗余率_pct"] + 5),
        arrowprops=dict(arrowstyle="->", color=PAL["red"], lw=0.9),
        fontsize=8,
        color=PAL["red"],
    )
    ax.set_title("Pareto 候选方案分布与 TOPSIS 排序")
    ax.set_xlabel("全生命周期成本 / 万元")
    ax.set_ylabel("综合冗余率 / %")
    ax.grid(True, axis="both")
    cbar = fig.colorbar(scatter, ax=ax, fraction=0.046, pad=0.03)
    cbar.set_label("TOPSIS 得分", fontsize=8)
    if outliers:
        ax.text(
            0.02,
            0.96,
            f"注：{outliers} 个高成本高冗余低得分方案未纳入主视区",
            transform=ax.transAxes,
            fontsize=7.4,
            color=PAL["gray"],
            ha="left",
            va="top",
        )
    save_chart(fig, out_path)


def figure_6_1(out_path: Path) -> None:
    df = read_table("step4_scheme_evaluation.csv").set_index("方案")
    cols = {
        "总制冷容量_kW": "制冷容量",
        "生命周期成本": "生命周期成本",
        "综合冗余率": "综合冗余率",
        "年能耗_kWh": "年运行能耗",
    }
    base = df.loc["基准方案", list(cols)]
    opt = df.loc["优化方案", list(cols)]
    ratio = opt / base * 100

    fig, ax = new_axes(16, frame=True)
    x = np.arange(len(cols))
    width = 0.35
    ax.bar(x - width / 2, [100] * len(cols), width, color="#BFC7D3", label="基准方案")
    ax.bar(x + width / 2, ratio.values, width, color=PAL["green"], label="优化方案")
    for i, val in enumerate(ratio.values):
        ax.text(i + width / 2, max(val - 4, 3), f"{val:.1f}%", ha="center", va="top", fontsize=7.5, color="white", weight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(list(cols.values()))
    ax.set_ylabel("相对基准方案 / %")
    ax.set_title("基准方案与优化方案综合对比")
    ax.set_ylim(0, 118)
    ax.grid(True, axis="y")
    ax.legend(loc="upper right", frameon=False)
    save_chart(fig, out_path)


def create_contact_sheet(fig_paths: list[Path], out_path: Path) -> None:
    thumbs = []
    for i, path in enumerate(fig_paths, start=1):
        im = Image.open(path).convert("RGB")
        im.thumbnail((500, 310))
        canvas = Image.new("RGB", (520, 350), "white")
        draw = ImageDraw.Draw(canvas)
        draw.text((10, 8), f"{i:02d}  {path.name}", fill=(30, 41, 59))
        canvas.paste(im, (10, 34))
        thumbs.append(canvas)

    cols = 2
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * 520, rows * 350), "white")
    for idx, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((idx % cols) * 520, (idx // cols) * 350))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def build_figures() -> list[Path]:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    fig_paths = [FIG_DIR / f"fig{i:02d}.png" for i in range(1, 17)]
    figure_1_1(fig_paths[0])
    figure_2_1(fig_paths[1])
    figure_3_1(fig_paths[2])
    figure_3_2(fig_paths[3])
    figure_3_3(fig_paths[4])
    figure_3_4(fig_paths[5])
    figure_3_5(fig_paths[6])
    figure_4_1(fig_paths[7])
    figure_4_2(fig_paths[8])
    figure_4_3(fig_paths[9])
    prediction_plot(fig_paths[10], "step3_lstm_prediction_series.csv", "LSTM", 11)
    prediction_plot(fig_paths[11], "step3_bp_prediction_series.csv", "BP", 12)
    figure_4_6(fig_paths[12])
    figure_5_1(fig_paths[13])
    figure_5_2(fig_paths[14])
    figure_6_1(fig_paths[15])
    create_contact_sheet(fig_paths, FIG_DIR / "contact_sheet.png")
    return fig_paths


def find_input_docx() -> Path:
    candidates = sorted(ROOT.glob(INPUT_DOCX_PATTERN))
    if not candidates:
        raise FileNotFoundError(f"Cannot find input docx by pattern {INPUT_DOCX_PATTERN}")
    return candidates[-1]


def set_inline_shape_sizes(input_docx: Path, tmp_docx: Path) -> None:
    doc = Document(str(input_docx))
    if len(doc.inline_shapes) < len(TARGET_DIMS_IN):
        raise RuntimeError(f"Expected at least {len(TARGET_DIMS_IN)} inline shapes, found {len(doc.inline_shapes)}")
    for shape, (width_in, height_in) in zip(doc.inline_shapes, TARGET_DIMS_IN):
        shape.width = Inches(width_in)
        shape.height = Inches(height_in)
    doc.save(str(tmp_docx))


def replace_docx_media(tmp_docx: Path, output_docx: Path, fig_paths: list[Path]) -> None:
    media_map = {f"word/media/image{i}.png": fig_paths[i - 1] for i in range(1, len(fig_paths) + 1)}
    if output_docx.exists():
        output_docx.unlink()
    with zipfile.ZipFile(tmp_docx, "r") as zin, zipfile.ZipFile(output_docx, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename in media_map:
                data = media_map[item.filename].read_bytes()
            zout.writestr(item, data)


def optimize_docx(fig_paths: list[Path]) -> Path:
    input_docx = find_input_docx()
    tmp_docx = OUTPUT_DOCX.with_name(OUTPUT_DOCX.stem + "_tmp_sized.docx")
    set_inline_shape_sizes(input_docx, tmp_docx)
    replace_docx_media(tmp_docx, OUTPUT_DOCX, fig_paths)
    tmp_docx.unlink(missing_ok=True)
    return OUTPUT_DOCX


def main() -> None:
    setup_matplotlib()
    fig_paths = build_figures()
    output_docx = optimize_docx(fig_paths)
    print(f"generated={output_docx}")
    print(f"figures={FIG_DIR}")
    print(f"contact_sheet={FIG_DIR / 'contact_sheet.png'}")


if __name__ == "__main__":
    main()
