function [annualEnergy, breakdown] = hvac_estimate_annual_energy_detailed(cfg, scheme, loadProfileKw, demand)
%HVAC_ESTIMATE_ANNUAL_ENERGY_DETAILED Estimate HVAC annual energy with COP/PLR and VFD curves.

loadProfileKw = loadProfileKw(:);
loadProfileKw = loadProfileKw(isfinite(loadProfileKw) & loadProfileKw >= 0);
if isempty(loadProfileKw)
    loadProfileKw = demand.totalCoolingLoadKw;
end

timeStepHours = getFieldOrDefault(cfg, "timeStepMinutes", 15) / 60;
coolingSeasonDays = getFieldOrDefault(cfg, "coolingSeasonDays", 120);
profileDays = max(numel(loadProfileKw) * timeStepHours / 24, eps);
annualScale = coolingSeasonDays / profileDays;

unitCapacity = max(scheme.chillerCapacityKw, eps);
chillerCount = max(scheme.chillerCount, 1);
maxCapacity = max(scheme.totalCoolingCapacityKw, unitCapacity * chillerCount);
ratedCop = getFieldOrDefault(cfg, "chillerRatedCOP", 5.2);
minPlr = getFieldOrDefault(cfg, "chillerMinPLR", 0.25);
plrCurve = getFieldOrDefault(cfg, "chillerPLRCurve", [0.25, 0.50, 0.75, 1.00; 0.78, 0.92, 1.00, 0.96]);
vfdExponent = getFieldOrDefault(cfg, "vfdExponent", 2.6);

activeChillers = ceil(loadProfileKw ./ unitCapacity);
activeChillers = min(max(activeChillers, 1), chillerCount);
availableCapacity = activeChillers .* unitCapacity;
plr = loadProfileKw ./ max(availableCapacity, eps);
plrForCop = min(max(plr, minPlr), 1);
copRatio = interp1(plrCurve(1, :), plrCurve(2, :), plrForCop, "linear", "extrap");
copRatio = max(copRatio, 0.10);
cop = ratedCop .* copRatio;
chillerPowerKw = loadProfileKw ./ max(cop, eps);

loadFraction = min(loadProfileKw ./ max(demand.totalCoolingLoadKw, eps), 1);
fanPowerKw = scheme.totalFanCapacityKw .* (loadFraction .^ vfdExponent);
pumpPowerKw = scheme.totalPumpCapacityKw .* (loadFraction .^ vfdExponent);

chillerKwh = sum(chillerPowerKw) * timeStepHours * annualScale;
fanKwh = sum(fanPowerKw) * timeStepHours * annualScale;
pumpKwh = sum(pumpPowerKw) * timeStepHours * annualScale;
annualEnergy = chillerKwh + fanKwh + pumpKwh;

breakdown = struct( ...
    "chillerKwh", chillerKwh, ...
    "fanKwh", fanKwh, ...
    "pumpKwh", pumpKwh, ...
    "totalKwh", annualEnergy, ...
    "meanChillerPLR", mean(plr, "omitnan"), ...
    "meanCOP", mean(cop, "omitnan"), ...
    "annualScale", annualScale);
end

function value = getFieldOrDefault(cfg, fieldName, defaultValue)
if isstruct(cfg) && isfield(cfg, fieldName)
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end
