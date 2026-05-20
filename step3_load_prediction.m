function predictionResult = step3_load_prediction(cfg, featureData, dataClean, analysisResult)
%STEP3_LOAD_PREDICTION Train LSTM and BP models, then evaluate predictions.
% The prediction result becomes the bridge between statistical analysis and
% engineering sizing: it stores model metrics, full load profiles, and subsystem
% demand scenarios for step4 capacity optimization.

stepTimer = tic;
predictionResult = struct();

% Start from Step 2's Pearson-selected features, then add a standardized daily
% cluster label for the ablation experiment.
selectedFeatures = string(analysisResult.selectedFeatures);
selectedFeatures = selectedFeatures(ismember(selectedFeatures, string(featureData.Properties.VariableNames)));
clusterFeatureName = "cluster_label_zscore";
featureDataWithCluster = addClusterLabelFeature(cfg, featureData, analysisResult, clusterFeatureName);
selectedFeaturesWithCluster = unique([selectedFeatures; clusterFeatureName], "stable");

fprintf("  Step 3.1 Building prediction matrix with %d selected features...\n", numel(selectedFeatures));
% X and y keep chronological order; splitIndexes therefore creates a time-based
% train/validation/test split rather than a shuffled split.
[X, y] = buildMatrix(featureData, selectedFeatures, cfg.targetName);
split = splitIndexes(numel(y), cfg);
fprintf("  Samples: total=%d, train=%d, val=%d, test=%d.\n", ...
    numel(y), numel(split.train), numel(split.val), numel(split.test));

predictionResult.selectedFeatures = selectedFeatures;
predictionResult.clusterFeatureName = clusterFeatureName;
predictionResult.selectedFeaturesWithCluster = selectedFeaturesWithCluster;
predictionResult.split = split;

fprintf("  Step 3.2 Building LSTM sequences, sequence length = %d...\n", cfg.sequenceLength);
% LSTM samples are sliding windows of historical feature rows.
[XSeq, ySeq] = buildSequences(X, y, cfg.sequenceLength);
seqSplit = splitIndexes(numel(ySeq), cfg);

fprintf("  Step 3.3 Training LSTM, maxEpochs=%d, miniBatchSize=%d...\n", cfg.maxEpochs, cfg.miniBatchSize);
predictionResult.lstm = trainLstmOrFallback(cfg, XSeq, ySeq, seqSplit);
fprintf("  Step 3.4 Training BP comparison model...\n");
% The BP baseline removes load-lag features when possible, so it serves as a
% simpler static-feature comparison to the sequence-based LSTM.
bpFeatures = selectedFeatures(~startsWith(selectedFeatures, "load_lag_"));
if isempty(bpFeatures)
    bpFeatures = selectedFeatures;
end
[Xbp, ybp] = buildMatrix(featureData, bpFeatures, cfg.targetName);
bpSplit = splitIndexes(numel(ybp), cfg);
fprintf("  BP baseline uses %d static features and excludes load lag features.\n", numel(bpFeatures));
predictionResult.bpFeatures = bpFeatures;
predictionResult.bp = trainBpOrFallback(cfg, Xbp, ybp, bpSplit);

predictionResult.yTest = ybp(bpSplit.test);
predictionResult.yPredBP = predictionResult.bp.yPredTest;
predictionResult.metricsBP = calculateMetrics(cfg, predictionResult.yTest, predictionResult.yPredBP);

predictionResult.yTestLSTM = ySeq(seqSplit.test);
predictionResult.yPredLSTM = predictionResult.lstm.yPredTest;
predictionResult.metricsLSTM = calculateMetrics(cfg, predictionResult.yTestLSTM, predictionResult.yPredLSTM);

fprintf("  Step 3.5 Running cluster-label ablation experiment...\n");
% Train two LSTM variants to quantify whether the typical-day cluster label
% improves prediction accuracy.
predictionResult.clusterAblation = runClusterAblation( ...
    cfg, featureDataWithCluster, selectedFeatures, selectedFeaturesWithCluster, cfg.targetName);

fprintf("  Step 3.6 Generating full predicted load profile for capacity optimization...\n");
% Full predicted profile is used for design quantiles and annual energy
% calculations, not only for test-set accuracy reporting.
predictionResult = generateLoadProfile(cfg, predictionResult, X, y);

fprintf("  Step 3.7 Training subsystem regression models (chiller, fan, pump, AHU)...\n");
% These regressions map total cooling load to subsystem-level equipment demand.
subsystemModels = trainSubsystemModels(cfg, dataClean);
fprintf("    Chiller: %.4f × total_load + %.2f  (R²=%.3f)\n", ...
    subsystemModels.chiller.Coefficients.Estimate(2), ...
    subsystemModels.chiller.Coefficients.Estimate(1), ...
    subsystemModels.chiller.Rsquared.Ordinary);
fprintf("    Fan:     %.4f × total_load + %.2f  (R²=%.3f)\n", ...
    subsystemModels.fan.Coefficients.Estimate(2), ...
    subsystemModels.fan.Coefficients.Estimate(1), ...
    subsystemModels.fan.Rsquared.Ordinary);
fprintf("    Pump:    %.4f × total_load + %.2f  (R²=%.3f)\n", ...
    subsystemModels.pump.Coefficients.Estimate(2), ...
    subsystemModels.pump.Coefficients.Estimate(1), ...
    subsystemModels.pump.Rsquared.Ordinary);

fprintf("  Step 3.8 Predicting subsystem load profiles from LSTM prediction...\n");
% Apply subsystem models to the predicted total load profile so optimization can
% constrain chiller, fan, pump, and AHU capacities separately.
predictionResult = predictSubsystemProfiles(cfg, predictionResult, subsystemModels);

fprintf("  Step 3.9 Building subsystem confidence demand and scenario tables...\n");
predictionResult = buildSubsystemDemandOutputs(cfg, predictionResult);

predictionResult.metrics = table( ...
    ["LSTM"; "BP"], ...
    [predictionResult.metricsLSTM.RMSE; predictionResult.metricsBP.RMSE], ...
    [predictionResult.metricsLSTM.MAE; predictionResult.metricsBP.MAE], ...
    [predictionResult.metricsLSTM.MAPE; predictionResult.metricsBP.MAPE], ...
    [predictionResult.metricsLSTM.R2; predictionResult.metricsBP.R2], ...
    'VariableNames', {'model', 'RMSE', 'MAE', 'MAPE', 'R2'});

% Write model-performance and demand-scenario evidence for the thesis tables.
metricsFile = fullfile(cfg.tableDir, "step3_prediction_metrics.csv");
ablationFile = fullfile(cfg.tableDir, "step3_cluster_ablation_metrics.csv");
quantileFile = fullfile(cfg.tableDir, "step3_subsystem_demand_quantiles.csv");
scenarioFile = fullfile(cfg.tableDir, "step3_scenario_demand.csv");
writetable(predictionResult.metrics, metricsFile);
writetable(predictionResult.clusterAblation, ablationFile);
writetable(predictionResult.subsystemDemandQuantiles, quantileFile);
writetable(predictionResult.scenarioDemandTable, scenarioFile);

plotStep3Figures(cfg, predictionResult);

fprintf("  LSTM metrics: RMSE=%.3f, MAE=%.3f, MAPE=%.2f%%, R2=%.4f.\n", ...
    predictionResult.metricsLSTM.RMSE, predictionResult.metricsLSTM.MAE, ...
    predictionResult.metricsLSTM.MAPE, predictionResult.metricsLSTM.R2);
fprintf("  BP metrics:   RMSE=%.3f, MAE=%.3f, MAPE=%.2f%%, R2=%.4f.\n", ...
    predictionResult.metricsBP.RMSE, predictionResult.metricsBP.MAE, ...
    predictionResult.metricsBP.MAPE, predictionResult.metricsBP.R2);
fprintf("  Saved: %s\n", metricsFile);
fprintf("  Saved: %s\n", ablationFile);
fprintf("  Saved: %s\n", quantileFile);
fprintf("  Saved: %s\n", scenarioFile);
fprintf("  Step 3 finished in %.1f seconds.\n", toc(stepTimer));
end

function featureDataOut = addClusterLabelFeature(~, featureData, analysisResult, clusterFeatureName)
%ADDCLUSTERLABELFEATURE Broadcast each daily K-Means label to all samples in that day.
featureDataOut = featureData;
timestamps = featureDataOut.timestamp;
dates = dateshift(timestamps, "start", "day");
clusterValues = nan(height(featureDataOut), 1);

for i = 1:numel(analysisResult.dailyDates)
    idx = dates == analysisResult.dailyDates(i);
    clusterValues(idx) = analysisResult.clusterLabel(i);
end

% Fill any unmatched dates defensively, then z-score the categorical label so it
% is on a scale similar to other standardized predictors.
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
%RUNCLUSTERABLATION Compare LSTM performance with and without cluster labels.
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
%BUILDMATRIX Extract numeric predictors and drop rows with missing inputs.
X = featureData{:, selectedFeatures};
y = featureData.(targetName);
valid = all(~isnan(X), 2) & ~isnan(y);
X = X(valid, :);
y = y(valid);
end

function split = splitIndexes(n, cfg)
%SPLITINDEXES Create chronological train/validation/test index ranges.
nTrain = floor(n * cfg.trainRatio);
nVal = floor(n * cfg.valRatio);
split.train = 1:nTrain;
split.val = (nTrain + 1):(nTrain + nVal);
split.test = (nTrain + nVal + 1):n;
end

function [XSeq, ySeq] = buildSequences(X, y, sequenceLength)
%BUILDSEQUENCES Convert tabular samples into LSTM cell-array sequences.
n = size(X, 1) - sequenceLength;
XSeq = cell(n, 1);
ySeq = zeros(n, 1);

for i = 1:n
    % MATLAB sequence input expects features-by-timeStep layout for each sample.
    XSeq{i} = X(i:(i + sequenceLength - 1), :)';
    ySeq(i) = y(i + sequenceLength);
end
end

function result = trainLstmOrFallback(cfg, XSeq, ySeq, split)
%TRAINLSTMORFALLBACK Use Deep Learning Toolbox when available, otherwise a
% moving-average predictor keeps the rest of the workflow executable.
result = struct("model", [], "yPredTest", []);

hasDeepLearning = exist("trainNetwork", "file") == 2 && exist("lstmLayer", "file") == 2;
if hasDeepLearning
    fprintf("    Deep Learning Toolbox detected. Using trainNetwork.\n");
    inputSize = size(XSeq{1}, 1);
    yTrain = ySeq(split.train);
    % Normalize only the target for stable neural-network training; predictions
    % are transformed back to kW before metrics are calculated.
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
    fprintf("    Deep Learning Toolbox not detected. Using moving-average fallback.\n");
    result.model = "fallback_moving_average";
    result.yPredTest = movingAverageFallback(ySeq, split.test, cfg.sequenceLength);
end
end

function result = trainBpOrFallback(cfg, X, y, split)
%TRAINBPORFALLBACK Train a BP neural net if available, otherwise linear regression.
result = struct("model", [], "yPredTest", []);

hasNeuralNet = exist("fitnet", "file") == 2;
if hasNeuralNet
    fprintf("    Neural Network Toolbox detected. Using fitnet.\n");
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
    fprintf("    fitnet not detected. Using linear regression fallback.\n");
    mdl = fitlm(X(split.train, :), y(split.train));
    result.model = mdl;
    result.yPredTest = predict(mdl, X(split.test, :));
end
end

function plotMode = trainingPlotMode(cfg)
%TRAININGPLOTMODE Map cfg.showTrainingProgress to MATLAB trainingOptions syntax.
if cfg.showTrainingProgress
    plotMode = "training-progress";
else
    plotMode = "none";
end
end

function yPred = movingAverageFallback(y, testIdx, windowSize)
%MOVINGAVERAGEFALLBACK Simple baseline used when LSTM training is unavailable.
yPred = zeros(numel(testIdx), 1);
for i = 1:numel(testIdx)
    idx = testIdx(i);
    startIdx = max(1, idx - windowSize);
    yPred(i) = mean(y(startIdx:(idx - 1)), "omitnan");
end
end

function metrics = calculateMetrics(cfg, yTrue, yPred)
%CALCULATEMETRICS Return common regression metrics in physical units.
yTrue = yTrue(:);
yPred = yPred(:);
valid = ~isnan(yTrue) & ~isnan(yPred);
yTrue = yTrue(valid);
yPred = yPred(valid);

err = yTrue - yPred;
metrics.RMSE = sqrt(mean(err .^ 2));
metrics.MAE = mean(abs(err));
% MAPE denominator is clipped to avoid unstable percentages at very low load.
metrics.MAPE = mean(abs(err ./ max(abs(yTrue), cfg.mapeMinLoadKw))) * 100;
metrics.R2 = 1 - sum(err .^ 2) / sum((yTrue - mean(yTrue)) .^ 2);
end

function result = generateLoadProfile(cfg, result, X, y)
%GENERATELOADPROFILE Predict the full available sequence for capacity sizing.
if strcmp(result.lstm.model, "fallback_moving_average")
    fullPrediction = result.yPredLSTM;
    fprintf("    Warning: LSTM model unavailable, using test-set predictions only.\n");
else
    [XSeqFull, ~] = buildSequences(X, y, cfg.sequenceLength);
    yPredNorm = predict(result.lstm.model, XSeqFull, "MiniBatchSize", cfg.miniBatchSize);
    fullPrediction = yPredNorm * result.lstm.targetStd + result.lstm.targetMean;
end

fullPrediction = fullPrediction(:);
result.predictedTotalLoadKw = fullPrediction;
result.predictedProfile = struct();
result.predictedProfile.totalCoolingLoadKw = fullPrediction;
% designLoadKw is the selected confidence quantile; representativeLoadKw is the
% average load used by part-load and lifecycle-energy calculations.
result.designLoadKw = quantileValue(fullPrediction, cfg.designConfidenceLevel);
result.representativeLoadKw = mean(fullPrediction, "omitnan");

fprintf("    Predicted profile: %d samples, design=%.2f kW, representative=%.2f kW.\n", ...
    numel(fullPrediction), result.designLoadKw, result.representativeLoadKw);
end

function models = trainSubsystemModels(cfg, dataClean)
%TRAINSUBSYSTEMMODELS Fit simple regressions from total load to subsystem demand.
models = struct();

hasFitlm = exist("fitlm", "file") == 2;
if ~hasFitlm
    fprintf("    Warning: Statistics Toolbox not detected. Using simplified linear regression.\n");
end

models.chiller = fitlm(dataClean.(cfg.targetName), dataClean.chiller_load_kw);
models.fan = fitlm(dataClean.(cfg.targetName), dataClean.fan_power_kw);
models.pump = fitlm(dataClean.(cfg.targetName), dataClean.pump_power_kw);
end

function result = predictSubsystemProfiles(cfg, result, models)
%PREDICTSUBSYSTEMPROFILES Convert total-load prediction into equipment demands.
profile = result.predictedProfile.totalCoolingLoadKw(:);

% Negative regression predictions have no physical meaning, so clamp at zero.
chillerProfile = max(predict(models.chiller, profile), 0);
fanProfile = max(predict(models.fan, profile), 0);
pumpProfile = max(predict(models.pump, profile), 0);
ahuProfile = max(profile * cfg.ahuAirflowPerKw, 0);

result.predictedProfile.chillerLoadKw = chillerProfile;
result.predictedProfile.fanPowerKw = fanProfile;
result.predictedProfile.pumpPowerKw = pumpProfile;
result.predictedProfile.ahuAirflow = ahuProfile;

% Quantile design loads are the values later converted into capacity
% constraints in step4.
result.chillerDesignLoadKw = quantileValue(chillerProfile, cfg.designConfidenceLevel);
result.fanDesignLoadKw = quantileValue(fanProfile, cfg.designConfidenceLevel);
result.pumpDesignLoadKw = quantileValue(pumpProfile, cfg.designConfidenceLevel);
result.ahuDesignLoadKw = quantileValue(ahuProfile, cfg.designConfidenceLevel);

result.chillerRepresentativeLoadKw = mean(chillerProfile, "omitnan");
result.fanRepresentativeLoadKw = mean(fanProfile, "omitnan");
result.pumpRepresentativeLoadKw = mean(pumpProfile, "omitnan");
result.ahuRepresentativeLoadKw = mean(ahuProfile, "omitnan");

fprintf("    Subsystem design loads: chiller=%.1f kW, fan=%.1f kW, pump=%.1f kW, AHU=%.0f m³/h.\n", ...
    result.chillerDesignLoadKw, result.fanDesignLoadKw, ...
    result.pumpDesignLoadKw, result.ahuDesignLoadKw);
end

function result = buildSubsystemDemandOutputs(cfg, result)
%BUILDSUBSYSTEMDEMANDOUTPUTS Create demand quantile and scenario tables.
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
    % Add P50/P90/P95/P99 columns dynamically from cfg.capacityConfidenceLevels.
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
    % Scenario demand values are quantiles of the predicted subsystem profiles.
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
%QUANTILEVALUE Lightweight empirical quantile helper independent of toolboxes.
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
%PLOTSTEP3FIGURES Export observed-vs-predicted and model-comparison figures.
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

% LSTM test-set curve.
fig1 = figure("Name", "Step 3 - LSTM Prediction", "Visible", figureVisibility(cfg));
plot(predictionResult.yTestLSTM, "LineWidth", 1.4);
hold on;
plot(predictionResult.yPredLSTM, "LineWidth", 1.4);
hold off;
xlabel("Test sample");
ylabel("Cooling load / kW");
title("LSTM Load Prediction");
legend("Observed", "Predicted", "Location", "best");
grid on;
saveFigureIfNeeded(cfg, fig1, "step3_lstm_prediction.png");

% BP comparison curve.
fig2 = figure("Name", "Step 3 - BP Prediction", "Visible", figureVisibility(cfg));
plot(predictionResult.yTest, "LineWidth", 1.4);
hold on;
plot(predictionResult.yPredBP, "LineWidth", 1.4);
hold off;
xlabel("Test sample");
ylabel("Cooling load / kW");
title("BP Load Prediction");
legend("Observed", "Predicted", "Location", "best");
grid on;
saveFigureIfNeeded(cfg, fig2, "step3_bp_prediction.png");

% RMSE comparison highlights prediction accuracy for the thesis result section.
fig3 = figure("Name", "Step 3 - Model Metrics", "Visible", figureVisibility(cfg));
bar(categorical(predictionResult.metrics.model), predictionResult.metrics.RMSE);
ylabel("RMSE / kW");
title("Prediction Error Comparison");
grid on;
saveFigureIfNeeded(cfg, fig3, "step3_model_rmse_comparison.png");
end

function visible = figureVisibility(cfg)
%FIGUREVISIBILITY Convert the showFigures flag to MATLAB's figure Visible value.
if cfg.showFigures
    visible = "on";
else
    visible = "off";
end
end

function saveFigureIfNeeded(cfg, fig, fileName)
%SAVEFIGUREIFNEEDED Write PNG figures only when cfg.saveFigures is enabled.
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
%ENSUREFIGUREDIR Create the figure output folder for direct step execution.
if ~exist(cfg.figureDir, "dir")
    mkdir(cfg.figureDir);
end
end
