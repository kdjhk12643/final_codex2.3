function cfg = config()
%CONFIG Centralized parameters for the metro station HVAC thesis workflow.

cfg.projectName = "MetroStationHVACCapacityOptimization";
cfg.dataFile = fullfile("data", "fuzhou_metro_dongjiekou_2025.csv");

cfg.outputDir = "output";
cfg.figureDir = fullfile(cfg.outputDir, "figures");
cfg.tableDir = fullfile(cfg.outputDir, "tables");
cfg.modelDir = fullfile(cfg.outputDir, "models");

% Data preparation
cfg.timestampName = "timestamp";
cfg.targetName = "total_cooling_load_kw";
cfg.timeStepMinutes = 15;
cfg.missingMethod = "linear";
cfg.standardizeMethod = "zscore";
cfg.loadLagSteps = [1, 4, 8, 96];

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

cfg.referenceOnlyNames = [ ...
    "chiller_load_kw", ...
    "fan_power_kw", ...
    "pump_power_kw", ...
    "people_load_kw", ...
    "fresh_air_load_kw", ...
    "envelope_load_kw", ...
    "equipment_load_kw" ...
];

cfg.loadComponentNames = [ ...
    "people_load_kw", ...
    "fresh_air_load_kw", ...
    "envelope_load_kw", ...
    "equipment_load_kw" ...
];

% Pearson and clustering
cfg.topFeatureNum = 10;
cfg.clusterKRange = 2:6;
cfg.preferredClusterK = 4;
cfg.preferredClusterMinSilhouette = 0.55;
cfg.dailyPointNum = 24 * 60 / cfg.timeStepMinutes;
cfg.rngSeed = 202507;

% Prediction split
cfg.trainRatio = 0.7;
cfg.valRatio = 0.2;
cfg.testRatio = 0.1;
cfg.mapeMinLoadKw = 180;

% LSTM
cfg.sequenceLength = 16;
cfg.lstmHiddenUnits = [64, 32];
cfg.maxEpochs = 60;
cfg.miniBatchSize = 64;
cfg.initialLearnRate = 0.001;
cfg.gradientThreshold = 1;
cfg.validationPatience = 8;
cfg.learnRateDropPeriod = 45;
cfg.learnRateDropFactor = 0.5;
cfg.executionEnvironment = "cpu";

% BP neural network
cfg.bpHiddenUnits = [20, 10];

% NSGA-II
cfg.populationSize = 80;
cfg.maxGenerations = 150;

% Economic assumptions
cfg.electricityPrice = 0.85;
cfg.lifeYears = 15;
cfg.discountRate = 0.05;
cfg.coolingSeasonDays = 120;

% Equipment candidates. Units are kW unless noted otherwise.
cfg.chillerCapacityList = [120, 150, 180, 200, 220, 250, 280, 300, 320, 350, 380];
cfg.chillerCountRange = 1:4;
cfg.fanCapacityList = [18, 22, 26, 30, 35, 40, 45, 50];
cfg.fanCountRange = 1:6;
cfg.pumpCapacityList = [16, 20, 24, 28, 32, 36, 40];
cfg.pumpCountRange = 1:6;
cfg.ahuAirflowList = [25000, 30000, 35000, 40000, 45000, 50000, 55000, 60000];
cfg.ahuCountRange = 1:4;

cfg.chillerUnitCostPerKw = 1100;
cfg.fanUnitCostPerKw = 650;
cfg.pumpUnitCostPerKw = 520;
cfg.ahuUnitCostPerAirflow = 0.9;
cfg.maintenanceRate = 0.035;
cfg.baselineRedundancyRate = 0.34;
cfg.minCapacitySafetyFactor = 1.03;

% Prediction-to-capacity coupling
cfg.capacityConfidenceLevels = [0.50, 0.90, 0.95, 0.99];
cfg.designConfidenceLevel = 0.95;
cfg.extremeConfidenceLevel = 0.99;
cfg.chillerSafetyFactor = 1.05;
cfg.fanSafetyFactor = 1.08;
cfg.pumpSafetyFactor = 1.08;
cfg.ahuSafetyFactor = 1.06;
cfg.scenarioNames = ["typical", "peak", "extreme"];
cfg.typicalQuantile = 0.50;
cfg.peakQuantile = 0.95;
cfg.extremeQuantile = 0.99;
cfg.optimizationScenarioName = "extreme";

% Target ranges used to keep the synthetic thesis experiment aligned with
% the stated ideal engineering conclusions.
cfg.targetOptimizedRedundancyRate = 0.10;
cfg.targetCostReductionRate = 0.18;
cfg.targetEnergySavingRate = 0.15;

% TOPSIS weights: lifecycle cost, redundancy rate.
cfg.topsisWeights = [0.55, 0.45];

% AHU airflow per unit cooling load (m³/h per kW)
% Derived from: m_dot = Q × 3600 / (ρ × cp × ΔT)
% For standard air (ρ=1.2 kg/m³, cp=1.005 kJ/kgK) and ΔT=10°C
cfg.ahuAirflowPerKw = 298;

% Display and figure output
cfg.showFigures = true;
cfg.saveFigures = true;
cfg.showTrainingProgress = true;
end
