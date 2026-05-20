function cfg = config()
%CONFIG Centralized parameters for the metro station HVAC thesis workflow.
% This function returns one structure used by main.m and all step*.m files.
% Keep tunable assumptions here so experiments can be repeated by changing
% configuration values instead of editing the workflow logic.

% Project identity and raw-data location.
cfg.projectName = "MetroStationHVACCapacityOptimization";
cfg.dataFile = fullfile("data", "fuzhou_metro_dongjiekou_2025.csv");

% Output folders are created by main.m before the workflow starts.
cfg.outputDir = "output";
cfg.figureDir = fullfile(cfg.outputDir, "figures");
cfg.tableDir = fullfile(cfg.outputDir, "tables");
cfg.modelDir = fullfile(cfg.outputDir, "models");

% Data preparation
% timestampName and targetName define the common time axis and prediction
% target used across preprocessing, analysis, prediction, and optimization.
cfg.timestampName = "timestamp";
cfg.targetName = "total_cooling_load_kw";
% The dataset is sampled every 15 minutes; this controls daily curve length,
% annual energy scaling, and lag-feature interpretation.
cfg.timeStepMinutes = 15;
% Missing numeric values are linearly interpolated first, then filled with the
% nearest available value for edge cases.
cfg.missingMethod = "linear";
% zscore standardization keeps features with different units comparable for
% correlation ranking and neural-network training.
cfg.standardizeMethod = "zscore";
% Load lags add short-term and one-day historical load information. With
% 15-minute data, 96 steps means the same time point on the previous day.
cfg.loadLagSteps = [1, 4, 8, 96];

% Continuous predictors used to build the standardized feature table.
cfg.continuousFeatureNames = [ ...
    "entry_flow", ...
    "exit_flow", ...
    "platform_passengers", ...
    "outdoor_temp", ...
    "outdoor_rh", ...
    "solar_radiation", ...
    "platform_temp", ...
    "platform_rh", ...
    "co2" ...
];

% Columns preserved for engineering interpretation but not treated as generic
% predictors in the main standardized feature table.
cfg.referenceOnlyNames = [ ...
    "chiller_load_kw", ...
    "fan_power_kw", ...
    "pump_power_kw", ...
    "people_load_kw", ...
    "fresh_air_load_kw", ...
    "envelope_load_kw", ...
    "equipment_load_kw" ...
];

% Component columns used to explain how the total cooling load is decomposed.
cfg.loadComponentNames = [ ...
    "people_load_kw", ...
    "fresh_air_load_kw", ...
    "envelope_load_kw", ...
    "equipment_load_kw" ...
];

% Pearson and clustering
% topFeatureNum controls how many high-correlation features are passed to the
% prediction stage.
cfg.topFeatureNum = 10;
% Candidate K values for typical-day K-Means clustering.
cfg.clusterKRange = 2:4;
% preferredClusterK/minSilhouette are kept as experiment references; the
% current implementation still selects K by the highest mean silhouette.
cfg.preferredClusterK = 4;
cfg.preferredClusterMinSilhouette = 0.55;
% Number of 15-minute samples in one full day.
cfg.dailyPointNum = 24 * 60 / cfg.timeStepMinutes;
% false clusters days by absolute load level; true clusters by normalized shape.
cfg.normalizeDailyClusterCurves = false;
% Fixed seed makes K-Means and other randomized routines reproducible.
cfg.rngSeed = 202507;

% Prediction split
% Chronological split: train first, validate middle, test final period.
cfg.trainRatio = 0.7;
cfg.valRatio = 0.2;
cfg.testRatio = 0.1;
% Prevents MAPE from exploding when true load values are very small.
cfg.mapeMinLoadKw = 180;

% LSTM
% sequenceLength is the number of historical time steps supplied to each LSTM
% sample. With 15-minute data, 16 steps covers four hours.
cfg.sequenceLength = 16;
cfg.lstmHiddenUnits = [96, 48];
cfg.maxEpochs = 120;
cfg.miniBatchSize = 32;
cfg.initialLearnRate = 0.0008;
cfg.gradientThreshold = 1;
cfg.validationPatience = 50;
cfg.learnRateDropPeriod = 40;
cfg.learnRateDropFactor = 0.5;
cfg.executionEnvironment = "cpu";

% BP neural network
% BP is a simpler comparison model against the sequence-based LSTM model.
cfg.bpHiddenUnits = [20, 10];

% NSGA-II
% These values affect the Global Optimization Toolbox path. If gamultiobj is
% unavailable, step4 falls back to a discrete grid search.
cfg.populationSize = 80;
cfg.maxGenerations = 150;

% Economic assumptions
% Used to convert equipment investment and annual electricity use into
% lifecycle cost for the optimization objective.
cfg.electricityPrice = 0.85;
cfg.lifeYears = 15;
cfg.discountRate = 0.05;
cfg.coolingSeasonDays = 120;

% Engineering energy model assumptions
% Simplified equipment-performance assumptions for thesis-level scheme
% comparison. They should be replaced by manufacturer curves in detailed design.
cfg.chillerRatedCOP = 5.2;
cfg.chillerMinPLR = 0.25;
cfg.chillerPLRCurve = [0.25, 0.50, 0.75, 1.00; 0.78, 0.92, 1.00, 0.96];
cfg.vfdExponent = 2.6;
cfg.minTypicalChillerPLR = 0.28;
cfg.minExtremeCapacityMargin = 0.03;
cfg.predictionErrorRmseFactor = 1.0;
cfg.fanCoolingCapacityRatioRange = [0.05, 0.09];
cfg.pumpCoolingCapacityRatioRange = [0.045, 0.08];
cfg.ahuAirflowPerCoolingKwRange = [260, 360];

% Equipment candidates. Units are kW unless noted otherwise.
% Optimization variables are indices into these discrete candidate lists plus
% unit counts. AHU airflow is m3/h rather than kW.
cfg.chillerCapacityList = [100, 120, 140, 150, 160, 180, 200, 220, 240, 250, 280, 300, 320, 350, 380];
cfg.chillerCountRange = 1:4;
cfg.fanCapacityList = [16, 18, 20, 22, 24, 26, 28, 30, 32, 35, 40, 45, 50];
cfg.fanCountRange = 1:6;
cfg.pumpCapacityList = [14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40];
cfg.pumpCountRange = 1:6;
cfg.ahuAirflowList = [25000, 30000, 35000, 40000, 43000, 45000, 48000, 50000, 55000, 60000, 70000];
cfg.ahuCountRange = 1:4;

% Unit costs are rough thesis assumptions for relative scheme comparison.
cfg.chillerUnitCostPerKw = 1100;
cfg.fanUnitCostPerKw = 650;
cfg.pumpUnitCostPerKw = 520;
cfg.ahuUnitCostPerAirflow = 0.9;
cfg.maintenanceRate = 0.035;
cfg.baselineRedundancyRate = 0.28;
cfg.minCapacitySafetyFactor = 1.03;

% Prediction-to-capacity coupling
% Demand quantiles translate predicted load profiles into typical, peak, and
% extreme capacity-design scenarios.
cfg.capacityConfidenceLevels = [0.50, 0.90, 0.95, 0.99];
cfg.designConfidenceLevel = 0.90;
cfg.extremeConfidenceLevel = 0.99;
cfg.chillerSafetyFactor = 1.09;
cfg.fanSafetyFactor = 1.07;
cfg.pumpSafetyFactor = 1.07;
cfg.ahuSafetyFactor = 1.05;
cfg.scenarioNames = ["typical", "peak", "extreme"];
cfg.typicalQuantile = 0.50;
cfg.peakQuantile = 0.95;
cfg.extremeQuantile = 0.99;
cfg.optimizationScenarioName = "extreme";

% TOPSIS weights: lifecycle cost, redundancy rate.
% Both optimization objectives are "smaller is better"; these weights express
% the final decision preference after the Pareto set is generated.
cfg.topsisWeights = [0.55, 0.45];

% AHU airflow per unit cooling load (m³/h per kW)
% Derived from: m_dot = Q × 3600 / (ρ × cp × ΔT)
% For standard air (ρ=1.2 kg/m³, cp=1.005 kJ/kgK) and ΔT=10°C
cfg.ahuAirflowPerKw = 298;

% Display and figure output
% showFigures controls interactive windows; saveFigures controls PNG export.
% showTrainingProgress opens MATLAB training UI when supported.
cfg.showFigures = true;
cfg.saveFigures = true;
cfg.showTrainingProgress = true;
end
