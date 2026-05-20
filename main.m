% 地铁车站环控系统容量优化完整流程的主入口。
% 本脚本只负责流程调度：参数来自 config.m，具体研究步骤分别由 step*.m 文件实现。
clear; clc; close all;

% 关闭 TeX 解释器，避免图题、图例中的下划线和文件名被 MATLAB 当作格式命令解析。
set(groot, "defaultTextInterpreter", "none");
set(groot, "defaultLegendInterpreter", "none");
set(groot, "defaultAxesTickLabelInterpreter", "none");

% 从统一配置结构中读取路径、模型超参数、经济假设和工程约束。
cfg = config();
totalTimer = tic;

% 在各步骤写出表格、图片或模型文件前，先确保输出目录存在。
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
fprintf("地铁车站环控系统容量优化流程开始。\n");
fprintf("数据文件：%s\n", cfg.dataFile);
fprintf("输出文件夹：%s\n", cfg.outputDir);
fprintf("============================================================\n\n");

% 步骤1将原始 CSV 转换为清洗后的数据表和标准化特征矩阵，后续步骤依赖 dataClean 和 featureData。
fprintf("[1/4] 数据预处理开始。\n");
[dataRaw, dataClean, featureData] = step1_data_prepare(cfg);
fprintf("[1/4] 数据预处理完成。\n\n");

% 步骤2分析负荷影响因素并提取典型日负荷模式，其特征选择和聚类结果将进入预测步骤。
fprintf("[2/4] 影响因素分析与聚类开始。\n");
analysisResult = step2_analysis_cluster(cfg, dataClean, featureData);
fprintf("[2/4] 影响因素分析与聚类完成。\n\n");

% 步骤3训练负荷预测模型，并将总冷负荷预测结果转换为各子系统容量需求情景。
fprintf("[3/4] 负荷预测开始。\n");
predictionResult = step3_load_prediction(cfg, featureData, dataClean, analysisResult);
fprintf("[3/4] 负荷预测完成。\n\n");

% 步骤4搜索可行设备容量方案，并在 Pareto 优化后用 TOPSIS 选择推荐方案。
fprintf("[4/4] 容量优化开始。\n");
optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult);
fprintf("[4/4] 容量优化完成。\n\n");

% 保存汇总 MAT 文件，便于不重新运行全流程时复查或复现论文图表。
resultFile = fullfile(cfg.modelDir, "bishe_result_summary.mat");
save(resultFile, ...
    "cfg", "dataRaw", "dataClean", "featureData", ...
    "analysisResult", "predictionResult", "optimizationResult");

fprintf("============================================================\n");
fprintf("流程完成，用时 %.1f 秒。\n", toc(totalTimer));
fprintf("结果已保存至 %s\n", resultFile);
fprintf("============================================================\n");
