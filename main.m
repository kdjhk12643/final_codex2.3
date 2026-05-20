% Main entry point for the full metro-station HVAC capacity workflow.
% The script intentionally keeps only orchestration here: parameters come from
% config.m, while each research step is implemented in its own step*.m file.
clear; clc; close all;

% Disable TeX parsing so file names, underscores, and English labels are shown
% literally in figures and legends.
set(groot, "defaultTextInterpreter", "none");
set(groot, "defaultLegendInterpreter", "none");
set(groot, "defaultAxesTickLabelInterpreter", "none");

% Load all configurable paths, model hyperparameters, economic assumptions, and
% engineering constraints from one centralized configuration structure.
cfg = config();
totalTimer = tic;

% Create output folders before any step writes tables, figures, or models.
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
if ~exist(cfg.figureDir, "dir")
    mkdir(cfg.figureDir);
end
if ~exist(cfg.tableDir, "dir")
    mkdir(cfg.tableDir);
end
if ~exist(cfg.modelDir, "dir")
    mkdir(cfg.modelDir);
end

fprintf("\n============================================================\n");
fprintf("Metro station HVAC capacity optimization workflow started.\n");
fprintf("Data file: %s\n", cfg.dataFile);
fprintf("Output folder: %s\n", cfg.outputDir);
fprintf("============================================================\n\n");

% Step 1 converts the raw CSV into a cleaned table and standardized feature
% matrix. Later steps rely on both dataClean and featureData.
fprintf("[1/4] Data preparation started.\n");
[dataRaw, dataClean, featureData] = step1_data_prepare(cfg);
fprintf("[1/4] Data preparation finished.\n\n");

% Step 2 explains the load drivers and extracts typical daily load patterns.
% Its selected features and cluster labels feed the prediction step.
fprintf("[2/4] Influence analysis and clustering started.\n");
analysisResult = step2_analysis_cluster(cfg, dataClean, featureData);
fprintf("[2/4] Influence analysis and clustering finished.\n\n");

% Step 3 trains the prediction models and converts the predicted total cooling
% load into subsystem demand scenarios for equipment sizing.
fprintf("[3/4] Load prediction started.\n");
predictionResult = step3_load_prediction(cfg, featureData, dataClean, analysisResult);
fprintf("[3/4] Load prediction finished.\n\n");

% Step 4 searches feasible equipment-capacity schemes and selects the final
% recommendation with TOPSIS after Pareto optimization.
fprintf("[4/4] Capacity optimization started.\n");
optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult);
fprintf("[4/4] Capacity optimization finished.\n\n");

% Save a compact MAT summary so thesis figures/tables can be regenerated or
% inspected without rerunning the full workflow.
resultFile = fullfile(cfg.modelDir, "bishe_result_summary.mat");
save(resultFile, ...
    "cfg", "dataRaw", "dataClean", "featureData", ...
    "analysisResult", "predictionResult", "optimizationResult");

fprintf("============================================================\n");
fprintf("Workflow finished in %.1f seconds.\n", toc(totalTimer));
fprintf("Results saved to %s\n", resultFile);
fprintf("============================================================\n");
