function [dataRaw, dataClean, featureData] = step1_data_prepare(cfg)
%STEP1_DATA_PREPARE 读取、清洗并标准化建模数据。
% 输出：
%   dataRaw     - 完成时间戳解析后的原始 CSV 数据表。
%   dataClean   - 排序、补缺并加入时间/滞后特征后的数据表。
%   featureData - 标准化建模特征矩阵，目标列仍保留原始物理量纲。

stepTimer = tic;
fprintf("  步骤 1.1 读取 CSV 数据...\n");
if ~isfile(cfg.dataFile)
    error("未找到数据文件：%s", cfg.dataFile);
end

% TextType="string" 可保证文本列写回 CSV 时类型一致。
dataRaw = readtable(cfg.dataFile, "TextType", "string");
fprintf("  已读取 %d 行、%d 列。\n", height(dataRaw), width(dataRaw));

% 仅当 readtable 未自动识别时间戳时，才手动转换时间列。
if ~isdatetime(dataRaw.(cfg.timestampName))
    dataRaw.(cfg.timestampName) = datetime(dataRaw.(cfg.timestampName), ...
        "InputFormat", "yyyy-MM-dd HH:mm:ss");
end

fprintf("  步骤 1.2 按时间排序并填补数值缺失...\n");
% 后续建模均假设数据按时间顺序排列。
dataRaw = sortrows(dataRaw, cfg.timestampName);
missingBefore = sum(sum(ismissing(dataRaw)));
dataClean = fillMissingValues(dataRaw, cfg);
missingAfter = sum(sum(ismissing(dataClean)));

fprintf("  清洗前/清洗后缺失值数量：%d / %d。\n", missingBefore, missingAfter);
fprintf("  步骤 1.3 添加时间特征并标准化预测因子...\n");
% 时间特征描述日/周周期规律，滞后特征为预测模型提供近期冷负荷历史信息。
dataClean = addTimeFeatures(dataClean, cfg);
dataClean = addLoadLagFeatures(dataClean, cfg);
featureData = buildStandardizedFeatureTable(dataClean, cfg);

% 保存中间表，便于论文流程中独立检查每个处理阶段。
cleanFile = fullfile(cfg.tableDir, "step1_clean_data.csv");
modelingFile = fullfile(cfg.tableDir, "step1_modeling_data.csv");
writetable(localizeStep1TableForOutput(dataClean), cleanFile);
writetable(localizeStep1TableForOutput(featureData), modelingFile);

plotStep1Figures(cfg, dataRaw, dataClean);

fprintf("  建模表：%d 行、%d 列。\n", height(featureData), width(featureData));
fprintf("  已保存：%s\n", cleanFile);
fprintf("  已保存：%s\n", modelingFile);
fprintf("  步骤 1 完成，用时 %.1f 秒。\n", toc(stepTimer));
end

function plotStep1Figures(cfg, dataRaw, dataClean)
%PLOTSTEP1FIGURES 导出基础数据质量和负荷曲线图。
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

% 图 1：后续步骤使用的清洗后目标负荷时序。
ts = dataClean.(cfg.timestampName);

fig1 = figure("Name", "步骤1 - 冷负荷时序", "Visible", figureVisibility(cfg));
plot(ts, dataClean.(cfg.targetName), "LineWidth", 1.1);
xlabel("时间");
ylabel("冷负荷 / kW");
title("车站站台冷负荷");
grid on;
saveFigureIfNeeded(cfg, fig1, "step1_cooling_load_timeseries.png");

% 图 2：填补前缺失值数量，用于说明数据质量和预处理必要性。
missingCounts = sum(ismissing(dataRaw));
missingCounts = missingCounts(:);
names = localizeStep1VariableNames(string(dataRaw.Properties.VariableNames))';
idx = missingCounts > 0;
fig2 = figure("Name", "步骤1 - 缺失值统计", "Visible", figureVisibility(cfg));
if any(idx)
    bar(categorical(names(idx)), missingCounts(idx));
    ylabel("缺失值数量");
    title("预处理前缺失值统计");
    xtickangle(35);
else
    text(0.5, 0.5, "无缺失值", "HorizontalAlignment", "center");
    axis off;
end
grid on;
saveFigureIfNeeded(cfg, fig2, "step1_missing_value_summary.png");
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

function dataClean = fillMissingValues(dataRaw, cfg)
%FILLMISSINGVALUES 只填补数值列缺失，不改变非数值元数据。
dataClean = dataRaw;

numericVars = dataClean.Properties.VariableNames(varfun(@isnumeric, dataClean, "OutputFormat", "uniform"));
for i = 1:numel(numericVars)
    varName = numericVars{i};
    % 先采用配置的插值方法，再用最近值补齐首尾仍无法插值的 NaN。
    dataClean.(varName) = fillmissing(dataClean.(varName), cfg.missingMethod);
    dataClean.(varName) = fillmissing(dataClean.(varName), "nearest");
end
end

function dataOut = addTimeFeatures(dataIn, cfg)
%ADDTIMEFEATURES 为负荷预测编码日历时间影响。
dataOut = dataIn;
ts = dataOut.(cfg.timestampName);

% 正弦/余弦特征能保留周期距离，例如 23:45 与 00:00 在时间周期上相邻。
dataOut.hour_decimal = hour(ts) + minute(ts) / 60;
dataOut.day_of_week = weekday(ts);
dataOut.is_weekend_numeric = double(dataOut.day_of_week == 1 | dataOut.day_of_week == 7);
dataOut.hour_sin = sin(2 * pi * dataOut.hour_decimal / 24);
dataOut.hour_cos = cos(2 * pi * dataOut.hour_decimal / 24);
dataOut.day_sin = sin(2 * pi * dataOut.day_of_week / 7);
dataOut.day_cos = cos(2 * pi * dataOut.day_of_week / 7);
end

function dataOut = addLoadLagFeatures(dataIn, cfg)
%ADDLOADLAGFEATURES 将历史目标负荷加入为监督学习预测因子。
dataOut = dataIn;
target = dataOut.(cfg.targetName);

for i = 1:numel(cfg.loadLagSteps)
    lagStep = cfg.loadLagSteps(i);
    lagName = "load_lag_" + string(lagStep);
    % 将目标列下移 lagStep 行；开头缺口用最近值填补，以保持建模表长度不变。
    lagValues = [nan(lagStep, 1); target(1:end - lagStep)];
    lagValues = fillmissing(lagValues, "nearest");
    dataOut.(lagName) = lagValues;
end
end

function featureData = buildStandardizedFeatureTable(dataClean, cfg)
%BUILDSTANDARDIZEDFEATURETABLE 组装可直接建模的特征矩阵。
featureData = dataClean(:, cfg.timestampName);

% 候选特征包括配置中的实测预测因子、生成的滞后特征和时间特征；不存在的列会被跳过。
lagFeatureNames = "load_lag_" + string(cfg.loadLagSteps);
candidateNames = [ ...
    cfg.continuousFeatureNames, ...
    lagFeatureNames, ...
    "hour_decimal", "is_weekend_numeric", "hour_sin", "hour_cos", "day_sin", "day_cos" ...
];
candidateNames = candidateNames(ismember(candidateNames, string(dataClean.Properties.VariableNames)));

for i = 1:numel(candidateNames)
    name = candidateNames(i);
    values = dataClean.(name);
    if cfg.standardizeMethod == "zscore"
        sigma = std(values, "omitnan");
        if sigma == 0 || isnan(sigma)
            % 常量特征经 zscore 后没有有效建模信息，直接置零。
            featureData.(name) = zeros(height(dataClean), 1);
        else
            featureData.(name) = (values - mean(values, "omitnan")) ./ sigma;
        end
    else
        featureData.(name) = values;
    end
end

% 目标列保留物理单位 kW，使模型误差和设计负荷可直接解释。
featureData.(cfg.targetName) = dataClean.(cfg.targetName);
end

function tableOut = localizeStep1TableForOutput(tableIn)
%LOCALIZESTEP1TABLEFOROUTPUT 生成仅用于 CSV 导出的中文表头副本。
tableOut = tableIn;
tableOut.Properties.VariableNames = cellstr(localizeStep1VariableNames(string(tableIn.Properties.VariableNames)));
end

function namesOut = localizeStep1VariableNames(namesIn)
%LOCALIZESTEP1VARIABLENAMES 将数据列名转换为论文表格中的中文表头。
namesOut = strings(size(namesIn));
for i = 1:numel(namesIn)
    name = namesIn(i);
    if startsWith(name, "load_lag_")
        lagStep = extractAfter(name, "load_lag_");
        namesOut(i) = "冷负荷滞后" + lagStep + "步";
    else
        switch name
            case "timestamp"
                namesOut(i) = "时间";
            case "total_cooling_load_kw"
                namesOut(i) = "总冷负荷_kW";
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
            case "chiller_load_kw"
                namesOut(i) = "冷机负荷_kW";
            case "fan_power_kw"
                namesOut(i) = "风机功率_kW";
            case "pump_power_kw"
                namesOut(i) = "水泵功率_kW";
            case "people_load_kw"
                namesOut(i) = "人员负荷_kW";
            case "fresh_air_load_kw"
                namesOut(i) = "新风负荷_kW";
            case "envelope_load_kw"
                namesOut(i) = "围护结构负荷_kW";
            case "equipment_load_kw"
                namesOut(i) = "设备负荷_kW";
            case "hour_decimal"
                namesOut(i) = "小时_十进制";
            case "day_of_week"
                namesOut(i) = "星期";
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
