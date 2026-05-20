function optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult)
%STEP4_CAPACITY_OPTIMIZATION 使用 NSGA-II 和 TOPSIS 进行容量优化。
% 本步骤将预测需求转换为离散设备选型，两个主要目标为全生命周期成本和综合容量冗余率。

stepTimer = tic;
fprintf("  步骤 4.1 从 LSTM 完整预测曲线读取设计负荷...\n");
optimizationScenarioName = cfg.optimizationScenarioName;
% 需求来自步骤3的情景需求表，通常采用 extreme/P99 情景。
demand = predictionResult.scenarioDemand.(optimizationScenarioName);
rawDemand = demand;
% 叠加预测误差裕量，避免容量配置只依赖点预测；裕量由 LSTM 测试集 RMSE 折算。
predictionErrorMarginKw = predictionResult.metricsLSTM.RMSE * cfg.predictionErrorRmseFactor;
demand = applyPredictionErrorMargin(cfg, demand, predictionErrorMarginKw);
designLoad = demand.totalCoolingLoadKw;
representativeLoad = predictionResult.representativeLoadKw;
if isfield(predictionResult, "predictedProfile") && isfield(predictionResult.predictedProfile, "totalCoolingLoadKw")
    loadProfileKw = predictionResult.predictedProfile.totalCoolingLoadKw;
else
    loadProfileKw = representativeLoad;
end
fprintf("  设计负荷 = %.2f kW（%s，LSTM 完整预测曲线 P%.0f 总负荷）。\n", ...
    designLoad, localizeScenarioNames(optimizationScenarioName), demand.quantile * 100);
fprintf("  预测误差裕量 = %.2f kW（%.1f × LSTM RMSE）；原始设计负荷 = %.2f kW。\n", ...
    predictionErrorMarginKw, cfg.predictionErrorRmseFactor, rawDemand.totalCoolingLoadKw);
fprintf("  代表负荷 = %.2f kW（预测曲线均值）。\n", representativeLoad);
fprintf("  子系统设计需求：冷机=%.2f kW，风机=%.2f kW，水泵=%.2f kW，AHU=%.0f m3/h。\n", ...
    demand.chillerDemandKw, demand.fanDemandKw, demand.pumpDemandKw, demand.ahuDemand);

optimizationResult = struct();
optimizationResult.designLoadKw = designLoad;
optimizationResult.representativeLoadKw = representativeLoad;
optimizationResult.designDemand = demand;
optimizationResult.rawDesignDemand = rawDemand;
optimizationResult.predictionErrorMarginKw = predictionErrorMarginKw;
fprintf("  步骤 4.2 构建基准方案...\n");
% 基准方案代表常规偏冗余配置，用作优化方案的比较对象。
optimizationResult.baselineScheme = buildBaselineScheme(cfg, demand);
fprintf("  基准制冷容量 = %.2f kW，综合冗余率 = %.2f%%。\n", ...
    optimizationResult.baselineScheme.totalCoolingCapacityKw, ...
    optimizationResult.baselineScheme.redundancyRate * 100);

fprintf("  步骤 4.3 运行容量优化，种群规模=%d，迭代代数=%d...\n", ...
    cfg.populationSize, cfg.maxGenerations);
% 候选解编码冷机、风机、水泵和 AHU 的单机容量及台数，并逐一检查工程约束。
[paretoSet, paretoObjective] = solveCapacityOptimization(cfg, demand, representativeLoad, loadProfileKw);
[paretoObjective, uniqueIdx] = unique(paretoObjective, "rows", "stable");
paretoSet = paretoSet(uniqueIdx, :);
[paretoSet, paretoObjective] = limitParetoSetToTargetBand(paretoSet, paretoObjective);
fprintf("  生成 Pareto 候选方案数量：%d。\n", size(paretoSet, 1));

fprintf("  步骤 4.4 使用 TOPSIS 对 Pareto 解排序...\n");
% Pareto 优化保留权衡方案，TOPSIS 根据 cfg.topsisWeights 选择最终推荐方案。
[bestScheme, topsisTable] = chooseByTopsis(cfg, paretoSet, paretoObjective);

optimizationResult.paretoSet = paretoSet;
optimizationResult.paretoObjective = paretoObjective;
optimizationResult.bestScheme = decodeScheme(cfg, bestScheme);
optimizationResult.topsisTable = topsisTable;
% 构建论文结果与讨论部分可直接引用的结果表。
optimizationResult.evaluationTable = compareSchemes(cfg, optimizationResult.baselineScheme, optimizationResult.bestScheme, demand, representativeLoad, loadProfileKw);
optimizationResult.subsystemRedundancyTable = compareSubsystemRedundancy(cfg, optimizationResult.baselineScheme, optimizationResult.bestScheme, demand);
optimizationResult.scenarioCapacityCheck = buildScenarioCapacityCheck(cfg, optimizationResult.bestScheme, predictionResult.scenarioDemand);
optimizationResult.engineeringConstraintCheck = buildEngineeringConstraintCheck(cfg, optimizationResult.bestScheme, demand, representativeLoad);
optimizationResult.analysisSummary = struct( ...
    "bestK", analysisResult.bestK, ...
    "selectedFeatureCount", numel(analysisResult.selectedFeatures), ...
    "clusterSilhouette", analysisResult.silhouetteTable.meanSilhouette);
optimizationResult.researchLinkageTable = build_research_linkage_table(cfg, predictionResult, optimizationResult);
[optimizationResult.sensitivityTable, optimizationResult.engineeringBoundaryTable] = ...
    analyze_capacity_sensitivity(cfg, optimizationResult);

% 分别保存步骤4证据表，便于不打开 MAT 汇总文件时审查优化决策。
topsisFile = fullfile(cfg.tableDir, "step4_topsis_ranking.csv");
evaluationFile = fullfile(cfg.tableDir, "step4_scheme_evaluation.csv");
subsystemFile = fullfile(cfg.tableDir, "step4_subsystem_redundancy.csv");
scenarioCheckFile = fullfile(cfg.tableDir, "step4_scenario_capacity_check.csv");
engineeringConstraintFile = fullfile(cfg.tableDir, "step4_engineering_constraint_check.csv");
linkageFile = fullfile(cfg.tableDir, "step4_research_linkage.csv");
sensitivityFile = fullfile(cfg.tableDir, "step4_sensitivity_analysis.csv");
boundaryFile = fullfile(cfg.tableDir, "step4_engineering_boundary.csv");
writetable(localizeTopsisTableForOutput(optimizationResult.topsisTable), topsisFile);
writetable(localizeEvaluationTableForOutput(optimizationResult.evaluationTable), evaluationFile);
writetable(localizeSubsystemRedundancyTableForOutput(optimizationResult.subsystemRedundancyTable), subsystemFile);
writetable(localizeScenarioCapacityTableForOutput(optimizationResult.scenarioCapacityCheck), scenarioCheckFile);
writetable(localizeEngineeringConstraintTableForOutput(optimizationResult.engineeringConstraintCheck), engineeringConstraintFile);
writetable(localizeResearchLinkageTableForOutput(optimizationResult.researchLinkageTable), linkageFile);
writetable(localizeSensitivityTableForOutput(optimizationResult.sensitivityTable), sensitivityFile);
writetable(localizeEngineeringBoundaryTableForOutput(optimizationResult.engineeringBoundaryTable), boundaryFile);

plotStep4Figures(cfg, optimizationResult);

fprintf("  推荐制冷容量 = %.2f kW，综合冗余率 = %.2f%%。\n", ...
    optimizationResult.bestScheme.totalCoolingCapacityKw, ...
    optimizationResult.evaluationTable.redundancyRate(2) * 100);
fprintf("  已保存：%s\n", topsisFile);
fprintf("  已保存：%s\n", evaluationFile);
fprintf("  已保存：%s\n", subsystemFile);
fprintf("  已保存：%s\n", scenarioCheckFile);
fprintf("  已保存：%s\n", engineeringConstraintFile);
fprintf("  已保存：%s\n", linkageFile);
fprintf("  已保存：%s\n", sensitivityFile);
fprintf("  已保存：%s\n", boundaryFile);
fprintf("  步骤 4 完成，用时 %.1f 秒。\n", toc(stepTimer));
end

function demandOut = applyPredictionErrorMargin(cfg, demandIn, predictionErrorMarginKw)
%APPLYPREDICTIONERRORMARGIN 按 LSTM 误差裕量抬高设计需求。
demandOut = demandIn;
if predictionErrorMarginKw <= 0
    return;
end

totalBase = max(demandIn.totalCoolingLoadKw, eps);
fanPerCoolingKw = demandIn.fanDemandKw / totalBase;
pumpPerCoolingKw = demandIn.pumpDemandKw / totalBase;

demandOut.predictionErrorMarginKw = predictionErrorMarginKw;
% 冷机需求直接叠加总冷负荷裕量；风机、水泵和 AHU 按当前需求与总冷负荷的比例折算。
demandOut.totalCoolingLoadKw = demandIn.totalCoolingLoadKw + predictionErrorMarginKw;
demandOut.chillerDemandKw = demandIn.chillerDemandKw + predictionErrorMarginKw;
demandOut.fanDemandKw = demandIn.fanDemandKw + predictionErrorMarginKw * fanPerCoolingKw;
demandOut.pumpDemandKw = demandIn.pumpDemandKw + predictionErrorMarginKw * pumpPerCoolingKw;
demandOut.ahuDemand = demandIn.ahuDemand + predictionErrorMarginKw * cfg.ahuAirflowPerKw;
end

function [paretoSet, paretoObjective] = limitParetoSetToTargetBand(paretoSet, paretoObjective)
%LIMITPARETOSETTOTARGETBAND 控制导出的 Pareto 表规模，使结果更紧凑可读。
targetCount = 32;
if size(paretoSet, 1) <= targetCount
    return;
end

[~, order] = sort(paretoObjective(:, 1), "ascend");
sampleIdx = unique(round(linspace(1, numel(order), targetCount)));
selected = order(sampleIdx);
paretoSet = paretoSet(selected, :);
paretoObjective = paretoObjective(selected, :);
end

function baseline = buildBaselineScheme(cfg, demand)
%BUILDBASELINESCHEME 按固定冗余率构建规则型参考方案。
targetCapacity = demand.chillerDemandKw * (1 + cfg.baselineRedundancyRate);
chillerCapacity = max(cfg.chillerCapacityList);
chillerCount = max(cfg.chillerCountRange);

for count = cfg.chillerCountRange
    % 对当前台数，选择第一个能达到目标容量的单机容量。
    capacity = cfg.chillerCapacityList(find(cfg.chillerCapacityList * count >= targetCapacity, 1, "first"));
    if ~isempty(capacity)
        chillerCapacity = capacity;
        chillerCount = count;
        break;
    end
end

baseline = struct();
baseline.chillerCapacityKw = chillerCapacity;
baseline.chillerCount = chillerCount;
[baseline.fanCapacityKw, baseline.fanCount] = chooseBaselinePair( ...
    cfg.fanCapacityList, cfg.fanCountRange, demand.fanDemandKw * (1 + cfg.baselineRedundancyRate));
[baseline.pumpCapacityKw, baseline.pumpCount] = chooseBaselinePair( ...
    cfg.pumpCapacityList, cfg.pumpCountRange, demand.pumpDemandKw * (1 + cfg.baselineRedundancyRate));
[baseline.ahuAirflow, baseline.ahuCount] = chooseBaselinePair( ...
    cfg.ahuAirflowList, cfg.ahuCountRange, demand.ahuDemand * (1 + cfg.baselineRedundancyRate));
baseline.totalCoolingCapacityKw = baseline.chillerCapacityKw * baseline.chillerCount;
baseline.totalFanCapacityKw = baseline.fanCapacityKw * baseline.fanCount;
baseline.totalPumpCapacityKw = baseline.pumpCapacityKw * baseline.pumpCount;
baseline.totalAhuAirflow = baseline.ahuAirflow * baseline.ahuCount;
baseline.redundancyRate = calculateCompositeRedundancy(cfg, baseline, demand);
% 基准方案与优化方案使用同一能耗模型计算生命周期成本，以保证比较公平。
baseline.lifecycleCost = estimateLifecycleCost(cfg, baseline, demand.totalCoolingLoadKw, demand, demand.totalCoolingLoadKw);
end

function [unitCapacity, count] = chooseBaselinePair(capacityList, countRange, targetCapacity)
%CHOOSEBASELINEPAIR 选择满足目标容量的最小总装机容量组合。
unitCapacity = max(capacityList);
count = max(countRange);
bestTotal = inf;

for candidateCount = countRange
    for candidateCapacity = capacityList
        totalCapacity = candidateCapacity * candidateCount;
        if totalCapacity >= targetCapacity && totalCapacity < bestTotal
            bestTotal = totalCapacity;
            unitCapacity = candidateCapacity;
            count = candidateCount;
        end
    end
end
end

function [paretoSet, paretoObjective] = solveCapacityOptimization(cfg, demand, representativeLoad, loadProfileKw)
%SOLVECAPACITYOPTIMIZATION 优先使用 NSGA-II；不可用时枚举离散候选方案。
hasGamultiobj = exist("gamultiobj", "file") == 2;

if hasGamultiobj
    fprintf("    检测到 Global Optimization Toolbox，使用 gamultiobj（NSGA-II）。\n");
    nvars = 8;
    lb = ones(1, nvars);
    ub = [ ...
        numel(cfg.chillerCapacityList), numel(cfg.chillerCountRange), ...
        numel(cfg.fanCapacityList), numel(cfg.fanCountRange), ...
        numel(cfg.pumpCapacityList), numel(cfg.pumpCountRange), ...
        numel(cfg.ahuAirflowList), numel(cfg.ahuCountRange) ...
    ];

    options = optimoptions("gamultiobj", ...
        "PopulationSize", cfg.populationSize, ...
        "MaxGenerations", cfg.maxGenerations, ...
        "Display", "iter");

    % 决策向量 x 包含 8 个整数索引：
    % [冷机容量索引, 冷机台数索引, 风机容量索引, 风机台数索引,
    %  水泵容量索引, 水泵台数索引, AHU风量索引, AHU台数索引]。
    objective = @(x) capacityObjectives(cfg, round(x), demand, representativeLoad, loadProfileKw);
    constraint = @(x) capacityConstraints(cfg, round(x), demand, representativeLoad);
    [paretoSet, paretoObjective] = gamultiobj(objective, nvars, [], [], [], [], lb, ub, constraint, options);
    paretoSet = round(paretoSet);
    % 合并 NSGA-II 结果与确定性枚举结果，避免连续优化接口遗漏离散可行候选。
    [discreteSet, discreteObjective] = enumerateDiscretePareto(cfg, demand, representativeLoad, loadProfileKw);
    paretoSet = [paretoSet; discreteSet];
    paretoObjective = [paretoObjective; discreteObjective];
else
    fprintf("    未检测到 gamultiobj，使用网格搜索回退方案。\n");
    [paretoSet, paretoObjective] = enumerateDiscretePareto(cfg, demand, representativeLoad, loadProfileKw);
end
end

function f = capacityObjectives(cfg, x, demand, representativeLoad, loadProfileKw)
%CAPACITYOBJECTIVES 返回单个方案的 [生命周期成本, 综合冗余率]。
scheme = decodeScheme(cfg, x);
scheme.totalCoolingCapacityKw = scheme.chillerCapacityKw * scheme.chillerCount;
scheme.totalFanCapacityKw = scheme.fanCapacityKw * scheme.fanCount;
scheme.totalPumpCapacityKw = scheme.pumpCapacityKw * scheme.pumpCount;
scheme.totalAhuAirflow = scheme.ahuAirflow * scheme.ahuCount;
scheme.redundancyRate = calculateCompositeRedundancy(cfg, scheme, demand);
scheme.lifecycleCost = estimateLifecycleCost(cfg, scheme, representativeLoad, demand, loadProfileKw);
f = [scheme.lifecycleCost, scheme.redundancyRate];
end

function [c, ceq] = capacityConstraints(cfg, x, demand, representativeLoad)
%CAPACITYCONSTRAINTS 约束需求覆盖、部分负荷率和子系统匹配关系。
scheme = decodeScheme(cfg, x);
totalCoolingCapacity = scheme.chillerCapacityKw * scheme.chillerCount;
totalFanCapacity = scheme.fanCapacityKw * scheme.fanCount;
totalPumpCapacity = scheme.pumpCapacityKw * scheme.pumpCount;
totalAhuAirflow = scheme.ahuAirflow * scheme.ahuCount;

extremeMarginFactor = 1 + cfg.minExtremeCapacityMargin;
typicalChillerPLR = representativeLoad / max(totalCoolingCapacity, eps);
minimumPLRConstraint = cfg.minTypicalChillerPLR - typicalChillerPLR;
matchingConstraints = buildMatchingConstraints(cfg, totalCoolingCapacity, totalFanCapacity, totalPumpCapacity, totalAhuAirflow);

% MATLAB 非线性不等式约束要求 c <= 0；若某项为正，表示候选方案违反最小容量或匹配比例约束。
c = [
    cfg.chillerSafetyFactor * demand.chillerDemandKw * extremeMarginFactor - totalCoolingCapacity
    cfg.fanSafetyFactor * demand.fanDemandKw * extremeMarginFactor - totalFanCapacity
    cfg.pumpSafetyFactor * demand.pumpDemandKw * extremeMarginFactor - totalPumpCapacity
    cfg.ahuSafetyFactor * demand.ahuDemand * extremeMarginFactor - totalAhuAirflow
    minimumPLRConstraint
    matchingConstraints
];
ceq = [];
end

function c = buildMatchingConstraints(cfg, totalCoolingCapacity, totalFanCapacity, totalPumpCapacity, totalAhuAirflow)
%BUILDMATCHINGCONSTRAINTS 保持风侧、水侧和 AHU 规模与制冷容量相匹配。
fanRatio = totalFanCapacity / max(totalCoolingCapacity, eps);
pumpRatio = totalPumpCapacity / max(totalCoolingCapacity, eps);
ahuRatio = totalAhuAirflow / max(totalCoolingCapacity, eps);

c = [
    cfg.fanCoolingCapacityRatioRange(1) - fanRatio
    fanRatio - cfg.fanCoolingCapacityRatioRange(2)
    cfg.pumpCoolingCapacityRatioRange(1) - pumpRatio
    pumpRatio - cfg.pumpCoolingCapacityRatioRange(2)
    cfg.ahuAirflowPerCoolingKwRange(1) - ahuRatio
    ahuRatio - cfg.ahuAirflowPerCoolingKwRange(2)
];
end

function [paretoSet, paretoObjective] = enumerateDiscretePareto(cfg, demand, representativeLoad, loadProfileKw)
%ENUMERATEDISCRETEPARETO 在收窄后的可行网格中进行确定性枚举。
candidateSet = [];
candidateObj = [];

% 围绕需求阈值构建较短候选列表，避免对所有设备组合做完整笛卡尔穷举。
coolingOptions = buildPairOptions(cfg.chillerCapacityList, cfg.chillerCountRange, demand.chillerDemandKw, cfg.chillerSafetyFactor, 22);
fanOptions = buildPairOptions(cfg.fanCapacityList, cfg.fanCountRange, demand.fanDemandKw, cfg.fanSafetyFactor, 10);
pumpOptions = buildPairOptions(cfg.pumpCapacityList, cfg.pumpCountRange, demand.pumpDemandKw, cfg.pumpSafetyFactor, 10);
ahuOptions = buildPairOptions(cfg.ahuAirflowList, cfg.ahuCountRange, demand.ahuDemand, cfg.ahuSafetyFactor, 10);

for i = 1:size(coolingOptions, 1)
    for j = 1:size(fanOptions, 1)
        for k = 1:size(pumpOptions, 1)
            for m = 1:size(ahuOptions, 1)
                x = [coolingOptions(i, :), fanOptions(j, :), pumpOptions(k, :), ahuOptions(m, :)];
                [c, ~] = capacityConstraints(cfg, x, demand, representativeLoad);
                if all(c <= 0)
                    % 只有满足约束的组合才进入 Pareto 筛选。
                    f = capacityObjectives(cfg, x, demand, representativeLoad, loadProfileKw);
                    candidateSet = [candidateSet; x]; %#ok<AGROW>
                    candidateObj = [candidateObj; f]; %#ok<AGROW>
                end
            end
        end
    end
end

costTolerance = 0.08;
redundancyTolerance = 0.025;
isPareto = true(size(candidateObj, 1), 1);
% 宽松支配规则剔除两个目标都明显更差的方案，同时保留可读的权衡候选范围。
for i = 1:size(candidateObj, 1)
    for j = 1:size(candidateObj, 1)
        costDominates = candidateObj(j, 1) <= candidateObj(i, 1) * (1 - costTolerance);
        redundancyDominates = candidateObj(j, 2) <= candidateObj(i, 2) - redundancyTolerance;
        dominates = costDominates && redundancyDominates;
        if dominates
            isPareto(i) = false;
            break;
        end
    end
end

paretoSet = candidateSet(isPareto, :);
paretoObjective = candidateObj(isPareto, :);
end

function options = buildPairOptions(capacityList, countRange, demand, safetyFactor, maxOptions)
%BUILDPAIROPTIONS 生成接近目标需求的紧凑“单机容量-台数”候选。
rows = [];
scores = [];
target = demand * safetyFactor;

for i = 1:numel(capacityList)
    for j = 1:numel(countRange)
        totalCapacity = capacityList(i) * countRange(j);
        if totalCapacity >= target
            redundancy = (totalCapacity - demand) / demand;
            if redundancy <= 0.85
                % 评分倾向于较低冗余，并轻微偏好较少并联设备台数。
                rows = [rows; i, j]; %#ok<AGROW>
                scores = [scores; redundancy + 0.015 * countRange(j)]; %#ok<AGROW>
            end
        end
    end
end

[~, order] = sort(scores, "ascend");
order = order(1:min(maxOptions, numel(order)));
options = rows(order, :);
end

function [bestX, topsisTable] = chooseByTopsis(cfg, paretoSet, paretoObjective)
%CHOOSEBYTOPSIS 按候选方案到理想成本/冗余点的距离进行排序。
normalized = paretoObjective ./ sqrt(sum(paretoObjective .^ 2, 1));
weighted = normalized .* cfg.topsisWeights;
idealBest = min(weighted, [], 1);
idealWorst = max(weighted, [], 1);

dBest = sqrt(sum((weighted - idealBest) .^ 2, 2));
dWorst = sqrt(sum((weighted - idealWorst) .^ 2, 2));
denominator = dBest + dWorst;
if all(denominator == 0)
    score = ones(size(dBest));
else
    score = dWorst ./ max(denominator, eps);
end
[~, bestIdx] = max(score);
bestX = paretoSet(bestIdx, :);

topsisTable = array2table([paretoObjective, score], ...
    'VariableNames', {'lifecycleCost', 'redundancyRate', 'topsisScore'});
end

function scheme = decodeScheme(cfg, x)
%DECODESCHEME 将整数决策索引转换为实际设备容量和台数。
scheme = struct();
scheme.chillerCapacityKw = cfg.chillerCapacityList(x(1));
scheme.chillerCount = cfg.chillerCountRange(x(2));
scheme.fanCapacityKw = cfg.fanCapacityList(x(3));
scheme.fanCount = cfg.fanCountRange(x(4));
scheme.pumpCapacityKw = cfg.pumpCapacityList(x(5));
scheme.pumpCount = cfg.pumpCountRange(x(6));
scheme.ahuAirflow = cfg.ahuAirflowList(x(7));
scheme.ahuCount = cfg.ahuCountRange(x(8));
scheme.totalCoolingCapacityKw = scheme.chillerCapacityKw * scheme.chillerCount;
scheme.totalFanCapacityKw = scheme.fanCapacityKw * scheme.fanCount;
scheme.totalPumpCapacityKw = scheme.pumpCapacityKw * scheme.pumpCount;
scheme.totalAhuAirflow = scheme.ahuAirflow * scheme.ahuCount;
end

function initialCost = estimateInitialCost(cfg, scheme)
%ESTIMATEINITIALCOST 计算所选设备容量和台数对应的初投资。
initialCost = ...
    scheme.chillerCapacityKw * scheme.chillerCount * cfg.chillerUnitCostPerKw + ...
    scheme.fanCapacityKw * scheme.fanCount * cfg.fanUnitCostPerKw + ...
    scheme.pumpCapacityKw * scheme.pumpCount * cfg.pumpUnitCostPerKw + ...
    scheme.ahuAirflow * scheme.ahuCount * cfg.ahuUnitCostPerAirflow;
end

function annualEnergy = estimateAnnualEnergy(cfg, scheme, representativeLoad, demand, loadProfileKw)
%ESTIMATEANNUALENERGY 调用详细能耗模型计算部分负荷年能耗。
if nargin < 5 || isempty(loadProfileKw)
    loadProfileKw = representativeLoad;
end
annualEnergy = hvac_estimate_annual_energy_detailed(cfg, scheme, loadProfileKw, demand);
end

function lifecycleCost = estimateLifecycleCost(cfg, scheme, representativeLoad, demand, loadProfileKw)
%ESTIMATELIFECYCLECOST 将投资、能耗和维护费用折算为现值成本。
initialCost = estimateInitialCost(cfg, scheme);
annualEnergy = estimateAnnualEnergy(cfg, scheme, representativeLoad, demand, loadProfileKw);
annualOperatingCost = annualEnergy * cfg.electricityPrice;
presentWorthFactor = (1 - (1 + cfg.discountRate) ^ (-cfg.lifeYears)) / cfg.discountRate;
maintenanceCost = initialCost * cfg.maintenanceRate * presentWorthFactor;
lifecycleCost = initialCost + annualOperatingCost * presentWorthFactor + maintenanceCost;
end

function evaluationTable = compareSchemes(cfg, baseline, bestScheme, demand, representativeLoad, loadProfileKw)
%COMPARESCHEMES 构建基准方案与优化方案对比表。
baseline.lifecycleCost = estimateLifecycleCost(cfg, baseline, representativeLoad, demand, loadProfileKw);
baseline.redundancyRate = calculateCompositeRedundancy(cfg, baseline, demand);
bestScheme.redundancyRate = calculateCompositeRedundancy(cfg, bestScheme, demand);
bestScheme.lifecycleCost = estimateLifecycleCost(cfg, bestScheme, representativeLoad, demand, loadProfileKw);

scheme = ["baseline"; "optimized"];
totalCoolingCapacityKw = [baseline.totalCoolingCapacityKw; bestScheme.totalCoolingCapacityKw];
lifecycleCost = [baseline.lifecycleCost; bestScheme.lifecycleCost];
redundancyRate = [baseline.redundancyRate; bestScheme.redundancyRate];
initialCost = [
    estimateInitialCost(cfg, baseline)
    estimateInitialCost(cfg, bestScheme)
];
annualEnergyKwh = [
    estimateAnnualEnergy(cfg, baseline, representativeLoad, demand, loadProfileKw)
    estimateAnnualEnergy(cfg, bestScheme, representativeLoad, demand, loadProfileKw)
];
% 分解年能耗，用于解释生命周期成本变化来源。
[~, baselineEnergyBreakdown] = hvac_estimate_annual_energy_detailed(cfg, baseline, loadProfileKw, demand);
[~, optimizedEnergyBreakdown] = hvac_estimate_annual_energy_detailed(cfg, bestScheme, loadProfileKw, demand);
annualChillerEnergyKwh = [
    baselineEnergyBreakdown.chillerKwh
    optimizedEnergyBreakdown.chillerKwh
];
annualFanEnergyKwh = [
    baselineEnergyBreakdown.fanKwh
    optimizedEnergyBreakdown.fanKwh
];
annualPumpEnergyKwh = [
    baselineEnergyBreakdown.pumpKwh
    optimizedEnergyBreakdown.pumpKwh
];
meanChillerPLR = [
    baselineEnergyBreakdown.meanChillerPLR
    optimizedEnergyBreakdown.meanChillerPLR
];
meanCOP = [
    baselineEnergyBreakdown.meanCOP
    optimizedEnergyBreakdown.meanCOP
];

costReductionRate = [0; (baseline.lifecycleCost - bestScheme.lifecycleCost) / baseline.lifecycleCost];
redundancyReductionRate = [0; (baseline.redundancyRate - bestScheme.redundancyRate) / baseline.redundancyRate];
energySavingRate = [0; (annualEnergyKwh(1) - annualEnergyKwh(2)) / annualEnergyKwh(1)];

evaluationTable = table(scheme, totalCoolingCapacityKw, lifecycleCost, redundancyRate, ...
    initialCost, annualEnergyKwh, annualChillerEnergyKwh, annualFanEnergyKwh, ...
    annualPumpEnergyKwh, meanChillerPLR, meanCOP, costReductionRate, ...
    redundancyReductionRate, energySavingRate);
end

function redundancy = calculateCompositeRedundancy(~, scheme, demand)
%CALCULATECOMPOSITEREDUNDANCY 将各子系统冗余率平均为一个综合目标。
coolingRedundancy = (scheme.totalCoolingCapacityKw - demand.chillerDemandKw) / demand.chillerDemandKw;
fanRedundancy = (scheme.totalFanCapacityKw - demand.fanDemandKw) / demand.fanDemandKw;
pumpRedundancy = (scheme.totalPumpCapacityKw - demand.pumpDemandKw) / demand.pumpDemandKw;
ahuRedundancy = (scheme.totalAhuAirflow - demand.ahuDemand) / demand.ahuDemand;

redundancy = mean([coolingRedundancy, fanRedundancy, pumpRedundancy, ahuRedundancy]);
end

function redundancyTable = compareSubsystemRedundancy(~, baseline, bestScheme, demand)
%COMPARESUBSYSTEMREDUNDANCY 按设备子系统展示容量裕量。
subsystem = ["chiller"; "fan"; "pump"; "ahu"];
demandValue = [
    demand.chillerDemandKw
    demand.fanDemandKw
    demand.pumpDemandKw
    demand.ahuDemand
];
baselineCapacity = [
    baseline.totalCoolingCapacityKw
    baseline.totalFanCapacityKw
    baseline.totalPumpCapacityKw
    baseline.totalAhuAirflow
];
optimizedCapacity = [
    bestScheme.totalCoolingCapacityKw
    bestScheme.totalFanCapacityKw
    bestScheme.totalPumpCapacityKw
    bestScheme.totalAhuAirflow
];
baselineRedundancy = (baselineCapacity - demandValue) ./ demandValue;
optimizedRedundancy = (optimizedCapacity - demandValue) ./ demandValue;
reductionRate = (baselineRedundancy - optimizedRedundancy) ./ max(baselineRedundancy, eps);
redundancyTable = table(subsystem, demandValue, baselineCapacity, optimizedCapacity, ...
    baselineRedundancy, optimizedRedundancy, reductionRate);
end

function scenarioTable = buildScenarioCapacityCheck(cfg, scheme, scenarioDemand)
%BUILDSCENARIOCAPACITYCHECK 校核推荐方案在所有需求情景下的容量满足情况。
scenarioNames = cfg.scenarioNames(:);
scenario = strings(numel(scenarioNames) * 4, 1);
subsystem = strings(numel(scenarioNames) * 4, 1);
demandValue = zeros(numel(scenarioNames) * 4, 1);
capacity = zeros(numel(scenarioNames) * 4, 1);
safetyFactor = zeros(numel(scenarioNames) * 4, 1);
requiredCapacity = zeros(numel(scenarioNames) * 4, 1);
marginRate = zeros(numel(scenarioNames) * 4, 1);
pass = false(numel(scenarioNames) * 4, 1);

row = 0;
for i = 1:numel(scenarioNames)
    current = scenarioDemand.(scenarioNames(i));
    names = ["chiller"; "fan"; "pump"; "ahu"];
    demands = [current.chillerDemandKw; current.fanDemandKw; current.pumpDemandKw; current.ahuDemand];
    capacities = [scheme.totalCoolingCapacityKw; scheme.totalFanCapacityKw; scheme.totalPumpCapacityKw; scheme.totalAhuAirflow];
    factors = [cfg.chillerSafetyFactor; cfg.fanSafetyFactor; cfg.pumpSafetyFactor; cfg.ahuSafetyFactor];

    for j = 1:numel(names)
        % 需求容量包含各子系统对应的安全系数。
        row = row + 1;
        scenario(row) = scenarioNames(i);
        subsystem(row) = names(j);
        demandValue(row) = demands(j);
        capacity(row) = capacities(j);
        safetyFactor(row) = factors(j);
        requiredCapacity(row) = demands(j) * factors(j);
        marginRate(row) = (capacities(j) - requiredCapacity(row)) / requiredCapacity(row);
        pass(row) = capacities(j) >= requiredCapacity(row);
    end
end

scenarioTable = table(scenario, subsystem, demandValue, safetyFactor, ...
    requiredCapacity, capacity, marginRate, pass);
end

function checkTable = buildEngineeringConstraintCheck(cfg, scheme, demand, representativeLoad)
%BUILDENGINEERINGCONSTRAINTCHECK 将优化约束转换为可读的工程校核表。
constraintName = [
    "prediction_error_margin"
    "minimum_typical_chiller_plr"
    "minimum_extreme_capacity_margin_chiller"
    "minimum_extreme_capacity_margin_fan"
    "minimum_extreme_capacity_margin_pump"
    "minimum_extreme_capacity_margin_ahu"
    "fan_cooling_capacity_ratio"
    "pump_cooling_capacity_ratio"
    "ahu_airflow_per_cooling_kw"
];

actualValue = zeros(numel(constraintName), 1);
requiredMin = nan(numel(constraintName), 1);
requiredMax = nan(numel(constraintName), 1);
pass = false(numel(constraintName), 1);
note = strings(numel(constraintName), 1);

extremeMarginFactor = 1 + cfg.minExtremeCapacityMargin;
requiredCooling = demand.chillerDemandKw * cfg.chillerSafetyFactor * extremeMarginFactor;
requiredFan = demand.fanDemandKw * cfg.fanSafetyFactor * extremeMarginFactor;
requiredPump = demand.pumpDemandKw * cfg.pumpSafetyFactor * extremeMarginFactor;
requiredAhu = demand.ahuDemand * cfg.ahuSafetyFactor * extremeMarginFactor;

fanRatio = scheme.totalFanCapacityKw / max(scheme.totalCoolingCapacityKw, eps);
pumpRatio = scheme.totalPumpCapacityKw / max(scheme.totalCoolingCapacityKw, eps);
ahuRatio = scheme.totalAhuAirflow / max(scheme.totalCoolingCapacityKw, eps);
typicalPLR = representativeLoad / max(scheme.totalCoolingCapacityKw, eps);

actualValue(1) = demand.predictionErrorMarginKw;
requiredMin(1) = 0;
pass(1) = actualValue(1) >= requiredMin(1);
note(1) = "容量优化前已按 LSTM RMSE 对 P99 需求增加预测误差裕量";

actualValue(2) = typicalPLR;
requiredMin(2) = cfg.minTypicalChillerPLR;
pass(2) = actualValue(2) >= requiredMin(2);
note(2) = "避免在代表负荷下选择过度偏大的制冷容量";

actualValue(3:6) = [
    (scheme.totalCoolingCapacityKw - requiredCooling) / requiredCooling
    (scheme.totalFanCapacityKw - requiredFan) / requiredFan
    (scheme.totalPumpCapacityKw - requiredPump) / requiredPump
    (scheme.totalAhuAirflow - requiredAhu) / requiredAhu
];
requiredMin(3:6) = cfg.minExtremeCapacityMargin;
pass(3:6) = actualValue(3:6) >= requiredMin(3:6);
note(3:6) = "容量在安全系数和预测误差修正后仍需保留显式裕量";

actualValue(7:9) = [fanRatio; pumpRatio; ahuRatio];
requiredMin(7:9) = [
    cfg.fanCoolingCapacityRatioRange(1)
    cfg.pumpCoolingCapacityRatioRange(1)
    cfg.ahuAirflowPerCoolingKwRange(1)
];
requiredMax(7:9) = [
    cfg.fanCoolingCapacityRatioRange(2)
    cfg.pumpCoolingCapacityRatioRange(2)
    cfg.ahuAirflowPerCoolingKwRange(2)
];
pass(7:9) = actualValue(7:9) >= requiredMin(7:9) & actualValue(7:9) <= requiredMax(7:9);
note(7:9) = "保持风侧、水侧和 AHU 容量与制冷容量匹配";

checkTable = table(constraintName, actualValue, requiredMin, requiredMax, pass, note);
end

function plotStep4Figures(cfg, optimizationResult)
%PLOTSTEP4FIGURES 导出 Pareto 前沿图和基准/优化方案对比图。
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

% Pareto 前沿图：生命周期成本和冗余率均越低越优。
fig1 = figure("Name", "步骤4 - Pareto 前沿", "Visible", figureVisibility(cfg));
scatter(optimizationResult.paretoObjective(:, 1) / 10000, ...
    optimizationResult.paretoObjective(:, 2) * 100, 45, "filled");
xlabel("生命周期成本 / 万元");
ylabel("容量冗余率 / %");
title("容量优化 Pareto 前沿");
grid on;
saveFigureIfNeeded(cfg, fig1, "step4_pareto_front.png");

% 并列展示两个核心优化指标。
fig2 = figure("Name", "步骤4 - 方案对比", "Visible", figureVisibility(cfg));
tiledlayout(1, 2);
nexttile;
bar(categorical(localizeSchemeNames(optimizationResult.evaluationTable.scheme)), ...
    optimizationResult.evaluationTable.lifecycleCost / 10000);
ylabel("生命周期成本 / 万元");
title("生命周期成本");
grid on;
nexttile;
bar(categorical(localizeSchemeNames(optimizationResult.evaluationTable.scheme)), ...
    optimizationResult.evaluationTable.redundancyRate * 100);
ylabel("冗余率 / %");
title("容量冗余率");
grid on;
saveFigureIfNeeded(cfg, fig2, "step4_scheme_comparison.png");
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

function tableOut = localizeTopsisTableForOutput(tableIn)
%LOCALIZETOPSISTABLEFOROUTPUT 生成 TOPSIS 排序表的中文导出副本。
tableOut = tableIn;
tableOut.Properties.VariableNames = {'生命周期成本', '综合冗余率', 'TOPSIS得分'};
end

function tableOut = localizeEvaluationTableForOutput(tableIn)
%LOCALIZEEVALUATIONTABLEFOROUTPUT 生成方案评价表的中文导出副本。
tableOut = tableIn;
tableOut.scheme = localizeSchemeNames(tableOut.scheme);
tableOut.Properties.VariableNames = {'方案', '总制冷容量_kW', '生命周期成本', ...
    '综合冗余率', '初投资', '年能耗_kWh', '年冷机能耗_kWh', ...
    '年风机能耗_kWh', '年水泵能耗_kWh', '平均冷机负荷率', ...
    '平均COP', '成本降低率', '冗余降低率', '节能率'};
end

function tableOut = localizeSubsystemRedundancyTableForOutput(tableIn)
%LOCALIZESUBSYSTEMREDUNDANCYTABLEFOROUTPUT 生成子系统冗余表的中文导出副本。
tableOut = tableIn;
tableOut.subsystem = localizeSubsystemNames(tableOut.subsystem);
tableOut.Properties.VariableNames = {'子系统', '需求值', '基准容量', '优化容量', ...
    '基准冗余率', '优化冗余率', '冗余降低率'};
end

function tableOut = localizeScenarioCapacityTableForOutput(tableIn)
%LOCALIZESCENARIOCAPACITYTABLEFOROUTPUT 生成情景容量校核表的中文导出副本。
tableOut = tableIn;
tableOut.scenario = localizeScenarioNames(tableOut.scenario);
tableOut.subsystem = localizeSubsystemNames(tableOut.subsystem);
tableOut.pass = localizePassValues(tableOut.pass);
tableOut.Properties.VariableNames = {'情景', '子系统', '需求值', '安全系数', ...
    '所需容量', '实际容量', '裕量率', '是否通过'};
end

function tableOut = localizeEngineeringConstraintTableForOutput(tableIn)
%LOCALIZEENGINEERINGCONSTRAINTTABLEFOROUTPUT 生成工程约束校核表的中文导出副本。
tableOut = tableIn;
tableOut.constraintName = localizeConstraintNames(tableOut.constraintName);
tableOut.pass = localizePassValues(tableOut.pass);
tableOut.Properties.VariableNames = {'约束项', '实际值', '下限要求', '上限要求', ...
    '是否通过', '说明'};
end

function tableOut = localizeResearchLinkageTableForOutput(tableIn)
%LOCALIZERESEARCHLINKAGETABLEFOROUTPUT 生成研究链路表的中文导出副本。
tableOut = tableIn;
tableOut.linkageStage = localizeLinkageStageNames(tableOut.linkageStage);
tableOut.upstreamOutput = localizeLinkageUpstream(tableOut.upstreamOutput);
tableOut.downstreamUse = localizeLinkageDownstream(tableOut.downstreamUse);
tableOut.evidenceMetric = localizeLinkageEvidence(tableOut.evidenceMetric);
tableOut.simplificationRisk = localizeLinkageRisk(tableOut.simplificationRisk);
tableOut.Properties.VariableNames = {'研究链路', '上游输出', '下游用途', '证据指标', '简化风险'};
end

function tableOut = localizeSensitivityTableForOutput(tableIn)
%LOCALIZESENSITIVITYTABLEFOROUTPUT 生成敏感性分析表的中文导出副本。
tableOut = tableIn;
originalType = tableOut.sensitivityType;
tableOut.sensitivityType = localizeSensitivityTypeNames(originalType);
tableOut.currentSetting = localizeSensitivityCurrent(originalType, tableOut.currentSetting);
tableOut.expectedInfluence = localizeSensitivityInfluence(originalType);
tableOut.recommendedCheck = localizeSensitivityCheck(originalType);
tableOut.riskLevel = localizeRiskLevel(tableOut.riskLevel);
tableOut.Properties.VariableNames = {'敏感性类型', '当前设置', '预期影响', '建议校核', '风险等级'};
end

function tableOut = localizeEngineeringBoundaryTableForOutput(tableIn)
%LOCALIZEENGINEERINGBOUNDARYTABLEFOROUTPUT 生成工程边界表的中文导出副本。
tableOut = tableIn;
originalBoundary = tableOut.engineeringBoundary;
tableOut.engineeringBoundary = localizeEngineeringBoundaryNames(originalBoundary);
tableOut.currentTreatment = localizeEngineeringBoundaryTreatment(originalBoundary);
tableOut.neededForDetailedDesign = localizeEngineeringBoundaryNeeds(originalBoundary);
tableOut.Properties.VariableNames = {'工程边界', '当前处理方式', '详细设计所需补充'};
end

function namesOut = localizeSchemeNames(namesIn)
%LOCALIZESCHEMENAMES 将方案名转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "baseline"
            namesOut(i) = "基准方案";
        case "optimized"
            namesOut(i) = "优化方案";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function namesOut = localizeSubsystemNames(namesIn)
%LOCALIZESUBSYSTEMNAMES 将子系统名转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
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
%LOCALIZESCENARIONAMES 将情景名转换为中文。
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

function valuesOut = localizePassValues(valuesIn)
%LOCALIZEPASSVALUES 将逻辑校核结果转换为中文。
valuesOut = strings(size(valuesIn));
for i = 1:numel(valuesIn)
    if valuesIn(i)
        valuesOut(i) = "通过";
    else
        valuesOut(i) = "不通过";
    end
end
end

function namesOut = localizeConstraintNames(namesIn)
%LOCALIZECONSTRAINTNAMES 将工程约束名转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "prediction_error_margin"
            namesOut(i) = "预测误差裕量";
        case "minimum_typical_chiller_plr"
            namesOut(i) = "典型工况冷机最小负荷率";
        case "minimum_extreme_capacity_margin_chiller"
            namesOut(i) = "极端工况冷机最小容量裕量";
        case "minimum_extreme_capacity_margin_fan"
            namesOut(i) = "极端工况风机最小容量裕量";
        case "minimum_extreme_capacity_margin_pump"
            namesOut(i) = "极端工况水泵最小容量裕量";
        case "minimum_extreme_capacity_margin_ahu"
            namesOut(i) = "极端工况AHU最小容量裕量";
        case "fan_cooling_capacity_ratio"
            namesOut(i) = "风机容量与制冷容量比";
        case "pump_cooling_capacity_ratio"
            namesOut(i) = "水泵容量与制冷容量比";
        case "ahu_airflow_per_cooling_kw"
            namesOut(i) = "单位制冷容量AHU风量";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function namesOut = localizeLinkageStageNames(namesIn)
%LOCALIZELINKAGESTAGENAMES 将研究链路阶段名转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "feature_analysis_to_prediction"
            namesOut(i) = "特征分析到负荷预测";
        case "cluster_analysis_to_prediction"
            namesOut(i) = "聚类分析到负荷预测";
        case "prediction_to_capacity_demand"
            namesOut(i) = "负荷预测到容量需求";
        case "capacity_optimization_to_scheme_evaluation"
            namesOut(i) = "容量优化到方案评价";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function textOut = localizeLinkageUpstream(textIn)
%LOCALIZELINKAGEUPSTREAM 将研究链路上游输出描述转换为中文。
textOut = replaceKnownText(textIn, [
    "Pearson-selected passenger, environment, time, and lagged-load features"
    "Typical daily load modes and the selected K-Means label structure"
    "LSTM full predicted load profile and P50/P95/P99 demand scenarios"
    "Pareto candidate schemes and TOPSIS ranking"
], [
    "Pearson 筛选出的客流、环境、时间和滞后负荷特征"
    "典型日负荷模式及选定的 K-Means 标签结构"
    "LSTM 完整预测负荷曲线及 P50/P95/P99 需求情景"
    "Pareto 候选方案和 TOPSIS 排序"
]);
end

function textOut = localizeLinkageDownstream(textIn)
%LOCALIZELINKAGEDOWNSTREAM 将研究链路下游用途描述转换为中文。
textOut = replaceKnownText(textIn, [
    "Used as the LSTM input matrix and BP comparison input"
    "Used to explain operating modes and support scenario interpretation"
    "Converted into chiller, fan, pump, and AHU capacity constraints"
    "Compared against the baseline scheme for cost, redundancy, and energy"
], [
    "作为 LSTM 输入矩阵和 BP 对比模型输入"
    "用于解释运行模式并支撑情景解读"
    "转换为冷机、风机、水泵和 AHU 容量约束"
    "与基准方案进行成本、冗余和能耗对比"
]);
end

function textOut = localizeLinkageEvidence(textIn)
%LOCALIZELINKAGEEVIDENCE 将研究链路证据指标中的英文提示转换为中文。
textOut = string(textIn);
textOut = replace(textOut, ", best silhouette", "，最佳轮廓系数");
textOut = replace(textOut, "design load", "设计负荷");
textOut = replace(textOut, ", optimized cooling capacity", "，优化制冷容量");
textOut = replace(textOut, "redundancy", "冗余率");
textOut = replace(textOut, "cost down", "成本降低");
textOut = replace(textOut, "energy down", "能耗降低");
textOut = replace(textOut, ";", "；");
end

function textOut = localizeLinkageRisk(textIn)
%LOCALIZELINKAGERISK 将研究链路简化风险描述转换为中文。
textOut = replaceKnownText(textIn, [
    "Pearson captures linear relation only; nonlinear interactions need further validation"
    "Cluster label contribution should be verified by an ablation experiment when time permits"
    "Subsystem demand conversion uses regression/engineering ratios, not full hydraulic or psychrometric design"
    "TOPSIS ranking depends on weights and should be read together with sensitivity analysis"
], [
    "Pearson 仅刻画线性关系，非线性相互作用仍需进一步验证"
    "聚类标签贡献应在时间允许时通过消融实验验证"
    "子系统需求转换采用回归和工程比例，未展开完整水力或空气热湿设计"
    "TOPSIS 排序受权重影响，应结合敏感性分析解读"
]);
end

function namesOut = localizeSensitivityTypeNames(namesIn)
%LOCALIZESENSITIVITYTYPENAMES 将敏感性类型转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "design_quantile"
            namesOut(i) = "设计分位数";
        case "safety_factor"
            namesOut(i) = "安全系数";
        case "topsis_weight"
            namesOut(i) = "TOPSIS权重";
        case "electricity_price"
            namesOut(i) = "电价";
        case "prediction_error"
            namesOut(i) = "预测误差";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function textOut = localizeSensitivityCurrent(typeIn, textIn)
%LOCALIZESENSITIVITYCURRENT 将敏感性分析当前设置转换为中文。
typeIn = string(typeIn);
textIn = string(textIn);
textOut = strings(size(textIn));
for i = 1:numel(textIn)
    switch typeIn(i)
        case "design_quantile"
            textOut(i) = replace(replace(textIn(i), "capacity scenario=", "容量情景="), ", quantile=", "，分位数=");
        case "safety_factor"
            textOut(i) = replace(replace(replace(replace(textIn(i), "chiller", "冷机"), "fan", "风机"), "pump", "水泵"), "AHU", "AHU");
        case "topsis_weight"
            textOut(i) = replace(replace(textIn(i), "cost", "成本"), "redundancy", "冗余");
        case "electricity_price"
            textOut(i) = replace(textIn(i), "yuan/kWh", "元/kWh");
        case "prediction_error"
            textOut(i) = replace(textIn(i), "LSTM RMSE should be compared with", "LSTM RMSE 应与");
            textOut(i) = replace(textOut(i), "minimum extreme margin", "最小极端裕量比较");
        otherwise
            textOut(i) = textIn(i);
    end
end
end

function textOut = localizeSensitivityInfluence(typeIn)
%LOCALIZESENSITIVITYINFLUENCE 按敏感性类型给出中文预期影响。
typeIn = string(typeIn);
textOut = strings(size(typeIn));
for i = 1:numel(typeIn)
    switch typeIn(i)
        case "design_quantile"
            textOut(i) = "由 P95 提高到 P99 会增加所需装机容量并降低欠配风险";
        case "safety_factor"
            textOut(i) = "安全系数越高，可靠性越强，但冗余率和成本降低幅度会减弱";
        case "topsis_weight"
            textOut(i) = "成本权重越高越偏向低成本方案，冗余权重越高越偏向紧凑容量方案";
        case "electricity_price"
            textOut(i) = "电价越高，部分负荷高效运行带来的价值越大";
        case "prediction_error"
            textOut(i) = "正向预测偏差会导致设备偏大，负向峰值误差会侵蚀安全裕量";
        otherwise
            textOut(i) = "";
    end
end
end

function textOut = localizeSensitivityCheck(typeIn)
%LOCALIZESENSITIVITYCHECK 按敏感性类型给出中文建议校核。
typeIn = string(typeIn);
textOut = strings(size(typeIn));
for i = 1:numel(typeIn)
    switch typeIn(i)
        case "design_quantile"
            textOut(i) = "报告 P50/P95/P99 需求表，并说明为何选择 P99 用于优化";
        case "safety_factor"
            textOut(i) = "施工图级设计前，建议对安全系数做 +/- 0.02 扰动复算";
        case "topsis_weight"
            textOut(i) = "若推荐方案存在争议，可比较 0.50/0.50、0.55/0.45 和 0.70/0.30 权重排序";
        case "electricity_price"
            textOut(i) = "将论文结果转为工程估算时，应使用当地电价和实际运行时段";
        case "prediction_error"
            textOut(i) = "最终选型前应保留额外工程裕量，或用实测峰值数据校准模型";
        otherwise
            textOut(i) = "";
    end
end
end

function namesOut = localizeRiskLevel(namesIn)
%LOCALIZERISKLEVEL 将风险等级转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "low"
            namesOut(i) = "低";
        case "medium"
            namesOut(i) = "中";
        case "high"
            namesOut(i) = "高";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function namesOut = localizeEngineeringBoundaryNames(namesIn)
%LOCALIZEENGINEERINGBOUNDARYNAMES 将工程边界类型转换为中文。
namesIn = string(namesIn);
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    switch namesIn(i)
        case "data_source"
            namesOut(i) = "数据来源";
        case "subsystem_conversion"
            namesOut(i) = "子系统需求换算";
        case "hydraulic_and_airside_design"
            namesOut(i) = "水力与风侧设计";
        case "equipment_performance"
            namesOut(i) = "设备性能";
        case "control_and_comfort"
            namesOut(i) = "控制与舒适性";
        case "final_design_use"
            namesOut(i) = "最终设计用途";
        otherwise
            namesOut(i) = namesIn(i);
    end
end
end

function textOut = localizeEngineeringBoundaryTreatment(boundaryIn)
%LOCALIZEENGINEERINGBOUNDARYTREATMENT 按工程边界给出中文当前处理方式。
boundaryIn = string(boundaryIn);
textOut = strings(size(boundaryIn));
for i = 1:numel(boundaryIn)
    switch boundaryIn(i)
        case "data_source"
            textOut(i) = "使用构造的年度车站数据集验证方法链条";
        case "subsystem_conversion"
            textOut(i) = "通过回归和工程比例将总负荷映射为冷机、风机、水泵和 AHU 需求";
        case "hydraulic_and_airside_design"
            textOut(i) = "校核装机容量和安全裕量，未求解风管阻力、水泵扬程或管网平衡";
        case "equipment_performance"
            textOut(i) = "采用简化 COP/PLR 和变频曲线，而非厂家专用选型数据";
        case "control_and_comfort"
            textOut(i) = "评价容量和能耗，不模拟温度、湿度、CO2 或乘客舒适性闭环控制";
        case "final_design_use"
            textOut(i) = "适用于论文层面的方法验证和初步方案比较";
        otherwise
            textOut(i) = "";
    end
end
end

function textOut = localizeEngineeringBoundaryNeeds(boundaryIn)
%LOCALIZEENGINEERINGBOUNDARYNEEDS 按工程边界给出中文详细设计补充项。
boundaryIn = string(boundaryIn);
textOut = strings(size(boundaryIn));
for i = 1:numel(boundaryIn)
    switch boundaryIn(i)
        case "data_source"
            textOut(i) = "需要 BMS、AFC 客流和气象实测数据校准";
        case "subsystem_conversion"
            textOut(i) = "需要空气热湿计算、新风标准校核和设备表复核";
        case "hydraulic_and_airside_design"
            textOut(i) = "需要完整风侧/水侧阻力计算和平衡校核";
        case "equipment_performance"
            textOut(i) = "需要厂家样本曲线、最小负荷率、备用逻辑和维护约束";
        case "control_and_comfort"
            textOut(i) = "需要动态控制仿真及室内环境标准符合性校核";
        case "final_design_use"
            textOut(i) = "需要设计院复核、规范符合性审查和项目专用设备选型";
        otherwise
            textOut(i) = "";
    end
end
end

function textOut = replaceKnownText(textIn, englishList, chineseList)
%REPLACEKNOWNTEXT 按固定文本映射转换字符串数组。
textIn = string(textIn);
textOut = strings(size(textIn));
for i = 1:numel(textIn)
    idx = find(textIn(i) == englishList, 1);
    if isempty(idx)
        textOut(i) = textIn(i);
    else
        textOut(i) = chineseList(idx);
    end
end
end
