function [dataRaw, dataClean, featureData] = step1_data_prepare(cfg)
%STEP1_DATA_PREPARE Read, clean, and standardize modeling data.

stepTimer = tic;
fprintf("  Step 1.1 Reading CSV data...\n");
if ~isfile(cfg.dataFile)
    error("Data file not found: %s", cfg.dataFile);
end

dataRaw = readtable(cfg.dataFile, "TextType", "string");
fprintf("  Loaded %d rows and %d columns.\n", height(dataRaw), width(dataRaw));

if ~isdatetime(dataRaw.(cfg.timestampName))
    dataRaw.(cfg.timestampName) = datetime(dataRaw.(cfg.timestampName), ...
        "InputFormat", "yyyy-MM-dd HH:mm:ss");
end

fprintf("  Step 1.2 Sorting timestamps and filling missing numeric values...\n");
dataRaw = sortrows(dataRaw, cfg.timestampName);
missingBefore = sum(sum(ismissing(dataRaw)));
dataClean = fillMissingValues(dataRaw, cfg);
missingAfter = sum(sum(ismissing(dataClean)));

fprintf("  Missing values before/after cleaning: %d / %d.\n", missingBefore, missingAfter);
fprintf("  Step 1.3 Adding time features and standardizing predictors...\n");
dataClean = addTimeFeatures(dataClean, cfg);
dataClean = addLoadLagFeatures(dataClean, cfg);
featureData = buildStandardizedFeatureTable(dataClean, cfg);

cleanFile = fullfile(cfg.tableDir, "step1_clean_data.csv");
modelingFile = fullfile(cfg.tableDir, "step1_modeling_data.csv");
writetable(dataClean, cleanFile);
writetable(featureData, modelingFile);

plotStep1Figures(cfg, dataRaw, dataClean);

fprintf("  Modeling table: %d rows, %d columns.\n", height(featureData), width(featureData));
fprintf("  Saved: %s\n", cleanFile);
fprintf("  Saved: %s\n", modelingFile);
fprintf("  Step 1 finished in %.1f seconds.\n", toc(stepTimer));
end

function plotStep1Figures(cfg, dataRaw, dataClean)
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

ts = dataClean.(cfg.timestampName);

fig1 = figure("Name", "Step 1 - Cooling Load Time Series", "Visible", figureVisibility(cfg));
plot(ts, dataClean.(cfg.targetName), "LineWidth", 1.1);
xlabel("Time");
ylabel("Cooling load / kW");
title("Station Platform Cooling Load");
grid on;
saveFigureIfNeeded(cfg, fig1, "step1_cooling_load_timeseries.png");

missingCounts = sum(ismissing(dataRaw));
missingCounts = missingCounts(:);
names = string(dataRaw.Properties.VariableNames)';
idx = missingCounts > 0;
fig2 = figure("Name", "Step 1 - Missing Value Summary", "Visible", figureVisibility(cfg));
if any(idx)
    bar(categorical(names(idx)), missingCounts(idx));
    ylabel("Missing count");
    title("Missing Values Before Preprocessing");
    xtickangle(35);
else
    text(0.5, 0.5, "No missing values", "HorizontalAlignment", "center");
    axis off;
end
grid on;
saveFigureIfNeeded(cfg, fig2, "step1_missing_value_summary.png");
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

function dataClean = fillMissingValues(dataRaw, cfg)
dataClean = dataRaw;

numericVars = dataClean.Properties.VariableNames(varfun(@isnumeric, dataClean, "OutputFormat", "uniform"));
for i = 1:numel(numericVars)
    varName = numericVars{i};
    dataClean.(varName) = fillmissing(dataClean.(varName), cfg.missingMethod);
    dataClean.(varName) = fillmissing(dataClean.(varName), "nearest");
end
end

function dataOut = addTimeFeatures(dataIn, cfg)
dataOut = dataIn;
ts = dataOut.(cfg.timestampName);

dataOut.hour_decimal = hour(ts) + minute(ts) / 60;
dataOut.day_of_week = weekday(ts);
dataOut.is_weekend_numeric = double(dataOut.day_of_week == 1 | dataOut.day_of_week == 7);
dataOut.hour_sin = sin(2 * pi * dataOut.hour_decimal / 24);
dataOut.hour_cos = cos(2 * pi * dataOut.hour_decimal / 24);
dataOut.day_sin = sin(2 * pi * dataOut.day_of_week / 7);
dataOut.day_cos = cos(2 * pi * dataOut.day_of_week / 7);
end

function dataOut = addLoadLagFeatures(dataIn, cfg)
dataOut = dataIn;
target = dataOut.(cfg.targetName);

for i = 1:numel(cfg.loadLagSteps)
    lagStep = cfg.loadLagSteps(i);
    lagName = "load_lag_" + string(lagStep);
    lagValues = [nan(lagStep, 1); target(1:end - lagStep)];
    lagValues = fillmissing(lagValues, "nearest");
    dataOut.(lagName) = lagValues;
end
end

function featureData = buildStandardizedFeatureTable(dataClean, cfg)
featureData = dataClean(:, cfg.timestampName);

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
            featureData.(name) = zeros(height(dataClean), 1);
        else
            featureData.(name) = (values - mean(values, "omitnan")) ./ sigma;
        end
    else
        featureData.(name) = values;
    end
end

featureData.(cfg.targetName) = dataClean.(cfg.targetName);
end
