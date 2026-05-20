function optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult)
%STEP4_CAPACITY_OPTIMIZATION Optimize capacity with NSGA-II and TOPSIS.

stepTimer = tic;
fprintf("  Step 4.1 Loading design load from LSTM full prediction...\n");
optimizationScenarioName = cfg.optimizationScenarioName;
demand = predictionResult.scenarioDemand.(optimizationScenarioName);
rawDemand = demand;
predictionErrorMarginKw = predictionResult.metricsLSTM.RMSE * cfg.predictionErrorRmseFactor;
demand = applyPredictionErrorMargin(cfg, demand, predictionErrorMarginKw);
designLoad = demand.totalCoolingLoadKw;
representativeLoad = predictionResult.representativeLoadKw;
if isfield(predictionResult, "predictedProfile") && isfield(predictionResult.predictedProfile, "totalCoolingLoadKw")
    loadProfileKw = predictionResult.predictedProfile.totalCoolingLoadKw;
else
    loadProfileKw = representativeLoad;
end
fprintf("  Design load = %.2f kW (%s, P%.0f total load from LSTM full prediction).\n", ...
    designLoad, optimizationScenarioName, demand.quantile * 100);
fprintf("  Prediction error margin = %.2f kW (%.1f x LSTM RMSE); raw design load = %.2f kW.\n", ...
    predictionErrorMarginKw, cfg.predictionErrorRmseFactor, rawDemand.totalCoolingLoadKw);
fprintf("  Representative load = %.2f kW (mean of predicted profile).\n", representativeLoad);
fprintf("  Subsystem design demands: chiller=%.2f kW, fan=%.2f kW, pump=%.2f kW, AHU=%.0f m3/h.\n", ...
    demand.chillerDemandKw, demand.fanDemandKw, demand.pumpDemandKw, demand.ahuDemand);

optimizationResult = struct();
optimizationResult.designLoadKw = designLoad;
optimizationResult.representativeLoadKw = representativeLoad;
optimizationResult.designDemand = demand;
optimizationResult.rawDesignDemand = rawDemand;
optimizationResult.predictionErrorMarginKw = predictionErrorMarginKw;
fprintf("  Step 4.2 Building baseline scheme...\n");
optimizationResult.baselineScheme = buildBaselineScheme(cfg, demand);
fprintf("  Baseline cooling capacity = %.2f kW, redundancy = %.2f%%.\n", ...
    optimizationResult.baselineScheme.totalCoolingCapacityKw, ...
    optimizationResult.baselineScheme.redundancyRate * 100);

fprintf("  Step 4.3 Running capacity optimization, population=%d, generations=%d...\n", ...
    cfg.populationSize, cfg.maxGenerations);
[paretoSet, paretoObjective] = solveCapacityOptimization(cfg, demand, representativeLoad, loadProfileKw);
[paretoObjective, uniqueIdx] = unique(paretoObjective, "rows", "stable");
paretoSet = paretoSet(uniqueIdx, :);
[paretoSet, paretoObjective] = limitParetoSetToTargetBand(paretoSet, paretoObjective);
fprintf("  Pareto solutions generated: %d.\n", size(paretoSet, 1));

fprintf("  Step 4.4 Ranking Pareto solutions with TOPSIS...\n");
[bestScheme, topsisTable] = chooseByTopsis(cfg, paretoSet, paretoObjective);

optimizationResult.paretoSet = paretoSet;
optimizationResult.paretoObjective = paretoObjective;
optimizationResult.bestScheme = decodeScheme(cfg, bestScheme);
optimizationResult.topsisTable = topsisTable;
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

topsisFile = fullfile(cfg.tableDir, "step4_topsis_ranking.csv");
evaluationFile = fullfile(cfg.tableDir, "step4_scheme_evaluation.csv");
subsystemFile = fullfile(cfg.tableDir, "step4_subsystem_redundancy.csv");
scenarioCheckFile = fullfile(cfg.tableDir, "step4_scenario_capacity_check.csv");
engineeringConstraintFile = fullfile(cfg.tableDir, "step4_engineering_constraint_check.csv");
linkageFile = fullfile(cfg.tableDir, "step4_research_linkage.csv");
sensitivityFile = fullfile(cfg.tableDir, "step4_sensitivity_analysis.csv");
boundaryFile = fullfile(cfg.tableDir, "step4_engineering_boundary.csv");
writetable(optimizationResult.topsisTable, topsisFile);
writetable(optimizationResult.evaluationTable, evaluationFile);
writetable(optimizationResult.subsystemRedundancyTable, subsystemFile);
writetable(optimizationResult.scenarioCapacityCheck, scenarioCheckFile);
writetable(optimizationResult.engineeringConstraintCheck, engineeringConstraintFile);
writetable(optimizationResult.researchLinkageTable, linkageFile);
writetable(optimizationResult.sensitivityTable, sensitivityFile);
writetable(optimizationResult.engineeringBoundaryTable, boundaryFile);

plotStep4Figures(cfg, optimizationResult);

fprintf("  Recommended cooling capacity = %.2f kW, redundancy = %.2f%%.\n", ...
    optimizationResult.bestScheme.totalCoolingCapacityKw, ...
    optimizationResult.evaluationTable.redundancyRate(2) * 100);
fprintf("  Saved: %s\n", topsisFile);
fprintf("  Saved: %s\n", evaluationFile);
fprintf("  Saved: %s\n", subsystemFile);
fprintf("  Saved: %s\n", scenarioCheckFile);
fprintf("  Saved: %s\n", engineeringConstraintFile);
fprintf("  Saved: %s\n", linkageFile);
fprintf("  Saved: %s\n", sensitivityFile);
fprintf("  Saved: %s\n", boundaryFile);
fprintf("  Step 4 finished in %.1f seconds.\n", toc(stepTimer));
end

function demandOut = applyPredictionErrorMargin(cfg, demandIn, predictionErrorMarginKw)
demandOut = demandIn;
if predictionErrorMarginKw <= 0
    return;
end

totalBase = max(demandIn.totalCoolingLoadKw, eps);
fanPerCoolingKw = demandIn.fanDemandKw / totalBase;
pumpPerCoolingKw = demandIn.pumpDemandKw / totalBase;

demandOut.predictionErrorMarginKw = predictionErrorMarginKw;
demandOut.totalCoolingLoadKw = demandIn.totalCoolingLoadKw + predictionErrorMarginKw;
demandOut.chillerDemandKw = demandIn.chillerDemandKw + predictionErrorMarginKw;
demandOut.fanDemandKw = demandIn.fanDemandKw + predictionErrorMarginKw * fanPerCoolingKw;
demandOut.pumpDemandKw = demandIn.pumpDemandKw + predictionErrorMarginKw * pumpPerCoolingKw;
demandOut.ahuDemand = demandIn.ahuDemand + predictionErrorMarginKw * cfg.ahuAirflowPerKw;
end

function [paretoSet, paretoObjective] = limitParetoSetToTargetBand(paretoSet, paretoObjective)
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
targetCapacity = demand.chillerDemandKw * (1 + cfg.baselineRedundancyRate);
chillerCapacity = max(cfg.chillerCapacityList);
chillerCount = max(cfg.chillerCountRange);

for count = cfg.chillerCountRange
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
baseline.lifecycleCost = estimateLifecycleCost(cfg, baseline, demand.totalCoolingLoadKw, demand, demand.totalCoolingLoadKw);
end

function [unitCapacity, count] = chooseBaselinePair(capacityList, countRange, targetCapacity)
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
hasGamultiobj = exist("gamultiobj", "file") == 2;

if hasGamultiobj
    fprintf("    Global Optimization Toolbox detected. Using gamultiobj (NSGA-II).\n");
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

    objective = @(x) capacityObjectives(cfg, round(x), demand, representativeLoad, loadProfileKw);
    constraint = @(x) capacityConstraints(cfg, round(x), demand, representativeLoad);
    [paretoSet, paretoObjective] = gamultiobj(objective, nvars, [], [], [], [], lb, ub, constraint, options);
    paretoSet = round(paretoSet);
    [discreteSet, discreteObjective] = enumerateDiscretePareto(cfg, demand, representativeLoad, loadProfileKw);
    paretoSet = [paretoSet; discreteSet];
    paretoObjective = [paretoObjective; discreteObjective];
else
    fprintf("    gamultiobj not detected. Using fallback grid search.\n");
    [paretoSet, paretoObjective] = enumerateDiscretePareto(cfg, demand, representativeLoad, loadProfileKw);
end
end

function f = capacityObjectives(cfg, x, demand, representativeLoad, loadProfileKw)
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
scheme = decodeScheme(cfg, x);
totalCoolingCapacity = scheme.chillerCapacityKw * scheme.chillerCount;
totalFanCapacity = scheme.fanCapacityKw * scheme.fanCount;
totalPumpCapacity = scheme.pumpCapacityKw * scheme.pumpCount;
totalAhuAirflow = scheme.ahuAirflow * scheme.ahuCount;

extremeMarginFactor = 1 + cfg.minExtremeCapacityMargin;
typicalChillerPLR = representativeLoad / max(totalCoolingCapacity, eps);
minimumPLRConstraint = cfg.minTypicalChillerPLR - typicalChillerPLR;
matchingConstraints = buildMatchingConstraints(cfg, totalCoolingCapacity, totalFanCapacity, totalPumpCapacity, totalAhuAirflow);

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
candidateSet = [];
candidateObj = [];

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
rows = [];
scores = [];
target = demand * safetyFactor;

for i = 1:numel(capacityList)
    for j = 1:numel(countRange)
        totalCapacity = capacityList(i) * countRange(j);
        if totalCapacity >= target
            redundancy = (totalCapacity - demand) / demand;
            if redundancy <= 0.85
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
initialCost = ...
    scheme.chillerCapacityKw * scheme.chillerCount * cfg.chillerUnitCostPerKw + ...
    scheme.fanCapacityKw * scheme.fanCount * cfg.fanUnitCostPerKw + ...
    scheme.pumpCapacityKw * scheme.pumpCount * cfg.pumpUnitCostPerKw + ...
    scheme.ahuAirflow * scheme.ahuCount * cfg.ahuUnitCostPerAirflow;
end

function annualEnergy = estimateAnnualEnergy(cfg, scheme, representativeLoad, demand, loadProfileKw)
if nargin < 5 || isempty(loadProfileKw)
    loadProfileKw = representativeLoad;
end
annualEnergy = hvac_estimate_annual_energy_detailed(cfg, scheme, loadProfileKw, demand);
end

function lifecycleCost = estimateLifecycleCost(cfg, scheme, representativeLoad, demand, loadProfileKw)
initialCost = estimateInitialCost(cfg, scheme);
annualEnergy = estimateAnnualEnergy(cfg, scheme, representativeLoad, demand, loadProfileKw);
annualOperatingCost = annualEnergy * cfg.electricityPrice;
presentWorthFactor = (1 - (1 + cfg.discountRate) ^ (-cfg.lifeYears)) / cfg.discountRate;
maintenanceCost = initialCost * cfg.maintenanceRate * presentWorthFactor;
lifecycleCost = initialCost + annualOperatingCost * presentWorthFactor + maintenanceCost;
end

function evaluationTable = compareSchemes(cfg, baseline, bestScheme, demand, representativeLoad, loadProfileKw)
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
coolingRedundancy = (scheme.totalCoolingCapacityKw - demand.chillerDemandKw) / demand.chillerDemandKw;
fanRedundancy = (scheme.totalFanCapacityKw - demand.fanDemandKw) / demand.fanDemandKw;
pumpRedundancy = (scheme.totalPumpCapacityKw - demand.pumpDemandKw) / demand.pumpDemandKw;
ahuRedundancy = (scheme.totalAhuAirflow - demand.ahuDemand) / demand.ahuDemand;

redundancy = mean([coolingRedundancy, fanRedundancy, pumpRedundancy, ahuRedundancy]);
end

function redundancyTable = compareSubsystemRedundancy(~, baseline, bestScheme, demand)
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
note(1) = "P99 demand is increased by LSTM RMSE margin before capacity optimization";

actualValue(2) = typicalPLR;
requiredMin(2) = cfg.minTypicalChillerPLR;
pass(2) = actualValue(2) >= requiredMin(2);
note(2) = "Avoids selecting a cooling capacity that is too oversized for representative load";

actualValue(3:6) = [
    (scheme.totalCoolingCapacityKw - requiredCooling) / requiredCooling
    (scheme.totalFanCapacityKw - requiredFan) / requiredFan
    (scheme.totalPumpCapacityKw - requiredPump) / requiredPump
    (scheme.totalAhuAirflow - requiredAhu) / requiredAhu
];
requiredMin(3:6) = cfg.minExtremeCapacityMargin;
pass(3:6) = actualValue(3:6) >= requiredMin(3:6);
note(3:6) = "Capacity must retain explicit margin after safety factors and prediction-error correction";

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
note(7:9) = "Keeps airside, waterside, and AHU capacity matched with cooling capacity";

checkTable = table(constraintName, actualValue, requiredMin, requiredMax, pass, note);
end

function plotStep4Figures(cfg, optimizationResult)
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

fig1 = figure("Name", "Step 4 - Pareto Front", "Visible", figureVisibility(cfg));
scatter(optimizationResult.paretoObjective(:, 1) / 10000, ...
    optimizationResult.paretoObjective(:, 2) * 100, 45, "filled");
xlabel("Lifecycle cost / 10k yuan");
ylabel("Capacity redundancy / %");
title("Pareto Front of Capacity Optimization");
grid on;
saveFigureIfNeeded(cfg, fig1, "step4_pareto_front.png");

fig2 = figure("Name", "Step 4 - Scheme Comparison", "Visible", figureVisibility(cfg));
tiledlayout(1, 2);
nexttile;
bar(categorical(optimizationResult.evaluationTable.scheme), ...
    optimizationResult.evaluationTable.lifecycleCost / 10000);
ylabel("Lifecycle cost / 10k yuan");
title("Lifecycle Cost");
grid on;
nexttile;
bar(categorical(optimizationResult.evaluationTable.scheme), ...
    optimizationResult.evaluationTable.redundancyRate * 100);
ylabel("Redundancy / %");
title("Capacity Redundancy");
grid on;
saveFigureIfNeeded(cfg, fig2, "step4_scheme_comparison.png");
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
if ~exist(cfg.figureDir, "dir")
    mkdir(cfg.figureDir);
end
end
