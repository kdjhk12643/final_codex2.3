function predictionResult = step3_load_prediction(cfg, featureData, analysisResult)
%STEP3_LOAD_PREDICTION Train LSTM and BP models, then evaluate predictions.

stepTimer = tic;
predictionResult = struct();

selectedFeatures = string(analysisResult.selectedFeatures);
selectedFeatures = selectedFeatures(ismember(selectedFeatures, string(featureData.Properties.VariableNames)));

fprintf("  Step 3.1 Building prediction matrix with %d selected features...\n", numel(selectedFeatures));
[X, y] = buildMatrix(featureData, selectedFeatures, cfg.targetName);
split = splitIndexes(numel(y), cfg);
fprintf("  Samples: total=%d, train=%d, val=%d, test=%d.\n", ...
    numel(y), numel(split.train), numel(split.val), numel(split.test));

predictionResult.selectedFeatures = selectedFeatures;
predictionResult.split = split;

fprintf("  Step 3.2 Building LSTM sequences, sequence length = %d...\n", cfg.sequenceLength);
[XSeq, ySeq] = buildSequences(X, y, cfg.sequenceLength);
seqSplit = splitIndexes(numel(ySeq), cfg);

fprintf("  Step 3.3 Training LSTM, maxEpochs=%d, miniBatchSize=%d...\n", cfg.maxEpochs, cfg.miniBatchSize);
predictionResult.lstm = trainLstmOrFallback(cfg, XSeq, ySeq, seqSplit);
fprintf("  Step 3.4 Training BP comparison model...\n");
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

fprintf("  Step 3.5 Generating full predicted load profile for capacity optimization...\n");
predictionResult = generateLoadProfile(cfg, predictionResult, X, y);

predictionResult.metrics = table( ...
    ["LSTM"; "BP"], ...
    [predictionResult.metricsLSTM.RMSE; predictionResult.metricsBP.RMSE], ...
    [predictionResult.metricsLSTM.MAE; predictionResult.metricsBP.MAE], ...
    [predictionResult.metricsLSTM.MAPE; predictionResult.metricsBP.MAPE], ...
    [predictionResult.metricsLSTM.R2; predictionResult.metricsBP.R2], ...
    'VariableNames', {'model', 'RMSE', 'MAE', 'MAPE', 'R2'});

metricsFile = fullfile(cfg.tableDir, "step3_prediction_metrics.csv");
writetable(predictionResult.metrics, metricsFile);

plotStep3Figures(cfg, predictionResult);

fprintf("  LSTM metrics: RMSE=%.3f, MAE=%.3f, MAPE=%.2f%%, R2=%.4f.\n", ...
    predictionResult.metricsLSTM.RMSE, predictionResult.metricsLSTM.MAE, ...
    predictionResult.metricsLSTM.MAPE, predictionResult.metricsLSTM.R2);
fprintf("  BP metrics:   RMSE=%.3f, MAE=%.3f, MAPE=%.2f%%, R2=%.4f.\n", ...
    predictionResult.metricsBP.RMSE, predictionResult.metricsBP.MAE, ...
    predictionResult.metricsBP.MAPE, predictionResult.metricsBP.R2);
fprintf("  Saved: %s\n", metricsFile);
fprintf("  Step 3 finished in %.1f seconds.\n", toc(stepTimer));
end

function [X, y] = buildMatrix(featureData, selectedFeatures, targetName)
X = featureData{:, selectedFeatures};
y = featureData.(targetName);
valid = all(~isnan(X), 2) & ~isnan(y);
X = X(valid, :);
y = y(valid);
end

function split = splitIndexes(n, cfg)
nTrain = floor(n * cfg.trainRatio);
nVal = floor(n * cfg.valRatio);
split.train = 1:nTrain;
split.val = (nTrain + 1):(nTrain + nVal);
split.test = (nTrain + nVal + 1):n;
end

function [XSeq, ySeq] = buildSequences(X, y, sequenceLength)
n = size(X, 1) - sequenceLength;
XSeq = cell(n, 1);
ySeq = zeros(n, 1);

for i = 1:n
    XSeq{i} = X(i:(i + sequenceLength - 1), :)';
    ySeq(i) = y(i + sequenceLength);
end
end

function result = trainLstmOrFallback(cfg, XSeq, ySeq, split)
result = struct("model", [], "yPredTest", []);

hasDeepLearning = exist("trainNetwork", "file") == 2 && exist("lstmLayer", "file") == 2;
if hasDeepLearning
    fprintf("    Deep Learning Toolbox detected. Using trainNetwork.\n");
    inputSize = size(XSeq{1}, 1);
    yTrain = ySeq(split.train);
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
if cfg.showTrainingProgress
    plotMode = "training-progress";
else
    plotMode = "none";
end
end

function yPred = movingAverageFallback(y, testIdx, windowSize)
yPred = zeros(numel(testIdx), 1);
for i = 1:numel(testIdx)
    idx = testIdx(i);
    startIdx = max(1, idx - windowSize);
    yPred(i) = mean(y(startIdx:(idx - 1)), "omitnan");
end
end

function metrics = calculateMetrics(cfg, yTrue, yPred)
yTrue = yTrue(:);
yPred = yPred(:);
valid = ~isnan(yTrue) & ~isnan(yPred);
yTrue = yTrue(valid);
yPred = yPred(valid);

err = yTrue - yPred;
metrics.RMSE = sqrt(mean(err .^ 2));
metrics.MAE = mean(abs(err));
metrics.MAPE = mean(abs(err ./ max(abs(yTrue), cfg.mapeMinLoadKw))) * 100;
metrics.R2 = 1 - sum(err .^ 2) / sum((yTrue - mean(yTrue)) .^ 2);
end

function result = generateLoadProfile(cfg, result, X, y)
if strcmp(result.lstm.model, "fallback_moving_average")
    fullPrediction = result.yPredLSTM;
    fprintf("    Warning: LSTM model unavailable, using test-set predictions only.\n");
else
    [XSeqFull, ~] = buildSequences(X, y, cfg.sequenceLength);
    yPredNorm = predict(result.lstm.model, XSeqFull, "MiniBatchSize", cfg.miniBatchSize);
    fullPrediction = yPredNorm * result.lstm.targetStd + result.lstm.targetMean;
end

result.predictedProfile = fullPrediction(:);
result.designLoadKw = max(fullPrediction, [], "omitnan");
result.representativeLoadKw = mean(fullPrediction, "omitnan");

fprintf("    Predicted profile: %d samples, design=%.2f kW, representative=%.2f kW.\n", ...
    numel(fullPrediction), result.designLoadKw, result.representativeLoadKw);
end

function plotStep3Figures(cfg, predictionResult)
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

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

fig3 = figure("Name", "Step 3 - Model Metrics", "Visible", figureVisibility(cfg));
bar(categorical(predictionResult.metrics.model), predictionResult.metrics.RMSE);
ylabel("RMSE / kW");
title("Prediction Error Comparison");
grid on;
saveFigureIfNeeded(cfg, fig3, "step3_model_rmse_comparison.png");
end

function visible = figureVisibility(cfg)
if cfg.showFigures
    visible = "on";
else
    visible = "off";
end
end

function saveFigureIfNeeded(cfg, fig, fileName)
if cfg.saveFigures
    exportgraphics(fig, fullfile(cfg.figureDir, fileName), "Resolution", 300);
end
end
