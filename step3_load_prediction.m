function predictionResult = step3_load_prediction(cfg, featureData, dataClean, analysisResult)
%STEP3_LOAD_PREDICTION 训练 LSTM 和 BP 模型，并评估预测结果。
% 预测结果连接统计分析与工程容量配置：其中保存模型指标、完整负荷预测曲线和子系统需求情景。

stepTimer = tic;
predictionResult = struct();

% 先使用步骤2中 Pearson 筛选出的特征，再额外加入标准化日聚类标签用于消融实验。
selectedFeatures = string(analysisResult.selectedFeatures);
selectedFeatures = selectedFeatures(ismember(selectedFeatures, string(featureData.Properties.VariableNames)));
clusterFeatureName = "cluster_label_zscore";
featureDataWithCluster = addClusterLabelFeature(cfg, featureData, analysisResult, clusterFeatureName);
selectedFeaturesWithCluster = unique([selectedFeatures; clusterFeatureName], "stable");

fprintf("  步骤 3.1 使用 %d 个筛选特征构建预测矩阵...\n", numel(selectedFeatures));
% X 和 y 保持时间顺序，因此 splitIndexes 生成的是按时间划分的训练/验证/测试集，而非随机划分。
[X, y] = buildMatrix(featureData, selectedFeatures, cfg.targetName);
split = splitIndexes(numel(y), cfg);
fprintf("  样本数：总计=%d，训练=%d，验证=%d，测试=%d。\n", ...
    numel(y), numel(split.train), numel(split.val), numel(split.test));

predictionResult.selectedFeatures = selectedFeatures;
predictionResult.clusterFeatureName = clusterFeatureName;
predictionResult.selectedFeaturesWithCluster = selectedFeaturesWithCluster;
predictionResult.split = split;

fprintf("  步骤 3.2 构建 LSTM 序列，序列长度 = %d...\n", cfg.sequenceLength);
% LSTM 样本由历史特征行的滑动窗口构成。
[XSeq, ySeq] = buildSequences(X, y, cfg.sequenceLength);
seqSplit = splitIndexes(numel(ySeq), cfg);

fprintf("  步骤 3.3 训练 LSTM，最大轮数=%d，小批量大小=%d...\n", cfg.maxEpochs, cfg.miniBatchSize);
predictionResult.lstm = trainLstmOrFallback(cfg, XSeq, ySeq, seqSplit);
fprintf("  步骤 3.4 训练 BP 对比模型...\n");
% BP 基准模型尽量剔除负荷滞后特征，用作比序列型 LSTM 更简单的静态特征对比模型。
bpFeatures = selectedFeatures(~startsWith(selectedFeatures, "load_lag_"));
if isempty(bpFeatures)
    bpFeatures = selectedFeatures;
end
[Xbp, ybp] = buildMatrix(featureData, bpFeatures, cfg.targetName);
bpSplit = splitIndexes(numel(ybp), cfg);
fprintf("  BP 基准模型使用 %d 个静态特征，并排除负荷滞后特征。\n", numel(bpFeatures));
predictionResult.bpFeatures = bpFeatures;
predictionResult.bp = trainBpOrFallback(cfg, Xbp, ybp, bpSplit);

predictionResult.yTest = ybp(bpSplit.test);
predictionResult.yPredBP = predictionResult.bp.yPredTest;
predictionResult.metricsBP = calculateMetrics(cfg, predictionResult.yTest, predictionResult.yPredBP);

predictionResult.yTestLSTM = ySeq(seqSplit.test);
predictionResult.yPredLSTM = predictionResult.lstm.yPredTest;
predictionResult.metricsLSTM = calculateMetrics(cfg, predictionResult.yTestLSTM, predictionResult.yPredLSTM);

fprintf("  步骤 3.5 运行聚类标签消融实验...\n");
% 训练两个 LSTM 变体，用于量化典型日聚类标签是否提升预测精度。
predictionResult.clusterAblation = runClusterAblation( ...
    cfg, featureDataWithCluster, selectedFeatures, selectedFeaturesWithCluster, cfg.targetName);

fprintf("  步骤 3.6 生成用于容量优化的完整预测负荷曲线...\n");
% 完整预测曲线用于设计分位数和年能耗计算，不只用于测试集精度报告。
predictionResult = generateLoadProfile(cfg, predictionResult, X, y);

fprintf("  步骤 3.7 训练子系统回归模型（冷机、风机、水泵、AHU）...\n");
% 这些回归模型用于把总冷负荷映射为子系统设备需求。
subsystemModels = trainSubsystemModels(cfg, dataClean);
fprintf("    冷机：%.4f × 总负荷 + %.2f  (R²=%.3f)\n", ...
    subsystemModels.chiller.Coefficients.Estimate(2), ...
    subsystemModels.chiller.Coefficients.Estimate(1), ...
    subsystemModels.chiller.Rsquared.Ordinary);
fprintf("    风机：%.4f × 总负荷 + %.2f  (R²=%.3f)\n", ...
    subsystemModels.fan.Coefficients.Estimate(2), ...
    subsystemModels.fan.Coefficients.Estimate(1), ...
    subsystemModels.fan.Rsquared.Ordinary);
fprintf("    水泵：%.4f × 总负荷 + %.2f  (R²=%.3f)\n", ...
    subsystemModels.pump.Coefficients.Estimate(2), ...
    subsystemModels.pump.Coefficients.Estimate(1), ...
    subsystemModels.pump.Rsquared.Ordinary);

fprintf("  步骤 3.8 基于 LSTM 预测结果推算子系统负荷曲线...\n");
% 将子系统模型应用到总负荷预测曲线，使优化环节能分别约束冷机、风机、水泵和 AHU 容量。
predictionResult = predictSubsystemProfiles(cfg, predictionResult, subsystemModels);

fprintf("  步骤 3.9 生成子系统置信需求和情景需求表...\n");
predictionResult = buildSubsystemDemandOutputs(cfg, predictionResult);

predictionResult.metrics = table( ...
    ["LSTM"; "BP"], ...
    [predictionResult.metricsLSTM.RMSE; predictionResult.metricsBP.RMSE], ...
    [predictionResult.metricsLSTM.MAE; predictionResult.metricsBP.MAE], ...
    [predictionResult.metricsLSTM.MAPE; predictionResult.metricsBP.MAPE], ...
    [predictionResult.metricsLSTM.R2; predictionResult.metricsBP.R2], ...
    'VariableNames', {'model', 'RMSE', 'MAE', 'MAPE', 'R2'});

% 写出模型性能和需求情景证据表，供论文表格使用。
metricsFile = fullfile(cfg.tableDir, "step3_prediction_metrics.csv");
ablationFile = fullfile(cfg.tableDir, "step3_cluster_ablation_metrics.csv");
quantileFile = fullfile(cfg.tableDir, "step3_subsystem_demand_quantiles.csv");
scenarioFile = fullfile(cfg.tableDir, "step3_scenario_demand.csv");
writetable(localizePredictionMetricsForOutput(predictionResult.metrics), metricsFile);
writetable(localizeAblationTableForOutput(predictionResult.clusterAblation), ablationFile);
writetable(localizeQuantileTableForOutput(predictionResult.subsystemDemandQuantiles), quantileFile);
writetable(localizeScenarioTableForOutput(predictionResult.scenarioDemandTable), scenarioFile);

plotStep3Figures(cfg, predictionResult);

fprintf("  LSTM 指标：RMSE=%.3f，MAE=%.3f，MAPE=%.2f%%，R2=%.4f。\n", ...
    predictionResult.metricsLSTM.RMSE, predictionResult.metricsLSTM.MAE, ...
    predictionResult.metricsLSTM.MAPE, predictionResult.metricsLSTM.R2);
fprintf("  BP 指标：RMSE=%.3f，MAE=%.3f，MAPE=%.2f%%，R2=%.4f。\n", ...
    predictionResult.metricsBP.RMSE, predictionResult.metricsBP.MAE, ...
    predictionResult.metricsBP.MAPE, predictionResult.metricsBP.R2);
fprintf("  已保存：%s\n", metricsFile);
fprintf("  已保存：%s\n", ablationFile);
fprintf("  已保存：%s\n", quantileFile);
fprintf("  已保存：%s\n", scenarioFile);
fprintf("  步骤 3 完成，用时 %.1f 秒。\n", toc(stepTimer));
end

function featureDataOut = addClusterLabelFeature(~, featureData, analysisResult, clusterFeatureName)
%ADDCLUSTERLABELFEATURE 将每日 K-Means 标签扩展到该日所有采样点。
featureDataOut = featureData;
timestamps = featureDataOut.timestamp;
dates = dateshift(timestamps, "start", "day");
clusterValues = nan(height(featureDataOut), 1);

for i = 1:numel(analysisResult.dailyDates)
    idx = dates == analysisResult.dailyDates(i);
    clusterValues(idx) = analysisResult.clusterLabel(i);
end

% 对未匹配日期做防御性填补，再对类别标签做 zscore，使其量级接近其他标准化特征。
clusterValues = fillmissing(clusterValues, "nearest");
clusterValues = fillmissing(clusterValues, "constant", mode(analysisResult.clusterLabel));
sigma = std(clusterValues, "omitnan");
if sigma == 0 || isnan(sigma)
    featureDataOut.(clusterFeatureName) = zeros(height(featureDataOut), 1);
else
    featureDataOut.(clusterFeatureName) = (clusterValues - mean(clusterValues, "omitnan")) ./ sigma;
end
end

function ablationTable = runClusterAblation(cfg, featureDataWithCluster, selectedFeatures, selectedFeaturesWithCluster, targetName)
%RUNCLUSTERABLATION 对比带聚类标签和不带聚类标签的 LSTM 表现。
[XBase, yBase] = buildMatrix(featureDataWithCluster, selectedFeatures, targetName);
[XCluster, yCluster] = buildMatrix(featureDataWithCluster, selectedFeaturesWithCluster, targetName);

[XSeqBase, ySeqBase] = buildSequences(XBase, yBase, cfg.sequenceLength);
[XSeqCluster, ySeqCluster] = buildSequences(XCluster, yCluster, cfg.sequenceLength);

baseSplit = splitIndexes(numel(ySeqBase), cfg);
clusterSplit = splitIndexes(numel(ySeqCluster), cfg);

withoutCluster = trainLstmOrFallback(cfg, XSeqBase, ySeqBase, baseSplit);
withCluster = trainLstmOrFallback(cfg, XSeqCluster, ySeqCluster, clusterSplit);

metricsWithoutCluster = calculateMetrics(cfg, ySeqBase(baseSplit.test), withoutCluster.yPredTest);
metricsWithCluster = calculateMetrics(cfg, ySeqCluster(clusterSplit.test), withCluster.yPredTest);

model = ["lstm_without_cluster"; "lstm_with_cluster"];
usesClusterLabel = [false; true];
featureCount = [numel(selectedFeatures); numel(selectedFeaturesWithCluster)];
RMSE = [metricsWithoutCluster.RMSE; metricsWithCluster.RMSE];
MAE = [metricsWithoutCluster.MAE; metricsWithCluster.MAE];
MAPE = [metricsWithoutCluster.MAPE; metricsWithCluster.MAPE];
R2 = [metricsWithoutCluster.R2; metricsWithCluster.R2];

ablationTable = table(model, usesClusterLabel, featureCount, RMSE, MAE, MAPE, R2);
end

function [X, y] = buildMatrix(featureData, selectedFeatures, targetName)
%BUILDMATRIX 提取数值预测因子，并删除输入或目标缺失的样本。
X = featureData{:, selectedFeatures};
y = featureData.(targetName);
valid = all(~isnan(X), 2) & ~isnan(y);
X = X(valid, :);
y = y(valid);
end

function split = splitIndexes(n, cfg)
%SPLITINDEXES 生成按时间顺序划分的训练、验证和测试索引。
nTrain = floor(n * cfg.trainRatio);
nVal = floor(n * cfg.valRatio);
split.train = 1:nTrain;
split.val = (nTrain + 1):(nTrain + nVal);
split.test = (nTrain + nVal + 1):n;
end

function [XSeq, ySeq] = buildSequences(X, y, sequenceLength)
%BUILDSEQUENCES 将表格样本转换为 LSTM 所需的 cell 序列。
n = size(X, 1) - sequenceLength;
XSeq = cell(n, 1);
ySeq = zeros(n, 1);

for i = 1:n
    % MATLAB 序列输入要求每个样本为“特征数 × 时间步”的布局。
    XSeq{i} = X(i:(i + sequenceLength - 1), :)';
    ySeq(i) = y(i + sequenceLength);
end
end

function result = trainLstmOrFallback(cfg, XSeq, ySeq, split)
%TRAINLSTMORFALLBACK 优先使用 Deep Learning Toolbox；不可用时用移动平均保证流程可运行。
result = struct("model", [], "yPredTest", []);

hasDeepLearning = exist("trainNetwork", "file") == 2 && exist("lstmLayer", "file") == 2;
if hasDeepLearning
    fprintf("    检测到 Deep Learning Toolbox，使用 trainNetwork。\n");
    inputSize = size(XSeq{1}, 1);
    yTrain = ySeq(split.train);
    % 仅标准化目标值以提高神经网络训练稳定性；计算指标前再换算回 kW。
    targetMean = mean(yTrain, "omitnan");
    targetStd = std(yTrain, "omitnan");
    if targetStd == 0 || isnan(targetStd)
        targetStd = 1;
    end
    yTrainNorm = (ySeq(split.train) - targetMean) ./ targetStd;
    yValNorm = (ySeq(split.val) - targetMean) ./ targetStd;

    layers = [
        sequenceInputLayer(inputSize)
        lstmLayer(cfg.lstmHiddenUnits(1), "OutputMode", "sequence")
        lstmLayer(cfg.lstmHiddenUnits(2), "OutputMode", "last")
        fullyConnectedLayer(1)
        regressionLayer
    ];

    options = trainingOptions("adam", ...
        "MaxEpochs", cfg.maxEpochs, ...
        "MiniBatchSize", cfg.miniBatchSize, ...
        "InitialLearnRate", cfg.initialLearnRate, ...
        "GradientThreshold", cfg.gradientThreshold, ...
        "LearnRateSchedule", "piecewise", ...
        "LearnRateDropPeriod", cfg.learnRateDropPeriod, ...
        "LearnRateDropFactor", cfg.learnRateDropFactor, ...
        "ValidationData", {XSeq(split.val), yValNorm}, ...
        "ValidationPatience", cfg.validationPatience, ...
        "Shuffle", "every-epoch", ...
        "ExecutionEnvironment", cfg.executionEnvironment, ...
        "Verbose", true, ...
        "Plots", trainingPlotMode(cfg));

    result.model = trainNetwork(XSeq(split.train), yTrainNorm, layers, options);
    yPredNorm = predict(result.model, XSeq(split.test), "MiniBatchSize", cfg.miniBatchSize);
    result.yPredTest = yPredNorm * targetStd + targetMean;
    result.targetMean = targetMean;
    result.targetStd = targetStd;
else
    fprintf("    未检测到 Deep Learning Toolbox，使用移动平均回退模型。\n");
    result.model = "fallback_moving_average";
    result.yPredTest = movingAverageFallback(ySeq, split.test, cfg.sequenceLength);
end
end

function result = trainBpOrFallback(cfg, X, y, split)
%TRAINBPORFALLBACK 优先训练 BP 神经网络；不可用时回退到线性回归。
result = struct("model", [], "yPredTest", []);

hasNeuralNet = exist("fitnet", "file") == 2;
if hasNeuralNet
    fprintf("    检测到 Neural Network Toolbox，使用 fitnet。\n");
    net = fitnet(cfg.bpHiddenUnits);
    net.divideFcn = "divideind";
    net.divideParam.trainInd = split.train;
    net.divideParam.valInd = split.val;
    net.divideParam.testInd = split.test;
    net.trainParam.showWindow = false;
    if cfg.showTrainingProgress
        net.trainParam.showWindow = true;
    end
    result.model = train(net, X', y');
    result.yPredTest = result.model(X(split.test, :)')';
else
    fprintf("    未检测到 fitnet，使用线性回归回退模型。\n");
    mdl = fitlm(X(split.train, :), y(split.train));
    result.model = mdl;
    result.yPredTest = predict(mdl, X(split.test, :));
end
end

function plotMode = trainingPlotMode(cfg)
%TRAININGPLOTMODE 将 cfg.showTrainingProgress 映射为 MATLAB trainingOptions 参数。
if cfg.showTrainingProgress
    plotMode = "training-progress";
else
    plotMode = "none";
end
end

function yPred = movingAverageFallback(y, testIdx, windowSize)
%MOVINGAVERAGEFALLBACK LSTM 不可训练时使用的简单移动平均基准。
yPred = zeros(numel(testIdx), 1);
for i = 1:numel(testIdx)
    idx = testIdx(i);
    startIdx = max(1, idx - windowSize);
    yPred(i) = mean(y(startIdx:(idx - 1)), "omitnan");
end
end

function metrics = calculateMetrics(cfg, yTrue, yPred)
%CALCULATEMETRICS 返回物理量纲下的常用回归指标。
yTrue = yTrue(:);
yPred = yPred(:);
valid = ~isnan(yTrue) & ~isnan(yPred);
yTrue = yTrue(valid);
yPred = yPred(valid);

err = yTrue - yPred;
metrics.RMSE = sqrt(mean(err .^ 2));
metrics.MAE = mean(abs(err));
% 对 MAPE 分母做下限约束，避免低负荷时百分比异常波动。
metrics.MAPE = mean(abs(err ./ max(abs(yTrue), cfg.mapeMinLoadKw))) * 100;
metrics.R2 = 1 - sum(err .^ 2) / sum((yTrue - mean(yTrue)) .^ 2);
end

function result = generateLoadProfile(cfg, result, X, y)
%GENERATELOADPROFILE 预测完整可用序列，用于后续容量配置。
if strcmp(result.lstm.model, "fallback_moving_average")
    fullPrediction = result.yPredLSTM;
    fprintf("    警告：LSTM 模型不可用，仅使用测试集预测结果。\n");
else
    [XSeqFull, ~] = buildSequences(X, y, cfg.sequenceLength);
    yPredNorm = predict(result.lstm.model, XSeqFull, "MiniBatchSize", cfg.miniBatchSize);
    fullPrediction = yPredNorm * result.lstm.targetStd + result.lstm.targetMean;
end

fullPrediction = fullPrediction(:);
result.predictedTotalLoadKw = fullPrediction;
result.predictedProfile = struct();
result.predictedProfile.totalCoolingLoadKw = fullPrediction;
% designLoadKw 为选定置信分位数负荷；representativeLoadKw 为部分负荷和生命周期能耗计算使用的平均负荷。
result.designLoadKw = quantileValue(fullPrediction, cfg.designConfidenceLevel);
result.representativeLoadKw = mean(fullPrediction, "omitnan");

fprintf("    预测曲线：%d 个样本，设计负荷=%.2f kW，代表负荷=%.2f kW。\n", ...
    numel(fullPrediction), result.designLoadKw, result.representativeLoadKw);
end

function models = trainSubsystemModels(cfg, dataClean)
%TRAINSUBSYSTEMMODELS 拟合总负荷到子系统需求的简化回归关系。
models = struct();

hasFitlm = exist("fitlm", "file") == 2;
if ~hasFitlm
    fprintf("    警告：未检测到 Statistics Toolbox，使用简化线性回归。\n");
end

models.chiller = fitlm(dataClean.(cfg.targetName), dataClean.chiller_load_kw);
models.fan = fitlm(dataClean.(cfg.targetName), dataClean.fan_power_kw);
models.pump = fitlm(dataClean.(cfg.targetName), dataClean.pump_power_kw);
end

function result = predictSubsystemProfiles(cfg, result, models)
%PREDICTSUBSYSTEMPROFILES 将总负荷预测转换为设备子系统需求。
profile = result.predictedProfile.totalCoolingLoadKw(:);

% 负的回归预测没有物理意义，因此截断为零。
chillerProfile = max(predict(models.chiller, profile), 0);
fanProfile = max(predict(models.fan, profile), 0);
pumpProfile = max(predict(models.pump, profile), 0);
ahuProfile = max(profile * cfg.ahuAirflowPerKw, 0);

result.predictedProfile.chillerLoadKw = chillerProfile;
result.predictedProfile.fanPowerKw = fanProfile;
result.predictedProfile.pumpPowerKw = pumpProfile;
result.predictedProfile.ahuAirflow = ahuProfile;

% 分位数设计负荷将在步骤4中转换为容量约束。
result.chillerDesignLoadKw = quantileValue(chillerProfile, cfg.designConfidenceLevel);
result.fanDesignLoadKw = quantileValue(fanProfile, cfg.designConfidenceLevel);
result.pumpDesignLoadKw = quantileValue(pumpProfile, cfg.designConfidenceLevel);
result.ahuDesignLoadKw = quantileValue(ahuProfile, cfg.designConfidenceLevel);

result.chillerRepresentativeLoadKw = mean(chillerProfile, "omitnan");
result.fanRepresentativeLoadKw = mean(fanProfile, "omitnan");
result.pumpRepresentativeLoadKw = mean(pumpProfile, "omitnan");
result.ahuRepresentativeLoadKw = mean(ahuProfile, "omitnan");

fprintf("    子系统设计需求：冷机=%.1f kW，风机=%.1f kW，水泵=%.1f kW，AHU=%.0f m³/h。\n", ...
    result.chillerDesignLoadKw, result.fanDesignLoadKw, ...
    result.pumpDesignLoadKw, result.ahuDesignLoadKw);
end

function result = buildSubsystemDemandOutputs(cfg, result)
%BUILDSUBSYSTEMDEMANDOUTPUTS 生成需求分位数表和情景需求表。
profiles = result.predictedProfile;
subsystem = ["total"; "chiller"; "fan"; "pump"; "ahu"];
unit = ["kW"; "kW"; "kW"; "kW"; "m3_per_h"];
seriesList = {
    profiles.totalCoolingLoadKw(:)
    profiles.chillerLoadKw(:)
    profiles.fanPowerKw(:)
    profiles.pumpPowerKw(:)
    profiles.ahuAirflow(:)
};

quantileColumns = strings(1, numel(cfg.capacityConfidenceLevels));
quantileValues = zeros(numel(subsystem), numel(cfg.capacityConfidenceLevels));
for j = 1:numel(cfg.capacityConfidenceLevels)
    level = cfg.capacityConfidenceLevels(j);
    quantileColumns(j) = "P" + string(round(level * 100));
    for i = 1:numel(subsystem)
        quantileValues(i, j) = quantileValue(seriesList{i}, level);
    end
end

result.subsystemDemandQuantiles = table(subsystem, unit);
for j = 1:numel(quantileColumns)
    % 根据 cfg.capacityConfidenceLevels 动态添加 P50/P90/P95/P99 等列。
    result.subsystemDemandQuantiles.(quantileColumns(j)) = quantileValues(:, j);
end
maxDemand = zeros(numel(subsystem), 1);
for i = 1:numel(subsystem)
    maxDemand(i) = max(seriesList{i}, [], "omitnan");
end
result.subsystemDemandQuantiles.maxDemand = maxDemand;

scenarioNames = cfg.scenarioNames(:);
scenarioQuantiles = [cfg.typicalQuantile; cfg.peakQuantile; cfg.extremeQuantile];
totalCoolingLoadKw = zeros(numel(scenarioNames), 1);
chillerDemandKw = zeros(numel(scenarioNames), 1);
fanDemandKw = zeros(numel(scenarioNames), 1);
pumpDemandKw = zeros(numel(scenarioNames), 1);
ahuDemand = zeros(numel(scenarioNames), 1);

for i = 1:numel(scenarioNames)
    q = scenarioQuantiles(i);
    % 各情景需求值取自预测子系统曲线的对应分位数。
    totalCoolingLoadKw(i) = quantileValue(profiles.totalCoolingLoadKw, q);
    chillerDemandKw(i) = quantileValue(profiles.chillerLoadKw, q);
    fanDemandKw(i) = quantileValue(profiles.fanPowerKw, q);
    pumpDemandKw(i) = quantileValue(profiles.pumpPowerKw, q);
    ahuDemand(i) = quantileValue(profiles.ahuAirflow, q);

    scenario = struct();
    scenario.name = scenarioNames(i);
    scenario.quantile = q;
    scenario.totalCoolingLoadKw = totalCoolingLoadKw(i);
    scenario.chillerDemandKw = chillerDemandKw(i);
    scenario.fanDemandKw = fanDemandKw(i);
    scenario.pumpDemandKw = pumpDemandKw(i);
    scenario.ahuDemand = ahuDemand(i);
    result.scenarioDemand.(scenarioNames(i)) = scenario;
end

result.scenarioDemandTable = table(scenarioNames, scenarioQuantiles, totalCoolingLoadKw, ...
    chillerDemandKw, fanDemandKw, pumpDemandKw, ahuDemand, ...
    'VariableNames', {'scenario', 'quantile', 'totalCoolingLoadKw', ...
    'chillerDemandKw', 'fanDemandKw', 'pumpDemandKw', 'ahuDemand'});
end

function value = quantileValue(values, level)
%QUANTILEVALUE 不依赖额外工具箱的轻量经验分位数函数。
values = values(:);
values = values(~isnan(values));
if isempty(values)
    value = NaN;
    return;
end
values = sort(values);
idx = max(1, min(numel(values), ceil(level * numel(values))));
value = values(idx);
end

function plotStep3Figures(cfg, predictionResult)
%PLOTSTEP3FIGURES 导出实测-预测对比图和模型误差对比图。
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

% LSTM 测试集曲线。
fig1 = figure("Name", "步骤3 - LSTM 预测", "Visible", figureVisibility(cfg));
plot(predictionResult.yTestLSTM, "LineWidth", 1.4);
hold on;
plot(predictionResult.yPredLSTM, "LineWidth", 1.4);
hold off;
xlabel("测试样本");
ylabel("冷负荷 / kW");
title("LSTM 负荷预测");
legend("实测值", "预测值", "Location", "best");
grid on;
saveFigureIfNeeded(cfg, fig1, "step3_lstm_prediction.png");

% BP 对比模型曲线。
fig2 = figure("Name", "步骤3 - BP 预测", "Visible", figureVisibility(cfg));
plot(predictionResult.yTest, "LineWidth", 1.4);
hold on;
plot(predictionResult.yPredBP, "LineWidth", 1.4);
hold off;
xlabel("测试样本");
ylabel("冷负荷 / kW");
title("BP 负荷预测");
legend("实测值", "预测值", "Location", "best");
grid on;
saveFigureIfNeeded(cfg, fig2, "step3_bp_prediction.png");

% RMSE 对比用于论文结果部分展示预测精度差异。
fig3 = figure("Name", "步骤3 - 模型指标", "Visible", figureVisibility(cfg));
bar(categorical(predictionResult.metrics.model), predictionResult.metrics.RMSE);
ylabel("RMSE / kW");
title("预测误差对比");
grid on;
saveFigureIfNeeded(cfg, fig3, "step3_model_rmse_comparison.png");
end

function visible = figureVisibility(cfg)
%FIGUREVISIBILITY 将 showFigures 标志转换为 MATLAB 图窗 Visible 属性。
if cfg.showFigures
    visible = "on";
else
    visible = "off";
end
end

function saveFigureIfNeeded(cfg, fig, fileName)
%SAVEFIGUREIFNEEDED 仅在 cfg.saveFigures 启用时写出 PNG 图片。
if cfg.saveFigures
    ensureFigureDir(cfg);
    filePath = fullfile(cfg.figureDir, fileName);
    if isfile(filePath)
        delete(filePath);
    end
    try
        exportgraphics(fig, filePath, "Resolution", 300);
    catch
        saveas(fig, filePath);
    end
end
end

function ensureFigureDir(cfg)
%ENSUREFIGUREDIR 支持单独运行本步骤时自动创建图片输出目录。
if ~exist(cfg.figureDir, "dir")
    mkdir(cfg.figureDir);
end
end

function tableOut = localizePredictionMetricsForOutput(tableIn)
%LOCALIZEPREDICTIONMETRICSFOROUTPUT 生成预测模型指标表的中文导出副本。
tableOut = tableIn;
tableOut.Properties.VariableNames = {'模型', '均方根误差_kW', '平均绝对误差_kW', '平均绝对百分比误差_百分比', '决定系数R2'};
end

function tableOut = localizeAblationTableForOutput(tableIn)
%LOCALIZEABLATIONTABLEFOROUTPUT 生成聚类标签消融表的中文导出副本。
tableOut = tableIn;
tableOut.model = localizeAblationModelNames(tableOut.model);
tableOut.Properties.VariableNames = {'模型', '是否使用聚类标签', '特征数量', ...
    '均方根误差_kW', '平均绝对误差_kW', '平均绝对百分比误差_百分比', '决定系数R2'};
end

function tableOut = localizeQuantileTableForOutput(tableIn)
%LOCALIZEQUANTILETABLEFOROUTPUT 生成子系统需求分位数表的中文导出副本。
tableOut = tableIn;
tableOut.subsystem = localizeSubsystemNames(tableOut.subsystem);
tableOut.unit = localizeUnitNames(tableOut.unit);
names = string(tableOut.Properties.VariableNames);
names(names == "subsystem") = "子系统";
names(names == "unit") = "单位";
names(names == "maxDemand") = "最大需求";
tableOut.Properties.VariableNames = cellstr(names);
end

function tableOut = localizeScenarioTableForOutput(tableIn)
%LOCALIZESCENARIOTABLEFOROUTPUT 生成情景需求表的中文导出副本。
tableOut = tableIn;
tableOut.scenario = localizeScenarioNames(tableOut.scenario);
tableOut.Properties.VariableNames = {'情景', '分位数', '总冷负荷_kW', ...
    '冷机需求_kW', '风机需求_kW', '水泵需求_kW', 'AHU风量需求_m3_h'};
end

function namesOut = localizeAblationModelNames(namesIn)
%LOCALIZEABLATIONMODELNAMES 将消融实验模型名转换为中文展示名。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "lstm_without_cluster"
            namesOut(i) = "不含聚类标签的LSTM";
        case "lstm_with_cluster"
            namesOut(i) = "含聚类标签的LSTM";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function namesOut = localizeSubsystemNames(namesIn)
%LOCALIZESUBSYSTEMNAMES 将子系统英文名转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "total"
            namesOut(i) = "总冷负荷";
        case "chiller"
            namesOut(i) = "冷机";
        case "fan"
            namesOut(i) = "风机";
        case "pump"
            namesOut(i) = "水泵";
        case "ahu"
            namesOut(i) = "AHU";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function namesOut = localizeScenarioNames(namesIn)
%LOCALIZESCENARIONAMES 将情景英文名转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "typical"
            namesOut(i) = "典型情景";
        case "peak"
            namesOut(i) = "峰值情景";
        case "extreme"
            namesOut(i) = "极端情景";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function namesOut = localizeUnitNames(namesIn)
%LOCALIZEUNITNAMES 将单位展示名转换为中文或规范写法。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "m3_per_h"
            namesOut(i) = "m3/h";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end
