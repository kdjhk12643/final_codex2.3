function [dataRaw, dataClean, featureData] = step1_data_prepare(cfg)
%STEP1_DATA_PREPARE Read, clean, and standardize modeling data.
% Outputs:
%   dataRaw     - original CSV table after timestamp parsing.
%   dataClean   - sorted and gap-filled table with added time/lag features.
%   featureData - standardized modeling matrix plus the unscaled target.

stepTimer = tic;
fprintf("  Step 1.1 Reading CSV data...\n");
if ~isfile(cfg.dataFile)
    error("Data file not found: %s", cfg.dataFile);
end

% TextType="string" keeps text columns consistent when written back to CSV.
dataRaw = readtable(cfg.dataFile, "TextType", "string");
fprintf("  Loaded %d rows and %d columns.\n", height(dataRaw), width(dataRaw));

% Convert the timestamp column only when readtable did not already infer it.
if ~isdatetime(dataRaw.(cfg.timestampName))
    dataRaw.(cfg.timestampName) = datetime(dataRaw.(cfg.timestampName), ...
        "InputFormat", "yyyy-MM-dd HH:mm:ss");
end

fprintf("  Step 1.2 Sorting timestamps and filling missing numeric values...\n");
% All downstream modeling assumes chronological order.
dataRaw = sortrows(dataRaw, cfg.timestampName);
missingBefore = sum(sum(ismissing(dataRaw)));
dataClean = fillMissingValues(dataRaw, cfg);
missingAfter = sum(sum(ismissing(dataClean)));

fprintf("  Missing values before/after cleaning: %d / %d.\n", missingBefore, missingAfter);
fprintf("  Step 1.3 Adding time features and standardizing predictors...\n");
% Time features describe periodic daily/weekly patterns, and lag features
% provide recent cooling-load history for the prediction models.
dataClean = addTimeFeatures(dataClean, cfg);
dataClean = addLoadLagFeatures(dataClean, cfg);
featureData = buildStandardizedFeatureTable(dataClean, cfg);

% Persist intermediate tables so each stage can be inspected independently in
% the thesis workflow.
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
%PLOTSTEP1FIGURES Export the basic data-quality and load-profile figures.
if ~(cfg.showFigures || cfg.saveFigures)
    return;
end

% Figure 1: cleaned target series used by all later stages.
ts = dataClean.(cfg.timestampName);

fig1 = figure("Name", "Step 1 - Cooling Load Time Series", "Visible", figureVisibility(cfg));
plot(ts, dataClean.(cfg.targetName), "LineWidth", 1.1);
xlabel("Time");
ylabel("Cooling load / kW");
title("Station Platform Cooling Load");
grid on;
saveFigureIfNeeded(cfg, fig1, "step1_cooling_load_timeseries.png");

% Figure 2: missing-value counts before filling, useful for documenting data
% quality and preprocessing necessity.
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
%FIGUREVISIBILITY Convert the showFigures flag to MATLAB's figure Visible value.
if cfg.showFigures
    visible = "on";
else
    visible = "off";
end
end

function saveFigureIfNeeded(cfg, fig, fileName)
%SAVEFIGUREIFNEEDED Write PNG figures only when cfg.saveFigures is enabled.
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
%ENSUREFIGUREDIR Create the figure output folder for direct step execution.
if ~exist(cfg.figureDir, "dir")
    mkdir(cfg.figureDir);
end
end

function dataClean = fillMissingValues(dataRaw, cfg)
%FILLMISSINGVALUES Fill numeric gaps without changing nonnumeric metadata.
dataClean = dataRaw;

numericVars = dataClean.Properties.VariableNames(varfun(@isnumeric, dataClean, "OutputFormat", "uniform"));
for i = 1:numel(numericVars)
    varName = numericVars{i};
    % First use the configured interpolation method, then nearest-neighbor
    % filling for leading/trailing NaN values that interpolation cannot fill.
    dataClean.(varName) = fillmissing(dataClean.(varName), cfg.missingMethod);
    dataClean.(varName) = fillmissing(dataClean.(varName), "nearest");
end
end

function dataOut = addTimeFeatures(dataIn, cfg)
%ADDTIMEFEATURES Encode calendar effects for load prediction.
dataOut = dataIn;
ts = dataOut.(cfg.timestampName);

% Sine/cosine features preserve cyclic distance, e.g. 23:45 is close to 00:00.
dataOut.hour_decimal = hour(ts) + minute(ts) / 60;
dataOut.day_of_week = weekday(ts);
dataOut.is_weekend_numeric = double(dataOut.day_of_week == 1 | dataOut.day_of_week == 7);
dataOut.hour_sin = sin(2 * pi * dataOut.hour_decimal / 24);
dataOut.hour_cos = cos(2 * pi * dataOut.hour_decimal / 24);
dataOut.day_sin = sin(2 * pi * dataOut.day_of_week / 7);
dataOut.day_cos = cos(2 * pi * dataOut.day_of_week / 7);
end

function dataOut = addLoadLagFeatures(dataIn, cfg)
%ADDLOADLAGFEATURES Add historical target values as supervised predictors.
dataOut = dataIn;
target = dataOut.(cfg.targetName);

for i = 1:numel(cfg.loadLagSteps)
    lagStep = cfg.loadLagSteps(i);
    lagName = "load_lag_" + string(lagStep);
    % Shift the target down by lagStep rows. The leading gap is filled with the
    % nearest available value so the modeling table keeps the original length.
    lagValues = [nan(lagStep, 1); target(1:end - lagStep)];
    lagValues = fillmissing(lagValues, "nearest");
    dataOut.(lagName) = lagValues;
end
end

function featureData = buildStandardizedFeatureTable(dataClean, cfg)
%BUILDSTANDARDIZEDFEATURETABLE Assemble the model-ready feature matrix.
featureData = dataClean(:, cfg.timestampName);

% Candidate names include configured measured predictors, generated lag
% features, and generated time features. Missing columns are ignored so the
% workflow is tolerant to small data-schema changes.
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
            % A constant feature contains no modeling information after zscore.
            featureData.(name) = zeros(height(dataClean), 1);
        else
            featureData.(name) = (values - mean(values, "omitnan")) ./ sigma;
        end
    else
        featureData.(name) = values;
    end
end

% Keep the target in physical units (kW) so model errors and design loads are
% directly interpretable.
featureData.(cfg.targetName) = dataClean.(cfg.targetName);
end
