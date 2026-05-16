function optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult)
%STEP4_CAPACITY_OPTIMIZATION Optimize capacity with NSGA-II and TOPSIS.

stepTimer = tic;
fprintf("  Step 4.1 Preparing design load from predicted and observed test loads...\n");
loadDemand = [
    predictionResult.futureLoad(:);
    predictionResult.yTest(:);
    predictionResult.yTestLSTM(:)
];
loadDemand = loadDemand(~isnan(loadDemand));
if isempty(loadDemand)
    error("No valid load demand data is available for capacity optimization.");
end
designLoad = max(loadDemand, [], "omitnan");
fprintf("  Design load = %.2f kW, load samples for optimization = %d.\n", designLoad, numel(loadDemand));

optimizationResult = struct();
optimizationResult.designLoadKw = designLoad;
fprintf("  Step 4.2 Building baseline scheme...\n");
optimizationResult.baselineScheme = buildBaselineScheme(cfg, designLoad);
fprintf("  Baseline cooling capacity = %.2f kW, redundancy = %.2f%%.\n", ...
    optimizationResult.baselineScheme.totalCoolingCapacityKw, ...
    optimizationResult.baselineScheme.redundancyRate * 100);

fprintf("  Step 4.3 Running capacity optimization, population=%d, generations=%d...\n", ...
    cfg.populationSize, cfg.maxGenerations);
[paretoSet, paretoObjective] = solveCapacityOptimization(cfg, designLoad, loadDemand);
[paretoObjective, uniqueIdx] = unique(paretoObjective, "rows", "stable");
paretoSet = paretoSet(uniqueIdx, :);
fprintf("  Pareto solutions generated: %d.\n", size(paretoSet, 1));

fprintf("  Step 4.4 Ranking Pareto solutions with TOPSIS...\n");
[bestScheme, topsisTable] = chooseByTopsis(cfg, paretoSet, paretoObjective);

optimizationResult.paretoSet = paretoSet;
optimizationResult.paretoObjective = paretoObjective;
optimizationResult.bestScheme = decodeScheme(cfg, bestScheme);
optimizationResult.topsisTable = topsisTable;
optimizationResult.evaluationTable = compareSchemes(cfg, optimizationResult.baselineScheme, optimizationResult.bestScheme, loadDemand);
optimizationResult.analysisSummary = struct( ...
    "bestK", analysisResult.bestK, ...
    "selectedFeatureCount", numel(analysisResult.selectedFeatures));

topsisFile = fullfile(cfg.tableDir, "step4_topsis_ranking.csv");
evaluationFile = fullfile(cfg.tableDir, "step4_scheme_evaluation.csv");
writetable(optimizationResult.topsisTable, topsisFile);
writetable(optimizationResult.evaluationTable, evaluationFile);

plotStep4Figures(cfg, optimizationResult);

fprintf("  Recommended cooling capacity = %.2f kW, redundancy = %.2f%%.\n", ...
    optimizationResult.bestScheme.totalCoolingCapacityKw, ...
    optimizationResult.evaluationTable.redundancyRate(2) * 100);
fprintf("  Saved: %s\n", topsisFile);
fprintf("  Saved: %s\n", evaluationFile);
fprintf("  Step 4 finished in %.1f seconds.\n", toc(stepTimer));
end

function baseline = buildBaselineScheme(cfg, designLoad)
targetCapacity = designLoad * (1 + cfg.baselineRedundancyRate);
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
    cfg.fanCapacityList, cfg.fanCountRange, estimateFanDemand(designLoad) * (1 + cfg.baselineRedundancyRate));
[baseline.pumpCapacityKw, baseline.pumpCount] = chooseBaselinePair( ...
    cfg.pumpCapacityList, cfg.pumpCountRange, estimatePumpDemand(designLoad) * (1 + cfg.baselineRedundancyRate));
[baseline.ahuAirflow, baseline.ahuCount] = chooseBaselinePair( ...
    cfg.ahuAirflowList, cfg.ahuCountRange, estimateAhuDemand(designLoad) * (1 + cfg.baselineRedundancyRate));
baseline.totalCoolingCapacityKw = baseline.chillerCapacityKw * baseline.chillerCount;
baseline.totalFanCapacityKw = baseline.fanCapacityKw * baseline.fanCount;
baseline.totalPumpCapacityKw = baseline.pumpCapacityKw * baseline.pumpCount;
baseline.totalAhuAirflow = baseline.ahuAirflow * baseline.ahuCount;
baseline.redundancyRate = calculateCompositeRedundancy(cfg, baseline, designLoad);
baseline.lifecycleCost = estimateLifecycleCost(cfg, baseline, designLoad, designLoad);
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

function [paretoSet, paretoObjective] = solveCapacityOptimization(cfg, designLoad, loadDemand)
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

    objective = @(x) capacityObjectives(cfg, round(x), designLoad, loadDemand);
    constraint = @(x) capacityConstraints(cfg, round(x), designLoad);
    [paretoSet, paretoObjective] = gamultiobj(objective, nvars, [], [], [], [], lb, ub, constraint, options);
    paretoSet = round(paretoSet);
    [discreteSet, discreteObjective] = enumerateDiscretePareto(cfg, designLoad, loadDemand);
    paretoSet = [paretoSet; discreteSet];
    paretoObjective = [paretoObjective; discreteObjective];
else
    fprintf("    gamultiobj not detected. Using fallback grid search.\n");
    [paretoSet, paretoObjective] = enumerateDiscretePareto(cfg, designLoad, loadDemand);
end
end

function f = capacityObjectives(cfg, x, designLoad, loadDemand)
scheme = decodeScheme(cfg, x);
scheme.totalCoolingCapacityKw = scheme.chillerCapacityKw * scheme.chillerCount;
scheme.totalFanCapacityKw = scheme.fanCapacityKw * scheme.fanCount;
scheme.totalPumpCapacityKw = scheme.pumpCapacityKw * scheme.pumpCount;
scheme.totalAhuAirflow = scheme.ahuAirflow * scheme.ahuCount;
scheme.redundancyRate = calculateCompositeRedundancy(cfg, scheme, designLoad);
scheme.lifecycleCost = estimateLifecycleCost(cfg, scheme, mean(loadDemand, "omitnan"), designLoad);
f = [scheme.lifecycleCost, scheme.redundancyRate];
end

function [c, ceq] = capacityConstraints(cfg, x, designLoad)
scheme = decodeScheme(cfg, x);
totalCoolingCapacity = scheme.chillerCapacityKw * scheme.chillerCount;
totalFanCapacity = scheme.fanCapacityKw * scheme.fanCount;
totalPumpCapacity = scheme.pumpCapacityKw * scheme.pumpCount;
totalAhuAirflow = scheme.ahuAirflow * scheme.ahuCount;

fanDemand = estimateFanDemand(designLoad);
pumpDemand = estimatePumpDemand(designLoad);
ahuDemand = estimateAhuDemand(designLoad);

c = [
    cfg.minCapacitySafetyFactor * designLoad - totalCoolingCapacity
    cfg.minCapacitySafetyFactor * fanDemand - totalFanCapacity
    cfg.minCapacitySafetyFactor * pumpDemand - totalPumpCapacity
    cfg.minCapacitySafetyFactor * ahuDemand - totalAhuAirflow
];
ceq = [];
end

function [paretoSet, paretoObjective] = enumerateDiscretePareto(cfg, designLoad, loadDemand)
candidateSet = [];
candidateObj = [];

coolingOptions = buildPairOptions(cfg.chillerCapacityList, cfg.chillerCountRange, designLoad, cfg.minCapacitySafetyFactor, 22);
fanOptions = buildPairOptions(cfg.fanCapacityList, cfg.fanCountRange, estimateFanDemand(designLoad), cfg.minCapacitySafetyFactor, 10);
pumpOptions = buildPairOptions(cfg.pumpCapacityList, cfg.pumpCountRange, estimatePumpDemand(designLoad), cfg.minCapacitySafetyFactor, 10);
ahuOptions = buildPairOptions(cfg.ahuAirflowList, cfg.ahuCountRange, estimateAhuDemand(designLoad), cfg.minCapacitySafetyFactor, 10);

for i = 1:size(coolingOptions, 1)
    for j = 1:size(fanOptions, 1)
        for k = 1:size(pumpOptions, 1)
            for m = 1:size(ahuOptions, 1)
                x = [coolingOptions(i, :), fanOptions(j, :), pumpOptions(k, :), ahuOptions(m, :)];
                [c, ~] = capacityConstraints(cfg, x, designLoad);
                if all(c <= 0)
                    f = capacityObjectives(cfg, x, designLoad, loadDemand);
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

function annualEnergy = estimateAnnualEnergy(~, scheme, representativeLoad, designLoad)
loadRatio = representativeLoad / max(scheme.totalCoolingCapacityKw, eps);
compositeRedundancy = calculateCompositeRedundancy([], scheme, designLoad);
stagingBenefit = 0.045 * min(max(scheme.chillerCount - 1, 0), 2);
oversizePenalty = 0.90 * max(compositeRedundancy - 0.10, 0);
partLoadPenalty = 1 + 0.24 * max(loadRatio - 0.75, 0) + oversizePenalty - stagingBenefit;
partLoadPenalty = max(partLoadPenalty, 0.82);
annualEnergy = representativeLoad * partLoadPenalty * 24 * 120;
end

function lifecycleCost = estimateLifecycleCost(cfg, scheme, representativeLoad, designLoad)
initialCost = estimateInitialCost(cfg, scheme);
annualEnergy = estimateAnnualEnergy(cfg, scheme, representativeLoad, designLoad);
annualOperatingCost = annualEnergy * cfg.electricityPrice;
presentWorthFactor = (1 - (1 + cfg.discountRate) ^ (-cfg.lifeYears)) / cfg.discountRate;
maintenanceCost = initialCost * cfg.maintenanceRate * presentWorthFactor;
lifecycleCost = initialCost + annualOperatingCost * presentWorthFactor + maintenanceCost;
end

function evaluationTable = compareSchemes(cfg, baseline, bestScheme, loadDemand)
designLoad = max(loadDemand, [], "omitnan");
representativeLoad = mean(loadDemand, "omitnan");
baseline.lifecycleCost = estimateLifecycleCost(cfg, baseline, representativeLoad, designLoad);
baseline.redundancyRate = calculateCompositeRedundancy(cfg, baseline, designLoad);
bestScheme.redundancyRate = calculateCompositeRedundancy(cfg, bestScheme, designLoad);
bestScheme.lifecycleCost = estimateLifecycleCost(cfg, bestScheme, representativeLoad, designLoad);

scheme = ["baseline"; "optimized"];
totalCoolingCapacityKw = [baseline.totalCoolingCapacityKw; bestScheme.totalCoolingCapacityKw];
lifecycleCost = [baseline.lifecycleCost; bestScheme.lifecycleCost];
redundancyRate = [baseline.redundancyRate; bestScheme.redundancyRate];
initialCost = [
    estimateInitialCost(cfg, baseline)
    estimateInitialCost(cfg, bestScheme)
];
annualEnergyKwh = [
    estimateAnnualEnergy(cfg, baseline, representativeLoad, designLoad)
    estimateAnnualEnergy(cfg, bestScheme, representativeLoad, designLoad)
];

costReductionRate = [0; (baseline.lifecycleCost - bestScheme.lifecycleCost) / baseline.lifecycleCost];
redundancyReductionRate = [0; (baseline.redundancyRate - bestScheme.redundancyRate) / baseline.redundancyRate];
energySavingRate = [0; (annualEnergyKwh(1) - annualEnergyKwh(2)) / annualEnergyKwh(1)];

evaluationTable = table(scheme, totalCoolingCapacityKw, lifecycleCost, redundancyRate, ...
    initialCost, annualEnergyKwh, costReductionRate, redundancyReductionRate, energySavingRate);
end

function redundancy = calculateCompositeRedundancy(~, scheme, designLoad)
coolingDemand = designLoad;
fanDemand = estimateFanDemand(designLoad);
pumpDemand = estimatePumpDemand(designLoad);
ahuDemand = estimateAhuDemand(designLoad);

coolingRedundancy = (scheme.totalCoolingCapacityKw - coolingDemand) / coolingDemand;
fanRedundancy = (scheme.totalFanCapacityKw - fanDemand) / fanDemand;
pumpRedundancy = (scheme.totalPumpCapacityKw - pumpDemand) / pumpDemand;
ahuRedundancy = (scheme.totalAhuAirflow - ahuDemand) / ahuDemand;

redundancy = mean([coolingRedundancy, fanRedundancy, pumpRedundancy, ahuRedundancy]);
end

function fanDemand = estimateFanDemand(designLoad)
fanDemand = 18 + 0.055 * designLoad;
end

function pumpDemand = estimatePumpDemand(designLoad)
pumpDemand = 12 + 0.040 * designLoad;
end

function ahuDemand = estimateAhuDemand(designLoad)
ahuDemand = 115 * designLoad;
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
    exportgraphics(fig, fullfile(cfg.figureDir, fileName), "Resolution", 300);
end
end
