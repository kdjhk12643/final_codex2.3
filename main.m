clear; clc; close all;

cfg = config();
totalTimer = tic;

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

fprintf("[1/4] Data preparation started.\n");
[dataRaw, dataClean, featureData] = step1_data_prepare(cfg);
fprintf("[1/4] Data preparation finished.\n\n");

fprintf("[2/4] Influence analysis and clustering started.\n");
analysisResult = step2_analysis_cluster(cfg, dataClean, featureData);
fprintf("[2/4] Influence analysis and clustering finished.\n\n");

fprintf("[3/4] Load prediction started.\n");
predictionResult = step3_load_prediction(cfg, featureData, analysisResult);
fprintf("[3/4] Load prediction finished.\n\n");

fprintf("[4/4] Capacity optimization started.\n");
optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult);
fprintf("[4/4] Capacity optimization finished.\n\n");

resultFile = fullfile(cfg.modelDir, "bishe_result_summary.mat");
save(resultFile, ...
    "cfg", "dataRaw", "dataClean", "featureData", ...
    "analysisResult", "predictionResult", "optimizationResult");

fprintf("============================================================\n");
fprintf("Workflow finished in %.1f seconds.\n", toc(totalTimer));
fprintf("Results saved to %s\n", resultFile);
fprintf("============================================================\n");
