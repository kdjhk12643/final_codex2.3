function cfg = config()
%CONFIG 地铁车站环控系统论文流程的集中参数配置。
% 本函数返回一个结构体，供 main.m 和所有 step*.m 文件共同使用。
% 可调假设集中放在这里，便于通过改参数重复实验，而不用改流程代码。

% 项目名称和原始数据位置。
cfg.projectName = "MetroStationHVACCapacityOptimization";
cfg.dataFile = fullfile("data", "fuzhou_metro_dongjiekou_2025.csv");

% 输出文件夹由 main.m 在流程开始前创建。
cfg.outputDir = "output";
cfg.figureDir = fullfile(cfg.outputDir, "figures");
cfg.tableDir = fullfile(cfg.outputDir, "tables");
cfg.modelDir = fullfile(cfg.outputDir, "models");

% 数据预处理参数。
% timestampName 和 targetName 定义预处理、分析、预测和优化共用的时间轴与预测目标。
cfg.timestampName = "timestamp";
cfg.targetName = "total_cooling_load_kw";
% 数据采样间隔为 15 分钟，用于确定日曲线长度、年能耗折算和滞后特征含义。
cfg.timeStepMinutes = 15;
% 数值缺失值先线性插值，首尾无法插值的位置再用最近值补齐。
cfg.missingMethod = "linear";
% zscore 标准化使不同量纲的特征可用于相关性排序和神经网络训练。
cfg.standardizeMethod = "zscore";
% 负荷滞后项提供短期和前一日历史负荷信息；15 分钟数据中 96 步代表前一天同一时刻。
cfg.loadLagSteps = [1, 4, 8, 96];

% 用于构建标准化特征表的连续型预测因子。
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

% 仅用于工程解释的参考列，不作为主标准化特征表中的通用预测因子。
cfg.referenceOnlyNames = [ ...
    "chiller_load_kw", ...
    "fan_power_kw", ...
    "pump_power_kw", ...
    "people_load_kw", ...
    "fresh_air_load_kw", ...
    "envelope_load_kw", ...
    "equipment_load_kw" ...
];

% 用于解释总冷负荷组成的分项负荷列。
cfg.loadComponentNames = [ ...
    "people_load_kw", ...
    "fresh_air_load_kw", ...
    "envelope_load_kw", ...
    "equipment_load_kw" ...
];

% Pearson 相关性分析与聚类参数。
% topFeatureNum 控制进入预测阶段的高相关特征数量。
cfg.topFeatureNum = 10;
% 典型日 K-Means 聚类候选 K 值。
cfg.clusterKRange = 2:4;
% preferredClusterK 和 preferredClusterMinSilhouette 作为实验参考保留；当前实现仍按平均轮廓系数最高选择 K。
cfg.preferredClusterK = 4;
cfg.preferredClusterMinSilhouette = 0.55;
% 一个完整日内包含的 15 分钟采样点数量。
cfg.dailyPointNum = 24 * 60 / cfg.timeStepMinutes;
% false 表示按绝对负荷水平聚类；true 表示按归一化曲线形态聚类。
cfg.normalizeDailyClusterCurves = false;
% 固定随机种子，保证 K-Means 等随机过程可复现。
cfg.rngSeed = 202507;

% 预测数据集划分。
% 按时间顺序划分：前段训练，中段验证，末段测试。
cfg.trainRatio = 0.7;
cfg.valRatio = 0.2;
cfg.testRatio = 0.1;
% 防止真实负荷很小时 MAPE 分母过小导致百分比异常放大。
cfg.mapeMinLoadKw = 180;

% LSTM
% sequenceLength 表示每个 LSTM 样本输入的历史时间步数；15 分钟数据下 16 步覆盖 4 小时。
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

% BP 神经网络参数。
% BP 作为比 LSTM 更简单的对比预测模型。
cfg.bpHiddenUnits = [20, 10];

% NSGA-II
% 这些参数用于 Global Optimization Toolbox 路径；若 gamultiobj 不可用，step4 会回退到离散网格搜索。
cfg.populationSize = 80;
cfg.maxGenerations = 150;

% 经济性假设。
% 用于将设备投资和年耗电量折算为优化目标中的全生命周期成本。
cfg.electricityPrice = 0.85;
cfg.lifeYears = 15;
cfg.discountRate = 0.05;
cfg.coolingSeasonDays = 120;

% 工程能耗模型假设。
% 用于论文层面的方案比较；若进入详细设计，应替换为设备厂商性能曲线。
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

% 设备候选规格。除特别说明外，单位均为 kW。
% 优化变量是候选规格列表索引和台数；AHU 风量单位为 m3/h，不是 kW。
cfg.chillerCapacityList = [100, 120, 140, 150, 160, 180, 200, 220, 240, 250, 280, 300, 320, 350, 380];
cfg.chillerCountRange = 1:4;
cfg.fanCapacityList = [16, 18, 20, 22, 24, 26, 28, 30, 32, 35, 40, 45, 50];
cfg.fanCountRange = 1:6;
cfg.pumpCapacityList = [14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40];
cfg.pumpCountRange = 1:6;
cfg.ahuAirflowList = [25000, 30000, 35000, 40000, 43000, 45000, 48000, 50000, 55000, 60000, 70000];
cfg.ahuCountRange = 1:4;

% 单位造价为论文层面的粗略假设，用于方案间相对比较。
cfg.chillerUnitCostPerKw = 1100;
cfg.fanUnitCostPerKw = 650;
cfg.pumpUnitCostPerKw = 520;
cfg.ahuUnitCostPerAirflow = 0.9;
cfg.maintenanceRate = 0.035;
cfg.baselineRedundancyRate = 0.28;
cfg.minCapacitySafetyFactor = 1.03;

% 预测结果到容量配置的耦合参数。
% 通过负荷分位数将预测负荷曲线转换为典型、峰值和极端容量设计情景。
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

% TOPSIS 权重：全生命周期成本、冗余率。
% 两个优化目标均为越小越好；该权重表示 Pareto 解集生成后的最终决策偏好。
cfg.topsisWeights = [0.55, 0.45];

% 单位冷负荷对应 AHU 风量（m³/h per kW）。
% 由公式 m_dot = Q × 3600 / (ρ × cp × ΔT) 推得。
% 标准空气取 ρ=1.2 kg/m³、cp=1.005 kJ/kgK，送回风温差 ΔT=10°C。
cfg.ahuAirflowPerKw = 298;

% 显示与图片输出参数。
% showFigures 控制是否打开交互图窗，saveFigures 控制是否导出 PNG，showTrainingProgress 控制是否显示训练过程窗口。
cfg.showFigures = true;
cfg.saveFigures = true;
cfg.showTrainingProgress = true;
end
