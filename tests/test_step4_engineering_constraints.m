function tests = test_step4_engineering_constraints
tests = functiontests(localfunctions);
end

function testEngineeringConstraintCheckMatchesOptimizationRequirement(testCase)
cfg = config();
tmpRoot = tempname;
mkdir(tmpRoot);
cfg.outputDir = tmpRoot;
cfg.figureDir = fullfile(tmpRoot, "figures");
cfg.tableDir = fullfile(tmpRoot, "tables");
cfg.modelDir = fullfile(tmpRoot, "models");
mkdir(cfg.figureDir);
mkdir(cfg.tableDir);
mkdir(cfg.modelDir);

cfg.showFigures = false;
cfg.saveFigures = false;
cfg.showTrainingProgress = false;
cfg.populationSize = 20;
cfg.maxGenerations = 1;

cfg.minTypicalChillerPLR = 0.10;
cfg.minExtremeCapacityMargin = 0.03;
cfg.predictionErrorRmseFactor = 1;
cfg.ahuAirflowPerKw = 3;
cfg.chillerSafetyFactor = 1.00;
cfg.fanSafetyFactor = 1.00;
cfg.pumpSafetyFactor = 1.00;
cfg.ahuSafetyFactor = 1.00;
cfg.fanCoolingCapacityRatioRange = [0.00, 1.00];
cfg.pumpCoolingCapacityRatioRange = [0.00, 1.00];
cfg.ahuAirflowPerCoolingKwRange = [0.00, 2.00];
cfg.baselineRedundancyRate = 0.28;
cfg.optimizationScenarioName = "extreme";
cfg.scenarioNames = ["typical", "peak", "extreme"];

cfg.chillerCapacityList = [104.03, 208.06];
cfg.chillerCountRange = 1:2;
cfg.fanCapacityList = [10.403, 20.806];
cfg.fanCountRange = 1:2;
cfg.pumpCapacityList = [10.403, 20.806];
cfg.pumpCountRange = 1:2;
cfg.ahuAirflowList = [106.09, 212.18];
cfg.ahuCountRange = 1:2;

predictionResult = buildSyntheticPredictionResult();
analysisResult = buildSyntheticAnalysisResult();

optimizationResult = step4_capacity_optimization(cfg, predictionResult, analysisResult);
checkTable = optimizationResult.engineeringConstraintCheck;
marginRows = startsWith(checkTable.constraintName, "minimum_extreme_capacity_margin_");

verifyTrue(testCase, all(checkTable.pass(marginRows)), ...
    "Schemes satisfying the optimizer's explicit extreme-margin requirement should not fail the readable engineering check.");
end

function predictionResult = buildSyntheticPredictionResult()
baseDemand = struct( ...
    "totalCoolingLoadKw", 100, ...
    "chillerDemandKw", 100, ...
    "fanDemandKw", 10, ...
    "pumpDemandKw", 10, ...
    "ahuDemand", 100, ...
    "quantile", 0.99);

predictionResult = struct();
predictionResult.scenarioDemand = struct( ...
    "typical", baseDemand, ...
    "peak", baseDemand, ...
    "extreme", baseDemand);
predictionResult.representativeLoadKw = 50;
predictionResult.predictedProfile = struct("totalCoolingLoadKw", [40; 60; 80; 100]);
predictionResult.metricsLSTM = struct("RMSE", 1, "MAE", 0, "MAPE", 0, "R2", 1);
predictionResult.metrics = table( ...
    ["LSTM"; "BP"], ...
    [1; 2], ...
    [0; 1], ...
    [0; 1], ...
    [1; 0.9], ...
    'VariableNames', {'model', 'RMSE', 'MAE', 'MAPE', 'R2'});
end

function analysisResult = buildSyntheticAnalysisResult()
analysisResult = struct();
analysisResult.bestK = 4;
analysisResult.selectedFeatures = "entry_flow";
analysisResult.silhouetteTable = table( ...
    [4], ...
    [0.68], ...
    'VariableNames', {'K', 'meanSilhouette'});
end
