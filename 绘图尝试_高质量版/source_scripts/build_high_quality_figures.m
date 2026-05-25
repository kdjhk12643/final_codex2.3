function build_high_quality_figures()
%BUILD_HIGH_QUALITY_FIGURES Generate thesis-quality figures from project data.

rootDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
outDir = fullfile(rootDir, "绘图尝试_高质量版");
pngDir = fullfile(outDir, "figures_png");
pdfDir = fullfile(outDir, "figures_pdf");
if ~exist(pngDir, "dir"), mkdir(pngDir); end
if ~exist(pdfDir, "dir"), mkdir(pdfDir); end

set(groot, "defaultTextInterpreter", "none");
set(groot, "defaultLegendInterpreter", "none");
set(groot, "defaultAxesTickLabelInterpreter", "none");
set(groot, "defaultAxesFontName", "Microsoft YaHei");
set(groot, "defaultTextFontName", "Microsoft YaHei");

raw = readtable(fullfile(rootDir, "data", "fuzhou_metro_dongjiekou_2025.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
if ~isdatetime(raw.timestamp)
    raw.timestamp = datetime(raw.timestamp, "InputFormat", "yyyy-MM-dd HH:mm:ss");
end
if iscell(raw.is_weekend)
    raw.is_weekend = string(raw.is_weekend);
end
if isstring(raw.is_weekend) || ischar(raw.is_weekend)
    raw.is_weekend = lower(string(raw.is_weekend)) == "true" | string(raw.is_weekend) == "1";
end
if iscell(raw.day_type)
    raw.day_type = string(raw.day_type);
end
raw.date = dateshift(raw.timestamp, "start", "day");
raw.month = month(raw.timestamp);
raw.hourDecimal = hour(raw.timestamp) + minute(raw.timestamp) / 60;
raw.week = week(raw.timestamp);

tablesDir = fullfile(rootDir, "output", "tables");
T = struct();
T.pearson = readtable(fullfile(tablesDir, "step2_pearson_features.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.ratio = readtable(fullfile(tablesDir, "step2_load_component_ratio.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.silhouette = readtable(fullfile(tablesDir, "step2_cluster_silhouette.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.metrics = readtable(fullfile(tablesDir, "step3_prediction_metrics.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.ablation = readtable(fullfile(tablesDir, "step3_cluster_ablation_metrics.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.fair = readtable(fullfile(tablesDir, "step3_fair_model_comparison.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.quantiles = readtable(fullfile(tablesDir, "step3_subsystem_demand_quantiles.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.scenario = readtable(fullfile(tablesDir, "step3_scenario_demand.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.evaluation = readtable(fullfile(tablesDir, "step4_scheme_evaluation.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.redundancy = readtable(fullfile(tablesDir, "step4_subsystem_redundancy.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.constraints = readtable(fullfile(tablesDir, "step4_engineering_constraint_check.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.topsis = readtable(fullfile(tablesDir, "step4_topsis_ranking.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.sensitivity = readtable(fullfile(tablesDir, "step4_sensitivity_analysis.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.boundary = readtable(fullfile(tablesDir, "step4_engineering_boundary.csv"), "TextType", "string", "VariableNamingRule", "preserve");
T.linkage = readtable(fullfile(tablesDir, "step4_research_linkage.csv"), "TextType", "string", "VariableNamingRule", "preserve");

summaryPath = fullfile(rootDir, "output", "models", "bishe_result_summary.mat");
S = struct();
if isfile(summaryPath)
    S = load(summaryPath);
end

manifest = table('Size', [0 6], ...
    'VariableTypes', ["double", "string", "string", "string", "string", "string"], ...
    'VariableNames', ["序号", "章节", "图名", "说明", "PNG", "PDF"]);

    function addManifest(no, section, title, note, stem)
        manifest(end + 1, :) = {no, section, title, note, ...
            fullfile(pngDir, stem + ".png"), fullfile(pdfDir, stem + ".pdf")};
    end

    function saveFig(fig, no, section, title, note, stem)
        drawnow;
        pngPath = fullfile(pngDir, stem + ".png");
        pdfPath = fullfile(pdfDir, stem + ".pdf");
        exportgraphics(fig, pngPath, "Resolution", 600, "BackgroundColor", "white");
        exportgraphics(fig, pdfPath, "ContentType", "vector", "BackgroundColor", "white");
        addManifest(no, section, title, note, stem);
        close(fig);
    end

% 1. Research flow diagrams.
makeResearchRoute(1, "一、研究流程与方法框架", "图1-1 技术路线图", "展示从数据预处理、特征分析、负荷预测到容量优化和工程评价的完整研究链路。", "Fig_1_1_research_route");
makeDataMechanism(2, "一、研究流程与方法框架", "图1-2 数据生成与变量关系图", "说明客流、气象、站内环境和负荷分项之间的关系，用于支撑数据集构造逻辑。", "Fig_1_2_data_mechanism");

% 2. Data and load characteristics.
dailyLoad = groupsummary(raw, "date", "mean", "total_cooling_load_kw");
fig = thesisFigure(16, 9);
plot(dailyLoad.date, dailyLoad.mean_total_cooling_load_kw, "Color", cBlue(), "LineWidth", 1.45);
formatAxes("日期", "日均总冷负荷 / kW");
title("全年日均总冷负荷时序", "FontWeight", "bold");
saveFig(fig, 3, "二、数据质量与负荷特性", "图2-1 全年日均总冷负荷时序图", "按日平均展示全年冷负荷变化，夏季高负荷区间明显高于过渡季和冬季。", "Fig_2_1_annual_daily_load");

weekMask = raw.timestamp >= datetime(2025, 7, 7) & raw.timestamp < datetime(2025, 7, 14);
fig = thesisFigure(16, 9);
plot(raw.timestamp(weekMask), raw.total_cooling_load_kw(weekMask), "Color", cBlue(), "LineWidth", 1.25);
formatAxes("时间", "总冷负荷 / kW");
title("夏季典型周总冷负荷时序", "FontWeight", "bold");
saveFig(fig, 4, "二、数据质量与负荷特性", "图2-2 夏季典型周总冷负荷时序图", "选取 2025-07-07 至 2025-07-13，展示周内负荷峰谷与工作日/周末差异。", "Fig_2_2_summer_week_load");

monthlyLoad = groupsummary(raw, "month", "mean", "total_cooling_load_kw");
fig = thesisFigure(14, 9);
b = bar(monthlyLoad.month, monthlyLoad.mean_total_cooling_load_kw, 0.68);
b.FaceColor = cCyan();
formatAxes("月份", "月平均总冷负荷 / kW");
xticks(1:12); xticklabels(compose("%d月", 1:12));
title("月平均总冷负荷变化", "FontWeight", "bold");
saveFig(fig, 5, "二、数据质量与负荷特性", "图2-3 月平均总冷负荷变化图", "展示负荷季节性变化，可用于说明夏季容量配置需求更高。", "Fig_2_3_monthly_load");

fig = thesisFigure(16, 9);
weekdayProfile = groupsummary(raw(~raw.is_weekend, :), "hourDecimal", "mean", "total_cooling_load_kw");
weekendProfile = groupsummary(raw(raw.is_weekend, :), "hourDecimal", "mean", "total_cooling_load_kw");
plot(weekdayProfile.hourDecimal, weekdayProfile.mean_total_cooling_load_kw, "Color", cBlue(), "LineWidth", 1.8); hold on;
plot(weekendProfile.hourDecimal, weekendProfile.mean_total_cooling_load_kw, "Color", cOrange(), "LineWidth", 1.8);
formatAxes("时刻 / h", "平均总冷负荷 / kW");
legend(["工作日", "周末"], "Location", "northwest", "Box", "off");
title("工作日与周末日内平均负荷曲线", "FontWeight", "bold");
saveFig(fig, 6, "二、数据质量与负荷特性", "图2-4 工作日与周末日内平均负荷曲线图", "对比工作日与周末的日内负荷形态，为典型日模式分析提供依据。", "Fig_2_4_weekday_weekend_profile");

fig = thesisFigure(16, 9);
dayTypes = ["weekday_high", "weekday_medium", "weekend_single", "low_flow"];
dayTypeNames = ["工作日高峰", "工作日中等", "周末单峰", "低流量日"];
colors = [cBlue(); cOrange(); cGreen(); cRed()];
for i = 1:numel(dayTypes)
    profile = groupsummary(raw(raw.day_type == dayTypes(i), :), "hourDecimal", "mean", "total_cooling_load_kw");
    plot(profile.hourDecimal, profile.mean_total_cooling_load_kw, "LineWidth", 1.75, "Color", colors(i, :)); hold on;
end
formatAxes("时刻 / h", "平均总冷负荷 / kW");
legend(dayTypeNames, "Location", "northwest", "Box", "off");
title("不同日类型典型负荷曲线对比", "FontWeight", "bold");
saveFig(fig, 7, "二、数据质量与负荷特性", "图2-5 不同日类型典型负荷曲线对比图", "对比四类日负荷模式，说明客流峰型和运行日类型对负荷曲线形态的影响。", "Fig_2_5_day_type_profiles");

fig = thesisFigure(14, 9);
componentMeans = [mean(raw.people_load_kw, "omitnan"), mean(raw.fresh_air_load_kw, "omitnan"), ...
    mean(raw.envelope_load_kw, "omitnan"), mean(raw.equipment_load_kw, "omitnan")];
pie(componentMeans);
colormap([cBlue(); cCyan(); cGreen(); cOrange()]);
legend(["人员负荷", "新风负荷", "围护结构负荷", "设备负荷"], "Location", "eastoutside", "Box", "off");
title("负荷分项平均构成", "FontWeight", "bold");
saveFig(fig, 8, "二、数据质量与负荷特性", "图2-6 负荷分项平均构成图", "展示人员、新风、围护结构和设备散热负荷在总负荷中的相对贡献。", "Fig_2_6_component_ratio");

fig = thesisFigure(16, 9);
componentMonthly = groupsummary(raw, "month", "mean", ["people_load_kw", "fresh_air_load_kw", "envelope_load_kw", "equipment_load_kw"]);
Y = [componentMonthly.mean_people_load_kw, componentMonthly.mean_fresh_air_load_kw, componentMonthly.mean_envelope_load_kw, componentMonthly.mean_equipment_load_kw];
bar(componentMonthly.month, Y, "stacked");
colormap([cBlue(); cCyan(); cGreen(); cOrange()]);
formatAxes("月份", "月平均分项负荷 / kW");
legend(["人员负荷", "新风负荷", "围护结构负荷", "设备负荷"], "Location", "northoutside", "Orientation", "horizontal", "Box", "off");
xticks(1:12); xticklabels(compose("%d月", 1:12));
title("月平均分项负荷堆叠图", "FontWeight", "bold");
saveFig(fig, 9, "二、数据质量与负荷特性", "图2-7 月平均分项负荷堆叠图", "展示全年各月份分项负荷构成变化，说明季节项和围护结构负荷的影响。", "Fig_2_7_monthly_components");

fig = thesisFigure(15, 9);
missingVars = ["entry_flow", "outdoor_temp", "platform_temp", "co2", "total_cooling_load_kw"];
missingNames = ["进站客流", "室外温度", "站台温度", "CO2", "总冷负荷"];
missingCounts = zeros(size(missingVars));
for i = 1:numel(missingVars)
    missingCounts(i) = sum(ismissing(raw.(missingVars(i))));
end
bar(missingCounts, "FaceColor", cRed());
formatAxes("", "缺失值数量");
xticklabels(missingNames);
title("原始数据缺失值统计", "FontWeight", "bold");
saveFig(fig, 10, "二、数据质量与负荷特性", "图2-8 原始数据缺失值统计图", "展示关键变量中的缺失值数量，用于说明缺失值填补的必要性。", "Fig_2_8_missing_values");

fig = thesisFigure(14, 9);
loadSorted = sort(raw.total_cooling_load_kw(~isnan(raw.total_cooling_load_kw)), "descend");
p = (1:numel(loadSorted)) / numel(loadSorted) * 100;
plot(p, loadSorted, "Color", cGreen(), "LineWidth", 1.6);
formatAxes("超过该负荷的时间比例 / %", "总冷负荷 / kW");
title("负荷持续曲线", "FontWeight", "bold");
saveFig(fig, 11, "二、数据质量与负荷特性", "图2-9 负荷持续曲线图", "用于观察高负荷持续时间和长期部分负荷运行特征。", "Fig_2_9_load_duration");

% 3. Feature analysis and clustering.
fig = thesisFigure(16, 10);
topN = min(12, height(T.pearson));
names = T.pearson{1:topN, 1};
vals = T.pearson{1:topN, 3};
barh(vals, "FaceColor", cPurple());
set(gca, "YTick", 1:topN, "YTickLabel", names, "YDir", "reverse");
formatAxes("绝对 Pearson 相关系数", "");
title("Pearson 特征相关性排名", "FontWeight", "bold");
saveFig(fig, 12, "三、影响因素分析与典型日聚类", "图3-1 Pearson 特征相关性排名图", "展示与总冷负荷相关性最高的特征，滞后负荷和客流特征排序靠前。", "Fig_3_1_pearson_ranking");

fig = thesisFigure(14, 10);
corrVars = ["entry_flow", "exit_flow", "platform_passengers", "outdoor_temp", "solar_radiation", ...
    "platform_temp", "co2", "people_load_kw", "fresh_air_load_kw", "envelope_load_kw", "equipment_load_kw", "total_cooling_load_kw"];
corrNames = ["进站", "出站", "站台人数", "室外温度", "太阳辐射", "站台温度", "CO2", "人员", "新风", "围护", "设备", "总负荷"];
C = corr(raw{:, corrVars}, "Rows", "pairwise");
imagesc(C);
axis equal tight;
colormap(parula);
caxis([-1 1]);
cb = colorbar;
cb.Label.String = "相关系数";
set(gca, "XTick", 1:numel(corrNames), "XTickLabel", corrNames, ...
    "YTick", 1:numel(corrNames), "YTickLabel", corrNames, "XTickLabelRotation", 45);
title("关键变量相关性热力图", "FontWeight", "bold");
saveFig(fig, 13, "三、影响因素分析与典型日聚类", "图3-2 关键变量相关性热力图", "展示客流、环境、分项负荷与总冷负荷之间的相关结构。", "Fig_3_2_correlation_heatmap");

fig = thesisFigure(12, 8);
bar(T.silhouette{:, 1}, T.silhouette{:, 2}, 0.6, "FaceColor", cGreen());
formatAxes("聚类数 K", "平均轮廓系数");
xticks(T.silhouette{:, 1});
title("不同 K 值聚类轮廓系数对比", "FontWeight", "bold");
saveFig(fig, 14, "三、影响因素分析与典型日聚类", "图3-3 不同 K 值聚类轮廓系数对比图", "比较候选聚类数 K=2、3、4 的平均轮廓系数，当前 K=4 最高。", "Fig_3_3_silhouette");

[dailyCurves, ~] = buildDailyCurves(raw);
rng(202507);
labelsK = kmeans(dailyCurves, 4, "Replicates", 20, "MaxIter", 1000);
clusterMean = zeros(4, size(dailyCurves, 2));
for k = 1:4
    clusterMean(k, :) = mean(dailyCurves(labelsK == k, :), 1, "omitnan");
end
fig = thesisFigure(16, 9);
xh = linspace(0, 24, size(clusterMean, 2));
for k = 1:4
    plot(xh, clusterMean(k, :), "Color", colors(k, :), "LineWidth", 1.8); hold on;
end
formatAxes("时刻 / h", "平均总冷负荷 / kW");
legend(compose("第%d类", 1:4), "Location", "northwest", "Box", "off");
title("K-Means 典型日聚类中心曲线", "FontWeight", "bold");
saveFig(fig, 15, "三、影响因素分析与典型日聚类", "图3-4 K-Means 典型日聚类中心曲线图", "将每类日负荷曲线取均值，展示典型日模式的差异。", "Fig_3_4_cluster_centers");

% 4. Prediction model.
makeSequenceDiagram(16, "四、负荷预测模型与效果评价", "图4-1 LSTM 输入序列构造图", "展示 16 个 15 分钟历史步长构成 4 小时输入窗口，用于预测下一时刻总冷负荷。", "Fig_4_1_lstm_sequence");
makeLstmArchitecture(17, "四、负荷预测模型与效果评价", "图4-2 LSTM 网络结构图", "展示项目中的两层 LSTM 网络结构：Sequence Input -> LSTM(96) -> LSTM(48) -> Fully Connected -> Regression。", "Fig_4_2_lstm_architecture");
makeBpArchitecture(18, "四、负荷预测模型与效果评价", "图4-3 BP 神经网络结构图", "展示 BP 对比模型的前馈网络结构，用于与 LSTM 时序模型比较。", "Fig_4_3_bp_architecture");

if isfield(S, "predictionResult")
    fig = thesisFigure(16, 9);
    yTrue = S.predictionResult.yTestLSTM(:);
    yPred = S.predictionResult.yPredLSTM(:);
    n = min(numel(yTrue), 900);
    plot(1:n, yTrue(1:n), "Color", [0.15 0.15 0.15], "LineWidth", 1.15); hold on;
    plot(1:n, yPred(1:n), "Color", cBlue(), "LineWidth", 1.35);
    formatAxes("测试样本序号", "总冷负荷 / kW");
    legend(["真实值", "LSTM预测值"], "Location", "northwest", "Box", "off");
    title("LSTM 测试集预测效果", "FontWeight", "bold");
    saveFig(fig, 19, "四、负荷预测模型与效果评价", "图4-4 LSTM 测试集预测效果图", "比较测试集真实负荷与 LSTM 预测负荷，展示时序模型对峰谷变化的跟踪能力。", "Fig_4_4_lstm_prediction");

    fig = thesisFigure(16, 9);
    yTrue = S.predictionResult.yTest(:);
    yPred = S.predictionResult.yPredBP(:);
    n = min(numel(yTrue), 900);
    plot(1:n, yTrue(1:n), "Color", [0.15 0.15 0.15], "LineWidth", 1.15); hold on;
    plot(1:n, yPred(1:n), "Color", cOrange(), "LineWidth", 1.35);
    formatAxes("测试样本序号", "总冷负荷 / kW");
    legend(["真实值", "BP预测值"], "Location", "northwest", "Box", "off");
    title("BP 测试集预测效果", "FontWeight", "bold");
    saveFig(fig, 20, "四、负荷预测模型与效果评价", "图4-5 BP 测试集预测效果图", "比较测试集真实负荷与 BP 预测负荷，用于说明静态基准模型的预测偏差。", "Fig_4_5_bp_prediction");
end

fig = thesisFigure(14, 9);
metricNames = ["RMSE/kW", "MAE/kW", "MAPE/%"];
Y = [T.metrics{1, 2}, T.metrics{1, 3}, T.metrics{1, 4}; T.metrics{2, 2}, T.metrics{2, 3}, T.metrics{2, 4}]';
bar(Y);
colormap([cBlue(); cOrange()]);
formatAxes("", "误差值");
set(gca, "XTickLabel", metricNames);
legend(["LSTM", "BP"], "Location", "northoutside", "Orientation", "horizontal", "Box", "off");
title("LSTM 与 BP 预测误差指标对比", "FontWeight", "bold");
saveFig(fig, 21, "四、负荷预测模型与效果评价", "图4-6 LSTM 与 BP 预测误差指标对比图", "比较两类模型的 RMSE、MAE 和 MAPE，LSTM 在主预测结果中误差更低。", "Fig_4_6_model_metrics");

fig = thesisFigure(14, 9);
Y = [T.ablation{1, 4}, T.ablation{1, 5}, T.ablation{1, 6}; T.ablation{2, 4}, T.ablation{2, 5}, T.ablation{2, 6}]';
bar(Y);
colormap([0.45 0.50 0.58; cGreen()]);
formatAxes("", "误差值");
set(gca, "XTickLabel", ["RMSE", "MAE", "MAPE"]);
legend(["不含聚类标签", "含聚类标签"], "Location", "northoutside", "Orientation", "horizontal", "Box", "off");
title("聚类标签消融实验结果", "FontWeight", "bold");
saveFig(fig, 22, "四、负荷预测模型与效果评价", "图4-7 聚类标签消融实验结果图", "比较加入典型日聚类标签前后的 LSTM 预测误差，用于量化聚类特征贡献。", "Fig_4_7_cluster_ablation");

fig = thesisFigure(15, 10);
barh(T.fair{:, 5}, "FaceColor", cTeal());
set(gca, "YTick", 1:height(T.fair), "YTickLabel", T.fair{:, 1}, "YDir", "reverse");
formatAxes("RMSE / kW", "");
title("公平输入模型比较", "FontWeight", "bold");
saveFig(fig, 23, "四、负荷预测模型与效果评价", "图4-8 公平输入模型比较图", "在含滞后和不含滞后特征条件下比较 LSTM 与 BP，避免将输入信息量差异误读为模型结构差异。", "Fig_4_8_fair_comparison");

% 5. Capacity optimization.
makePredictionToCapacity(24, "五、容量优化与工程评价", "图5-1 预测结果到容量需求转换图", "说明 LSTM 完整预测曲线如何转换为 P50/P95/P99 情景需求，并进一步转为设备容量约束。", "Fig_5_1_prediction_to_capacity");

fig = thesisFigure(16, 9);
subNames = T.quantiles{1:4, 1};
Y = [T.quantiles{1:4, 3}, T.quantiles{1:4, 5}, T.quantiles{1:4, 6}];
bar(Y);
colormap([cCyan(); cOrange(); cRed()]);
formatAxes("", "需求值 / kW");
set(gca, "XTickLabel", subNames);
legend(["P50", "P95", "P99"], "Location", "northoutside", "Orientation", "horizontal", "Box", "off");
title("子系统容量需求分位数对比", "FontWeight", "bold");
saveFig(fig, 25, "五、容量优化与工程评价", "图5-2 子系统容量需求分位数对比图", "比较总冷负荷、冷机、风机和水泵在不同置信分位下的容量需求。", "Fig_5_2_subsystem_quantiles");

fig = thesisFigure(12, 8);
bar([T.quantiles{5, 3}, T.quantiles{5, 5}, T.quantiles{5, 6}, T.quantiles{5, 7}], 0.6, "FaceColor", cGreen());
formatAxes("", "AHU风量需求 / (m^3/h)");
set(gca, "XTickLabel", ["P50", "P95", "P99", "最大值"]);
title("AHU 风量需求分位数", "FontWeight", "bold");
saveFig(fig, 26, "五、容量优化与工程评价", "图5-3 AHU 风量需求分位数图", "单独展示 AHU 风量需求，避免与 kW 量纲混合。", "Fig_5_3_ahu_quantiles");

makeOptimizationFlow(27, "五、容量优化与工程评价", "图5-4 NSGA-II 与 TOPSIS 容量优化流程图", "展示容量优化从设备编码、工程约束、双目标评价、Pareto 解集到 TOPSIS 推荐方案的流程。", "Fig_5_4_optimization_flow");

fig = thesisFigure(14, 9);
scatter(T.topsis{:, 1} / 10000, T.topsis{:, 2} * 100, 55, cBlue(), "filled", "MarkerFaceAlpha", 0.75); hold on;
scatter(T.topsis{1, 1} / 10000, T.topsis{1, 2} * 100, 95, cRed(), "filled");
formatAxes("生命周期成本 / 万元", "综合冗余率 / %");
legend(["Pareto候选方案", "TOPSIS推荐方案"], "Location", "northeast", "Box", "off");
title("容量优化 Pareto 前沿", "FontWeight", "bold");
saveFig(fig, 28, "五、容量优化与工程评价", "图5-5 容量优化 Pareto 前沿图", "展示生命周期成本与综合冗余率之间的权衡关系，红点为 TOPSIS 推荐方案。", "Fig_5_5_pareto_front");

fig = thesisFigure(14, 8);
nTop = min(8, height(T.topsis));
bar(T.topsis{1:nTop, 3}, "FaceColor", cPurple());
formatAxes("候选方案排序", "TOPSIS贴近度");
xticks(1:nTop); xticklabels(compose("方案%d", 1:nTop));
title("TOPSIS 候选方案得分排序", "FontWeight", "bold");
saveFig(fig, 29, "五、容量优化与工程评价", "图5-6 TOPSIS 候选方案得分排序图", "展示 Pareto 候选方案的 TOPSIS 得分，得分越高表示越接近低成本、低冗余理想方案。", "Fig_5_6_topsis_ranking");

fig = thesisFigure(16, 9);
groups = ["总制冷容量/kW", "生命周期成本/万元", "综合冗余率/%", "年能耗/万kWh"];
base = [T.evaluation{1, 2}, T.evaluation{1, 3} / 10000, T.evaluation{1, 4} * 100, T.evaluation{1, 6} / 10000];
opt = [T.evaluation{2, 2}, T.evaluation{2, 3} / 10000, T.evaluation{2, 4} * 100, T.evaluation{2, 6} / 10000];
bar([base; opt]');
colormap([0.45 0.50 0.58; cBlue()]);
formatAxes("", "指标值");
set(gca, "XTickLabel", groups);
legend(["基准方案", "优化方案"], "Location", "northoutside", "Orientation", "horizontal", "Box", "off");
title("基准方案与优化方案综合对比", "FontWeight", "bold");
saveFig(fig, 30, "五、容量优化与工程评价", "图5-7 基准方案与优化方案综合对比图", "从装机容量、生命周期成本、冗余率和年能耗四方面比较优化效果。", "Fig_5_7_scheme_comparison");

fig = thesisFigure(15, 9);
Y = [T.redundancy{:, 5} * 100, T.redundancy{:, 6} * 100];
bar(Y);
colormap([cOrange(); cGreen()]);
formatAxes("", "冗余率 / %");
set(gca, "XTickLabel", T.redundancy{:, 1});
legend(["基准方案", "优化方案"], "Location", "northoutside", "Orientation", "horizontal", "Box", "off");
title("子系统容量冗余率对比", "FontWeight", "bold");
saveFig(fig, 31, "五、容量优化与工程评价", "图5-8 子系统容量冗余率对比图", "比较冷机、风机、水泵和 AHU 在优化前后的容量冗余率。", "Fig_5_8_subsystem_redundancy");

fig = thesisFigure(16, 10);
names = T.constraints{:, 1};
passValue = double(T.constraints{:, 5} == "通过" | lower(T.constraints{:, 5}) == "true");
barh(passValue, "FaceColor", cGreen());
set(gca, "YTick", 1:numel(names), "YTickLabel", names, "YDir", "reverse", "XLim", [0, 1.1]);
xticks([0, 1]); xticklabels(["未通过", "通过"]);
formatAxes("校核结果", "");
title("工程约束校核结果", "FontWeight", "bold");
saveFig(fig, 32, "五、容量优化与工程评价", "图5-9 工程约束校核结果图", "展示推荐方案在预测误差裕量、最小负荷率、极端容量裕量和子系统匹配约束下均通过校核。", "Fig_5_9_engineering_constraints");

fig = thesisFigure(14, 8);
riskText = T.sensitivity{:, 5};
riskScore = zeros(height(T.sensitivity), 1);
for i = 1:numel(riskScore)
    if contains(riskText(i), "高") || contains(lower(riskText(i)), "high")
        riskScore(i) = 3;
    elseif contains(riskText(i), "低") || contains(lower(riskText(i)), "low")
        riskScore(i) = 1;
    else
        riskScore(i) = 2;
    end
end
bar(riskScore, 0.62, "FaceColor", cRed());
formatAxes("", "风险等级");
ylim([0 3.4]); yticks(1:3); yticklabels(["低", "中", "高"]);
xticks(1:5);
xticklabels(["设计分位数", "安全系数", "TOPSIS权重", "电价", "预测误差"]);
xtickangle(20);
title("关键参数敏感性风险等级", "FontWeight", "bold");
saveFig(fig, 33, "五、容量优化与工程评价", "图5-10 关键参数敏感性风险等级图", "展示设计分位数、安全系数、TOPSIS 权重、电价和预测误差等因素的敏感性风险。", "Fig_5_10_sensitivity_risk");

boundaryCompact = table( ...
    ["数据来源"; "子系统需求换算"; "水力与风侧设计"; "设备性能"; "控制与舒适性"; "最终设计用途"], ...
    ["构造年度数据验证方法"; "回归 + 工程比例换算"; "仅校核容量与安全裕量"; "简化 COP/PLR 曲线"; "未模拟温湿度与 CO2 闭环"; "论文级初步方案比较"], ...
    ["需 BMS/AFC/气象实测校准"; "需热湿计算与新风校核"; "需阻力、扬程、管网平衡"; "需厂家曲线和维护约束"; "需动态控制和标准校核"; "需设计院复核与设备选型"], ...
    'VariableNames', ["工程边界", "当前处理", "详细设计补充"]);
linkageCompact = table( ...
    ["特征分析→预测"; "聚类分析→预测"; "负荷预测→容量需求"; "容量优化→方案评价"], ...
    ["Pearson 筛选关键特征"; "K=4 典型日模式"; "LSTM 曲线与 P99 情景"; "Pareto 候选 + TOPSIS"], ...
    ["LSTM/BP 输入"; "运行模式解释"; "设备容量约束"; "推荐方案对比"], ...
    ["LSTM RMSE 9.58, R² 0.9709"; "轮廓系数 0.680"; "P99 冷机需求 413.29 kW"; "成本、冗余、能耗均降低"], ...
    'VariableNames', ["研究链路", "上游输出", "下游用途", "证据指标"]);
makeTableFigure(34, "五、容量优化与工程评价", "图5-11 工程边界与详细设计补充图", "说明当前论文级方法验证与施工图级工程设计之间的边界。", "Fig_5_11_engineering_boundary", boundaryCompact, 1:3);
makeTableFigure(35, "五、容量优化与工程评价", "图5-12 研究链路证据矩阵图", "汇总特征分析、聚类分析、预测结果和容量优化之间的证据链路。", "Fig_5_12_research_linkage", linkageCompact, 1:4);

writetable(manifest, fullfile(outDir, "figure_manifest.csv"), "Encoding", "UTF-8");
fprintf("Generated %d high-quality figures.\n", height(manifest));

    function makeResearchRoute(no, section, titleText, note, stem)
        fig = diagramFigure(16, 8.5);
        axis off;
        addBox([0.05 0.58 0.16 0.18], "数据预处理", "缺失填补\newline 时间/滞后特征", cLightBlue());
        addBox([0.26 0.58 0.16 0.18], "负荷特性分析", "Pearson\newline 分项负荷", cLightGreen());
        addBox([0.47 0.58 0.16 0.18], "典型日聚类", "K-Means\newline 轮廓系数", cLightOrange());
        addBox([0.68 0.58 0.16 0.18], "负荷预测", "LSTM / BP\newline 消融对比", cLightPurple());
        addBox([0.47 0.24 0.16 0.18], "容量优化", "NSGA-II\newline TOPSIS", cLightRed());
        addBox([0.68 0.24 0.16 0.18], "工程评价", "成本/冗余\newline 能耗/约束", cLightGray());
        addArrow([0.21 0.67], [0.26 0.67]); addArrow([0.42 0.67], [0.47 0.67]);
        addArrow([0.63 0.67], [0.68 0.67]); addArrow([0.76 0.58], [0.58 0.42]);
        addArrow([0.63 0.33], [0.68 0.33]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makeDataMechanism(no, section, titleText, note, stem)
        fig = diagramFigure(16, 8.5);
        axis off;
        addBox([0.06 0.58 0.18 0.18], "客流模式", "进站/出站\newline 站台人数\newline 日类型", cLightBlue());
        addBox([0.06 0.28 0.18 0.18], "气象环境", "室外温湿度\newline 太阳辐射\newline 季节项", cLightGreen());
        addBox([0.36 0.58 0.18 0.18], "站内状态", "站台温湿度\newline CO2\newline 热惯性", cLightOrange());
        addBox([0.36 0.28 0.18 0.18], "负荷分项", "人员/新风\newline 围护/设备", cLightPurple());
        addBox([0.70 0.43 0.20 0.20], "总冷负荷", "total_cooling_load_kw\newline 容量优化目标输入", cLightRed());
        addArrow([0.24 0.67], [0.36 0.67]); addArrow([0.24 0.37], [0.36 0.37]);
        addArrow([0.54 0.67], [0.70 0.54]); addArrow([0.54 0.37], [0.70 0.48]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makeSequenceDiagram(no, section, titleText, note, stem)
        fig = diagramFigure(16, 7.8);
        axis off;
        addBox([0.06 0.50 0.13 0.18], "t-15", "多变量特征", cLightBlue());
        addBox([0.22 0.50 0.13 0.18], "...", "滑动窗口", cLightBlue());
        addBox([0.38 0.50 0.13 0.18], "t-1", "多变量特征", cLightBlue());
        addBox([0.57 0.50 0.16 0.18], "LSTM", "16步历史\newline 4小时窗口", cLightPurple());
        addBox([0.80 0.50 0.14 0.18], "t", "预测负荷/kW", cLightGreen());
        addArrow([0.19 0.59], [0.22 0.59]); addArrow([0.35 0.59], [0.38 0.59]);
        addArrow([0.51 0.59], [0.57 0.59]); addArrow([0.73 0.59], [0.80 0.59]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makeLstmArchitecture(no, section, titleText, note, stem)
        fig = diagramFigure(16, 7.8);
        axis off;
        addBox([0.04 0.48 0.16 0.20], "Sequence Input", "特征数 × 16步", cLightBlue());
        addBox([0.25 0.48 0.16 0.20], "LSTM Layer 1", "96 hidden units\newline OutputMode=sequence", cLightPurple());
        addBox([0.46 0.48 0.16 0.20], "LSTM Layer 2", "48 hidden units\newline OutputMode=last", cLightPurple());
        addBox([0.67 0.48 0.13 0.20], "FC", "1维输出", cLightGreen());
        addBox([0.84 0.48 0.12 0.20], "Regression", "kW", cLightOrange());
        addArrow([0.20 0.58], [0.25 0.58]); addArrow([0.41 0.58], [0.46 0.58]);
        addArrow([0.62 0.58], [0.67 0.58]); addArrow([0.80 0.58], [0.84 0.58]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makeBpArchitecture(no, section, titleText, note, stem)
        fig = diagramFigure(16, 7.8);
        axis off;
        addBox([0.06 0.48 0.18 0.20], "静态特征输入", "客流/气象\newline 环境/时间", cLightBlue());
        addBox([0.32 0.48 0.16 0.20], "隐藏层1", "20个神经元", cLightPurple());
        addBox([0.56 0.48 0.16 0.20], "隐藏层2", "10个神经元", cLightPurple());
        addBox([0.80 0.48 0.14 0.20], "输出层", "总冷负荷/kW", cLightGreen());
        addArrow([0.24 0.58], [0.32 0.58]); addArrow([0.48 0.58], [0.56 0.58]);
        addArrow([0.72 0.58], [0.80 0.58]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makePredictionToCapacity(no, section, titleText, note, stem)
        fig = diagramFigure(16, 8.5);
        axis off;
        addBox([0.05 0.56 0.18 0.18], "LSTM完整预测曲线", "全年/测试序列\newline 负荷预测值", cLightBlue());
        addBox([0.30 0.56 0.18 0.18], "分位数情景", "P50典型\newline P95峰值\newline P99极端", cLightGreen());
        addBox([0.55 0.56 0.18 0.18], "子系统换算", "冷机/风机\newline 水泵/AHU", cLightOrange());
        addBox([0.78 0.56 0.16 0.18], "误差裕量", "叠加LSTM RMSE", cLightRed());
        addBox([0.30 0.25 0.18 0.18], "容量约束", "安全系数\newline 最小裕量", cLightPurple());
        addBox([0.55 0.25 0.18 0.18], "设备组合优化", "规格索引 + 台数", cLightGray());
        addArrow([0.23 0.65], [0.30 0.65]); addArrow([0.48 0.65], [0.55 0.65]);
        addArrow([0.73 0.65], [0.78 0.65]); addArrow([0.86 0.56], [0.64 0.43]);
        addArrow([0.48 0.34], [0.55 0.34]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makeOptimizationFlow(no, section, titleText, note, stem)
        fig = diagramFigure(16, 8.5);
        axis off;
        addBox([0.04 0.56 0.16 0.18], "设备候选库", "容量规格\newline 台数范围", cLightBlue());
        addBox([0.25 0.56 0.16 0.18], "整数编码", "8维决策向量", cLightGreen());
        addBox([0.46 0.56 0.16 0.18], "工程约束", "容量/PLR\newline 匹配比例", cLightOrange());
        addBox([0.67 0.56 0.16 0.18], "双目标评价", "生命周期成本\newline 综合冗余率", cLightPurple());
        addBox([0.46 0.25 0.16 0.18], "Pareto解集", "非劣候选方案", cLightGray());
        addBox([0.67 0.25 0.16 0.18], "TOPSIS排序", "成本0.55\newline 冗余0.45", cLightRed());
        addBox([0.86 0.25 0.10 0.18], "推荐方案", "输出", cLightGreen());
        addArrow([0.20 0.65], [0.25 0.65]); addArrow([0.41 0.65], [0.46 0.65]);
        addArrow([0.62 0.65], [0.67 0.65]); addArrow([0.75 0.56], [0.54 0.43]);
        addArrow([0.62 0.34], [0.67 0.34]); addArrow([0.83 0.34], [0.86 0.34]);
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function makeTableFigure(no, section, titleText, note, stem, sourceTable, colIdx)
        fig = thesisFigure(17, 10);
        axis off;
        rows = min(height(sourceTable), 6);
        vals = sourceTable{1:rows, colIdx};
        colNames = sourceTable.Properties.VariableNames(colIdx);
        x0 = 0.04; y0 = 0.12; w = 0.92; h = 0.72;
        nCols = numel(colIdx);
        nRows = rows + 1;
        colW = w / nCols;
        rowH = h / nRows;
        rectangle("Position", [x0 y0 w h], "FaceColor", "white", "EdgeColor", [0.75 0.80 0.88], "LineWidth", 1.0);
        rectangle("Position", [x0 y0 + h - rowH w rowH], "FaceColor", [0.90 0.94 1.00], "EdgeColor", [0.75 0.80 0.88], "LineWidth", 0.8);
        for cc = 1:nCols
            tx = x0 + (cc - 1) * colW + 0.01;
            text(tx, y0 + h - rowH / 2, string(colNames(cc)), "FontName", "Microsoft YaHei", ...
                "FontSize", 8.5, "FontWeight", "bold", "VerticalAlignment", "middle", "Interpreter", "none");
            if cc > 1
                line([x0 + (cc - 1) * colW, x0 + (cc - 1) * colW], [y0, y0 + h], "Color", [0.82 0.86 0.92], "LineWidth", 0.6);
            end
        end
        for rr = 1:rows
            y = y0 + h - (rr + 1) * rowH;
            if mod(rr, 2) == 0
                rectangle("Position", [x0 y w rowH], "FaceColor", [0.98 0.99 1.00], "EdgeColor", "none");
            end
            line([x0, x0 + w], [y, y], "Color", [0.82 0.86 0.92], "LineWidth", 0.6);
            for cc = 1:nCols
                tx = x0 + (cc - 1) * colW + 0.01;
                text(tx, y + rowH / 2, wrapForTable(string(vals(rr, cc)), 22), ...
                    "FontName", "Microsoft YaHei", "FontSize", 7.2, ...
                    "VerticalAlignment", "middle", "Interpreter", "none");
            end
        end
        title(titleText, "FontWeight", "bold");
        saveFig(fig, no, section, titleText, note, stem);
    end

    function out = wrapForTable(txt, maxChars)
        chars = char(txt);
        if strlength(txt) <= maxChars
            out = txt;
            return;
        end
        parts = strings(0);
        startIdx = 1;
        while startIdx <= numel(chars)
            endIdx = min(numel(chars), startIdx + maxChars - 1);
            parts(end + 1) = string(chars(startIdx:endIdx)); %#ok<AGROW>
            startIdx = endIdx + 1;
        end
        out = strjoin(parts, newline);
    end

    function fig = thesisFigure(w, h)
        fig = figure("Visible", "off", "Color", "white", "Units", "centimeters", "Position", [2 2 w h]);
        ax = axes(fig);
        ax.FontName = "Microsoft YaHei";
        ax.FontSize = 9.5;
        ax.LineWidth = 0.8;
        ax.Box = "off";
        ax.Color = "white";
        grid(ax, "on");
        ax.GridAlpha = 0.16;
        hold(ax, "on");
    end

    function fig = diagramFigure(w, h)
        fig = figure("Visible", "off", "Color", "white", "Units", "centimeters", "Position", [2 2 w h]);
        axes(fig, "Position", [0 0 1 1]);
        xlim([0 1]); ylim([0 1]);
    end

    function formatAxes(xlab, ylab)
        ax = gca;
        ax.FontName = "Microsoft YaHei";
        ax.FontSize = 9.5;
        ax.LineWidth = 0.9;
        ax.Box = "off";
        ax.GridAlpha = 0.16;
        grid(ax, "on");
        xlabel(xlab, "FontName", "Microsoft YaHei", "FontSize", 10);
        ylabel(ylab, "FontName", "Microsoft YaHei", "FontSize", 10);
    end

    function addBox(pos, head, body, fillColor)
        annotation("textbox", pos, "String", sprintf("%s\n%s", head, body), ...
            "FitBoxToText", "off", "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
            "FontName", "Microsoft YaHei", "FontSize", 10, "FontWeight", "bold", ...
            "BackgroundColor", fillColor, "EdgeColor", [0.25 0.42 0.75], "LineWidth", 1.1);
    end

    function addArrow(p1, p2)
        annotation("arrow", [p1(1) p2(1)], [p1(2) p2(2)], "LineWidth", 1.2, "Color", [0.28 0.34 0.42]);
    end
end

function [dailyCurves, dailyDates] = buildDailyCurves(raw)
dailyDates = unique(raw.date);
dailyCurves = nan(numel(dailyDates), 96);
for i = 1:numel(dailyDates)
    idx = raw.date == dailyDates(i);
    values = raw.total_cooling_load_kw(idx);
    n = min(numel(values), 96);
    curve = nan(1, 96);
    curve(1:n) = values(1:n);
    curve = fillmissing(curve, "linear", 2);
    curve = fillmissing(curve, "nearest", 2);
    dailyCurves(i, :) = curve;
end
end

function c = cBlue(), c = [0.16 0.38 0.72]; end
function c = cCyan(), c = [0.08 0.57 0.70]; end
function c = cGreen(), c = [0.10 0.55 0.34]; end
function c = cOrange(), c = [0.82 0.42 0.08]; end
function c = cRed(), c = [0.78 0.16 0.16]; end
function c = cPurple(), c = [0.44 0.28 0.75]; end
function c = cTeal(), c = [0.09 0.47 0.43]; end
function c = cLightBlue(), c = [0.91 0.95 1.00]; end
function c = cLightGreen(), c = [0.91 0.98 0.94]; end
function c = cLightOrange(), c = [1.00 0.96 0.89]; end
function c = cLightPurple(), c = [0.95 0.93 1.00]; end
function c = cLightRed(), c = [1.00 0.93 0.93]; end
function c = cLightGray(), c = [0.96 0.97 0.98]; end
