function analysisResult = step2_analysis_cluster(cfg, dataClean, featureData)
%STEP2_ANALYSIS_CLUSTER 进行 Pearson 排序、负荷分解和 K-Means 聚类。
% 本步骤将运行数据转换为可解释的论文证据：关键影响因素、分项负荷占比和典型日冷负荷模式。

stepTimer = tic;
% 固定随机流，使重复运行 K-Means 时结果可复现。
rng(cfg.rngSeed);

analysisResult = struct();
fprintf("  步骤 2.1 计算各特征与 %s 的 Pearson 相关性排序...\n", cfg.targetName);
% 相关性排序用于筛选后续预测模型中最相关的标准化预测因子。
analysisResult.correlationTable = rankPearsonFeatures(cfg, featureData);
analysisResult.selectedFeatures = analysisResult.correlationTable.feature( ...
    1:min(cfg.topFeatureNum, height(analysisResult.correlationTable)));
fprintf("  已选择前 %d 个特征：%s\n", numel(analysisResult.selectedFeatures), strjoin(localizeFeatureNames(analysisResult.selectedFeatures)', "、"));

fprintf("  步骤 2.2 计算负荷分项占比...\n");
% 分项占比用于说明车站冷负荷的主要来源。
analysisResult.loadComponentRatio = calculateLoadComponentRatio(cfg, dataClean);

fprintf("  步骤 2.3 构建日负荷曲线并测试 K = %s...\n", mat2str(cfg.clusterKRange));
% dailyCurves 每一行表示一天，各列为固定的 15 分钟时间点。
[dailyCurves, dailyDates] = buildDailyLoadCurves(cfg, dataClean);
[bestK, clusterLabel, silhouetteTable] = chooseBestClusterK(cfg, dailyCurves);
fprintf("  按平均轮廓系数选择的最优 K：%d。\n", bestK);

analysisResult.dailyDates = dailyDates;
analysisResult.dailyLoadCurves = dailyCurves;
analysisResult.bestK = bestK;
analysisResult.clusterLabel = clusterLabel;
analysisResult.silhouetteTable = silhouetteTable;

pearsonFile = fullfile(cfg.tableDir, "step2_pearson_features.csv");
ratioFile = fullfile(cfg.tableDir, "step2_load_component_ratio.csv");
clusterFile = fullfile(cfg.tableDir, "step2_cluster_silhouette.csv");
writetable(localizeCorrelationTableForOutput(analysisResult.correlationTable), pearsonFile);
writetable(localizeRatioTableForOutput(analysisResult.loadComponentRatio), ratioFile);
writetable(localizeSilhouetteTableForOutput(silhouetteTable), clusterFile);

% 数值证据表写出后，再导出对应图件。
plotStep2Figures(cfg, analysisResult);

fprintf("  已保存：%s\n", pearsonFile);
fprintf("  已保存：%s\n", ratioFile);
fprintf("  已保存：%s\n", clusterFile);
fprintf("  步骤 2 完成，用时 %.1f 秒。\n", toc(stepTimer));
end

function plotStep2Figures(cfg, analysisResult)
%PLOTSTEP2FIGURES 可视化特征重要性、分项负荷占比和聚类结果。
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

% 柱状图展示与冷负荷目标最强的线性关系。
topN = min(cfg.topFeatureNum, height(analysisResult.correlationTable));
fig1 = figure("Name", "步骤2 - Pearson 特征排序", "Visible", figureVisibility(cfg));
bar(categorical(localizeFeatureNames(analysisResult.correlationTable.feature(1:topN))), ...
    analysisResult.correlationTable.absPearsonR(1:topN));
ylabel("|Pearson 相关系数|");
title("冷负荷关键影响因素");
grid on;
xtickangle(35);
saveFigureIfNeeded(cfg, fig1, "step2_pearson_feature_ranking.png");

% 饼图展示平均物理分项负荷占比。
fig2 = figure("Name", "步骤2 - 分项负荷占比", "Visible", figureVisibility(cfg));
pie(analysisResult.loadComponentRatio.ratio, localizeFeatureNames(analysisResult.loadComponentRatio.component));
title("平均冷负荷分项占比");
saveFigureIfNeeded(cfg, fig2, "step2_load_component_ratio.png");

% 各类均值曲线描述 K-Means 识别出的典型日负荷模式。
fig3 = figure("Name", "步骤2 - 典型日负荷聚类", "Visible", figureVisibility(cfg));
hold on;
colors = lines(analysisResult.bestK);
for k = 1:analysisResult.bestK
    idx = analysisResult.clusterLabel == k;
    plot(mean(analysisResult.dailyLoadCurves(idx, :), 1, "omitnan"), ...
        "LineWidth", 2, "Color", colors(k, :));
end
hold off;
xlabel("日内 15 分钟时间点");
ylabel("归一化负荷");
title("典型日冷负荷模式");
legend("第 " + string(1:analysisResult.bestK) + " 类", "Location", "best");
grid on;
saveFigureIfNeeded(cfg, fig3, "step2_daily_load_clusters.png");
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

function correlationTable = rankPearsonFeatures(cfg, featureData)
%RANKPEARSONFEATURES 计算每个预测因子与目标负荷之间的 Pearson 相关系数。
varNames = string(featureData.Properties.VariableNames);
featureNames = setdiff(varNames, [cfg.timestampName, cfg.targetName], "stable");

target = featureData.(cfg.targetName);
feature = strings(numel(featureNames), 1);
pearsonR = zeros(numel(featureNames), 1);
absPearsonR = zeros(numel(featureNames), 1);

for i = 1:numel(featureNames)
    values = featureData.(featureNames(i));
    % Rows="complete" 会忽略特征或目标中存在 NaN 的样本。
    r = corr(values, target, "Rows", "complete", "Type", "Pearson");
    feature(i) = featureNames(i);
    pearsonR(i) = r;
    absPearsonR(i) = abs(r);
end

correlationTable = table(feature, pearsonR, absPearsonR);
correlationTable = sortrows(correlationTable, "absPearsonR", "descend");
end

function ratioTable = calculateLoadComponentRatio(cfg, dataClean)
%CALCULATELOADCOMPONENTRATIO 估计各配置分项的平均负荷占比。
componentNames = cfg.loadComponentNames(ismember(cfg.loadComponentNames, string(dataClean.Properties.VariableNames)));
componentMean = zeros(numel(componentNames), 1);
componentRatio = zeros(numel(componentNames), 1);
totalMean = mean(dataClean.(cfg.targetName), "omitnan");

for i = 1:numel(componentNames)
    componentMean(i) = mean(dataClean.(componentNames(i)), "omitnan");
    % 占比以平均总冷负荷为分母，而不是分项均值之和，以保持与目标列定义一致。
    componentRatio(i) = componentMean(i) / totalMean;
end

ratioTable = table(componentNames(:), componentMean, componentRatio, ...
    'VariableNames', {'component', 'meanLoadKw', 'ratio'});
end

function [dailyCurves, dailyDates] = buildDailyLoadCurves(cfg, dataClean)
%BUILDDAILYLOADCURVES 将连续时间负荷序列转换为逐日曲线矩阵。
dates = dateshift(dataClean.(cfg.timestampName), "start", "day");
dailyDates = unique(dates);
dailyCurves = nan(numel(dailyDates), cfg.dailyPointNum);

for i = 1:numel(dailyDates)
    idx = dates == dailyDates(i);
    dayLoad = dataClean.(cfg.targetName)(idx);
    n = min(numel(dayLoad), cfg.dailyPointNum);
    curve = nan(1, cfg.dailyPointNum);
    curve(1:n) = dayLoad(1:n);
    % 填补不完整日曲线缺口，使 K-Means 输入保持固定宽度。
    curve = fillmissing(curve, "linear", 2);
    curve = fillmissing(curve, "nearest", 2);
    if cfg.normalizeDailyClusterCurves
        % 可选 min-max 缩放：使聚类更关注曲线形态，而非绝对负荷水平。
        minValue = min(curve);
        maxValue = max(curve);
        if maxValue > minValue
            curve = (curve - minValue) ./ (maxValue - minValue);
        else
            curve = zeros(size(curve));
        end
    end
    dailyCurves(i, :) = curve;
end
end

function [bestK, bestLabel, silhouetteTable] = chooseBestClusterK(cfg, dailyCurves)
%CHOOSEBESTCLUSTERK 遍历候选 K，并选择平均轮廓系数最高的结果。
kValues = cfg.clusterKRange(:);
meanSilhouette = nan(numel(kValues), 1);
labels = cell(numel(kValues), 1);

for i = 1:numel(kValues)
    k = kValues(i);
    fprintf("    正在运行 K-Means，K = %d...\n", k);
    % 多次重复可降低随机初值陷入较差局部最优的概率。
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

function tableOut = localizeCorrelationTableForOutput(tableIn)
%LOCALIZECORRELATIONTABLEFOROUTPUT 生成相关性表的中文导出副本。
tableOut = tableIn;
tableOut.feature = localizeFeatureNames(tableOut.feature);
tableOut.Properties.VariableNames = {'特征', 'Pearson相关系数', '绝对Pearson相关系数'};
end

function tableOut = localizeRatioTableForOutput(tableIn)
%LOCALIZERATIOTABLEFOROUTPUT 生成分项负荷占比表的中文导出副本。
tableOut = tableIn;
tableOut.component = localizeFeatureNames(tableOut.component);
tableOut.Properties.VariableNames = {'分项负荷', '平均负荷_kW', '占比'};
end

function tableOut = localizeSilhouetteTableForOutput(tableIn)
%LOCALIZESILHOUETTETABLEFOROUTPUT 生成聚类轮廓系数表的中文导出副本。
tableOut = tableIn;
tableOut.Properties.VariableNames = {'K值', '平均轮廓系数'};
end

function namesOut = localizeFeatureNames(namesIn)
%LOCALIZEFEATURENAMES 将特征名转换为图表展示用中文名称。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    name = namesIn(i);
    if startsWith(name, "load_lag_")
        lagStep = extractAfter(name, "load_lag_");
        namesOut(i) = "冷负荷滞后" + lagStep + "步";
    else
        switch name
            case "entry_flow"
                namesOut(i) = "进站客流";
            case "exit_flow"
                namesOut(i) = "出站客流";
            case "platform_passengers"
                namesOut(i) = "站台人数";
            case "outdoor_temp"
                namesOut(i) = "室外温度";
            case "outdoor_rh"
                namesOut(i) = "室外相对湿度";
            case "solar_radiation"
                namesOut(i) = "太阳辐射";
            case "platform_temp"
                namesOut(i) = "站台温度";
            case "platform_rh"
                namesOut(i) = "站台相对湿度";
            case "co2"
                namesOut(i) = "二氧化碳浓度";
            case "people_load_kw"
                namesOut(i) = "人员负荷";
            case "fresh_air_load_kw"
                namesOut(i) = "新风负荷";
            case "envelope_load_kw"
                namesOut(i) = "围护结构负荷";
            case "equipment_load_kw"
                namesOut(i) = "设备负荷";
            case "hour_decimal"
                namesOut(i) = "小时_十进制";
            case "is_weekend_numeric"
                namesOut(i) = "是否周末";
            case "hour_sin"
                namesOut(i) = "小时正弦";
            case "hour_cos"
                namesOut(i) = "小时余弦";
            case "day_sin"
                namesOut(i) = "星期正弦";
            case "day_cos"
                namesOut(i) = "星期余弦";
            otherwise
                namesOut(i) = name;
        end
    end
end
end
