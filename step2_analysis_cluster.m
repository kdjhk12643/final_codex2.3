function analysisResult = step2_analysis_cluster(cfg, dataClean, featureData)
%STEP2_ANALYSIS_CLUSTER Pearson ranking, load decomposition, and K-Means clustering.

stepTimer = tic;
rng(cfg.rngSeed);

analysisResult = struct();
fprintf("  Step 2.1 Ranking Pearson correlations against %s...\n", cfg.targetName);
analysisResult.correlationTable = rankPearsonFeatures(cfg, featureData);
analysisResult.selectedFeatures = analysisResult.correlationTable.feature( ...
    1:min(cfg.topFeatureNum, height(analysisResult.correlationTable)));
fprintf("  Selected top %d features: %s\n", numel(analysisResult.selectedFeatures), strjoin(analysisResult.selectedFeatures', ", "));

fprintf("  Step 2.2 Calculating load component ratios...\n");
analysisResult.loadComponentRatio = calculateLoadComponentRatio(cfg, dataClean);

fprintf("  Step 2.3 Building daily load curves and testing K = %s...\n", mat2str(cfg.clusterKRange));
[dailyCurves, dailyDates] = buildDailyLoadCurves(cfg, dataClean);
[bestK, clusterLabel, silhouetteTable] = chooseBestClusterK(cfg, dailyCurves);
fprintf("  Best K by mean silhouette: %d.\n", bestK);

analysisResult.dailyDates = dailyDates;
analysisResult.dailyLoadCurves = dailyCurves;
analysisResult.bestK = bestK;
analysisResult.clusterLabel = clusterLabel;
analysisResult.silhouetteTable = silhouetteTable;

pearsonFile = fullfile(cfg.tableDir, "step2_pearson_features.csv");
ratioFile = fullfile(cfg.tableDir, "step2_load_component_ratio.csv");
clusterFile = fullfile(cfg.tableDir, "step2_cluster_silhouette.csv");
writetable(analysisResult.correlationTable, pearsonFile);
writetable(analysisResult.loadComponentRatio, ratioFile);
writetable(silhouetteTable, clusterFile);

plotStep2Figures(cfg, analysisResult);

fprintf("  Saved: %s\n", pearsonFile);
fprintf("  Saved: %s\n", ratioFile);
fprintf("  Saved: %s\n", clusterFile);
fprintf("  Step 2 finished in %.1f seconds.\n", toc(stepTimer));
end

function plotStep2Figures(cfg, analysisResult)
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

topN = min(cfg.topFeatureNum, height(analysisResult.correlationTable));
fig1 = figure("Name", "Step 2 - Pearson Feature Ranking", "Visible", figureVisibility(cfg));
bar(categorical(analysisResult.correlationTable.feature(1:topN)), ...
    analysisResult.correlationTable.absPearsonR(1:topN));
ylabel("|Pearson R|");
title("Key Factors Related to Cooling Load");
grid on;
xtickangle(35);
saveFigureIfNeeded(cfg, fig1, "step2_pearson_feature_ranking.png");

fig2 = figure("Name", "Step 2 - Load Component Ratio", "Visible", figureVisibility(cfg));
pie(analysisResult.loadComponentRatio.ratio, analysisResult.loadComponentRatio.component);
title("Average Cooling Load Component Ratio");
saveFigureIfNeeded(cfg, fig2, "step2_load_component_ratio.png");

fig3 = figure("Name", "Step 2 - Typical Daily Load Clusters", "Visible", figureVisibility(cfg));
hold on;
colors = lines(analysisResult.bestK);
for k = 1:analysisResult.bestK
    idx = analysisResult.clusterLabel == k;
    plot(mean(analysisResult.dailyLoadCurves(idx, :), 1, "omitnan"), ...
        "LineWidth", 2, "Color", colors(k, :));
end
hold off;
xlabel("15-min time point in a day");
ylabel("Normalized load");
title("Typical Daily Cooling Load Patterns");
legend("Cluster " + string(1:analysisResult.bestK), "Location", "best");
grid on;
saveFigureIfNeeded(cfg, fig3, "step2_daily_load_clusters.png");
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

function correlationTable = rankPearsonFeatures(cfg, featureData)
varNames = string(featureData.Properties.VariableNames);
featureNames = setdiff(varNames, [cfg.timestampName, cfg.targetName], "stable");

target = featureData.(cfg.targetName);
feature = strings(numel(featureNames), 1);
pearsonR = zeros(numel(featureNames), 1);
absPearsonR = zeros(numel(featureNames), 1);

for i = 1:numel(featureNames)
    values = featureData.(featureNames(i));
    r = corr(values, target, "Rows", "complete", "Type", "Pearson");
    feature(i) = featureNames(i);
    pearsonR(i) = r;
    absPearsonR(i) = abs(r);
end

correlationTable = table(feature, pearsonR, absPearsonR);
correlationTable = sortrows(correlationTable, "absPearsonR", "descend");
end

function ratioTable = calculateLoadComponentRatio(cfg, dataClean)
componentNames = cfg.loadComponentNames(ismember(cfg.loadComponentNames, string(dataClean.Properties.VariableNames)));
componentMean = zeros(numel(componentNames), 1);
componentRatio = zeros(numel(componentNames), 1);
totalMean = mean(dataClean.(cfg.targetName), "omitnan");

for i = 1:numel(componentNames)
    componentMean(i) = mean(dataClean.(componentNames(i)), "omitnan");
    componentRatio(i) = componentMean(i) / totalMean;
end

ratioTable = table(componentNames(:), componentMean, componentRatio, ...
    'VariableNames', {'component', 'meanLoadKw', 'ratio'});
end

function [dailyCurves, dailyDates] = buildDailyLoadCurves(cfg, dataClean)
dates = dateshift(dataClean.(cfg.timestampName), "start", "day");
dailyDates = unique(dates);
dailyCurves = nan(numel(dailyDates), cfg.dailyPointNum);

for i = 1:numel(dailyDates)
    idx = dates == dailyDates(i);
    dayLoad = dataClean.(cfg.targetName)(idx);
    n = min(numel(dayLoad), cfg.dailyPointNum);
    curve = nan(1, cfg.dailyPointNum);
    curve(1:n) = dayLoad(1:n);
    curve = fillmissing(curve, "linear", 2);
    curve = fillmissing(curve, "nearest", 2);
    minValue = min(curve);
    maxValue = max(curve);
    if maxValue > minValue
        curve = (curve - minValue) ./ (maxValue - minValue);
    else
        curve = zeros(size(curve));
    end
    dailyCurves(i, :) = curve;
end
end

function [bestK, bestLabel, silhouetteTable] = chooseBestClusterK(cfg, dailyCurves)
kValues = cfg.clusterKRange(:);
meanSilhouette = nan(numel(kValues), 1);
labels = cell(numel(kValues), 1);

for i = 1:numel(kValues)
    k = kValues(i);
    fprintf("    Running K-Means for K = %d...\n", k);
    labels{i} = kmeans(dailyCurves, k, "Replicates", 10, "MaxIter", 1000);
    s = silhouette(dailyCurves, labels{i});
    meanSilhouette(i) = mean(s, "omitnan");
end

[~, bestIdx] = max(meanSilhouette);
bestK = kValues(bestIdx);
bestLabel = labels{bestIdx};
silhouetteTable = table(kValues, meanSilhouette, ...
    'VariableNames', {'K', 'meanSilhouette'});
end
