function linkageTable = build_research_linkage_table(cfg, predictionResult, optimizationResult)
%BUILD_RESEARCH_LINKAGE_TABLE Summarize how analysis, prediction, and optimization connect.

evaluation = optimizationResult.evaluationTable;
baseline = evaluation(strcmp(evaluation.scheme, "baseline"), :);
optimized = evaluation(strcmp(evaluation.scheme, "optimized"), :);

lstm = predictionResult.metrics(strcmp(predictionResult.metrics.model, "LSTM"), :);
bp = predictionResult.metrics(strcmp(predictionResult.metrics.model, "BP"), :);

clusterText = sprintf("K=%d, best silhouette %.3f", ...
    optimizationResult.analysisSummary.bestK, ...
    max(optimizationResult.analysisSummary.clusterSilhouette, [], "omitnan"));
predictionText = sprintf("LSTM RMSE %.2f, MAPE %.2f%%, R2 %.4f; BP RMSE %.2f", ...
    lstm.RMSE, lstm.MAPE, lstm.R2, bp.RMSE);
capacityText = sprintf("P%.0f design load %.2f kW, optimized cooling capacity %.0f kW", ...
    optimizationResult.designDemand.quantile * 100, ...
    optimizationResult.designDemand.totalCoolingLoadKw, ...
    optimized.totalCoolingCapacityKw);
evaluationText = sprintf("redundancy %.2f%% -> %.2f%%, cost down %.2f%%, energy down %.2f%%", ...
    baseline.redundancyRate * 100, optimized.redundancyRate * 100, ...
    optimized.costReductionRate * 100, optimized.energySavingRate * 100);

linkageStage = [
    "feature_analysis_to_prediction"
    "cluster_analysis_to_prediction"
    "prediction_to_capacity_demand"
    "capacity_optimization_to_scheme_evaluation"
];
upstreamOutput = [
    "Pearson-selected passenger, environment, time, and lagged-load features"
    "Typical daily load modes and the selected K-Means label structure"
    "LSTM full predicted load profile and P50/P95/P99 demand scenarios"
    "Pareto candidate schemes and TOPSIS ranking"
];
downstreamUse = [
    "Used as the LSTM input matrix and BP comparison input"
    "Used to explain operating modes and support scenario interpretation"
    "Converted into chiller, fan, pump, and AHU capacity constraints"
    "Compared against the baseline scheme for cost, redundancy, and energy"
];
evidenceMetric = [
    predictionText
    clusterText
    capacityText
    evaluationText
];
simplificationRisk = [
    "Pearson captures linear relation only; nonlinear interactions need further validation"
    "Cluster label contribution should be verified by an ablation experiment when time permits"
    "Subsystem demand conversion uses regression/engineering ratios, not full hydraulic or psychrometric design"
    "TOPSIS ranking depends on weights and should be read together with sensitivity analysis"
];

linkageTable = table(linkageStage, upstreamOutput, downstreamUse, evidenceMetric, simplificationRisk);
end
