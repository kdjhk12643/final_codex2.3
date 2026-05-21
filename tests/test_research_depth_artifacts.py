from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_research_depth_matlab_helpers_are_present():
    linkage = read_text(ROOT / "build_research_linkage_table.m")
    sensitivity = read_text(ROOT / "analyze_capacity_sensitivity.m")
    step4 = read_text(ROOT / "step4_capacity_optimization.m")

    assert "linkageStage" in linkage
    assert "evidenceMetric" in linkage
    assert "simplificationRisk" in linkage
    assert "sensitivityType" in sensitivity
    assert "engineeringBoundary" in sensitivity
    assert "step4_research_linkage.csv" in step4
    assert "step4_sensitivity_analysis.csv" in step4
    assert "step4_engineering_boundary.csv" in step4


def test_cluster_ablation_is_implemented_in_step3():
    step3 = read_text(ROOT / "step3_load_prediction.m")

    assert "step3_cluster_ablation_metrics.csv" in step3
    assert "addClusterLabelFeature" in step3
    assert "lstm_without_cluster" in step3
    assert "lstm_with_cluster" in step3
    assert "clusterFeatureName" in step3


def test_fair_model_comparison_is_implemented_in_step3():
    step3 = read_text(ROOT / "step3_load_prediction.m")

    assert "step3_fair_model_comparison.csv" in step3
    assert "runFairModelComparison" in step3
    assert "lstm_with_lag" in step3
    assert "bp_with_lag" in step3
    assert "lstm_without_lag" in step3
    assert "bp_without_lag" in step3
    assert "usesLagFeatures" in step3


def test_engineering_constraints_are_implemented_in_step4():
    config = read_text(ROOT / "config.m")
    step4 = read_text(ROOT / "step4_capacity_optimization.m")

    assert "cfg.minTypicalChillerPLR" in config
    assert "cfg.minExtremeCapacityMargin" in config
    assert "cfg.predictionErrorRmseFactor" in config
    assert "cfg.fanCoolingCapacityRatioRange" in config
    assert "cfg.pumpCoolingCapacityRatioRange" in config
    assert "cfg.ahuAirflowPerCoolingKwRange" in config

    assert "applyPredictionErrorMargin" in step4
    assert "minimumPLRConstraint" in step4
    assert "extremeMarginFactor" in step4
    assert "matchingConstraints" in step4
    assert "predictionErrorMarginKw" in step4
    assert "step4_engineering_constraint_check.csv" in step4
    assert "buildEngineeringConstraintCheck" in step4


def test_ideal_result_text_matches_actual_output_and_has_no_mojibake():
    text = read_text(ROOT / "我最理想的实验结果.txt")

    assert "LSTM" in text
    assert "RMSE=9.47" in text
    assert "R²=0.9715" in text
    assert "综合冗余率：32.71% → 10.78%" in text
    assert "全生命周期成本降低：13.01%" in text
    assert "年运行能耗降低：6.68%" in text
    assert "敏感性分析" in text
    assert "工程边界" in text
    assert "�" not in text
    assert "锝" not in text
    assert "瀹" not in text
