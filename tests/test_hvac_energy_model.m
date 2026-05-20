function tests = test_hvac_energy_model
tests = functiontests(localfunctions);
end

function testDetailedEnergyUsesCopPlrAndVfdCurves(testCase)
cfg = struct();
cfg.chillerRatedCOP = 5.2;
cfg.chillerMinPLR = 0.25;
cfg.chillerPLRCurve = [0.25, 0.50, 0.75, 1.00; 0.78, 0.92, 1.00, 0.96];
cfg.vfdExponent = 2.6;
cfg.timeStepMinutes = 15;
cfg.coolingSeasonDays = 120;

demand = struct();
demand.totalCoolingLoadKw = 200;

matched = struct( ...
    "chillerCapacityKw", 120, ...
    "chillerCount", 2, ...
    "totalCoolingCapacityKw", 240, ...
    "totalFanCapacityKw", 24, ...
    "totalPumpCapacityKw", 20);

oversized = matched;
oversized.chillerCapacityKw = 240;
oversized.chillerCount = 2;
oversized.totalCoolingCapacityKw = 480;
oversized.totalFanCapacityKw = 48;
oversized.totalPumpCapacityKw = 40;

loadProfile = [80; 120; 160; 200];

[matchedEnergy, matchedBreakdown] = hvac_estimate_annual_energy_detailed(cfg, matched, loadProfile, demand);
[oversizedEnergy, oversizedBreakdown] = hvac_estimate_annual_energy_detailed(cfg, oversized, loadProfile, demand);

verifyGreaterThan(testCase, oversizedEnergy, matchedEnergy);
verifyGreaterThan(testCase, matchedBreakdown.chillerKwh, 0);
verifyGreaterThan(testCase, matchedBreakdown.fanKwh, 0);
verifyGreaterThan(testCase, matchedBreakdown.pumpKwh, 0);
verifyEqual(testCase, matchedBreakdown.totalKwh, matchedEnergy, "AbsTol", 1e-9);
end
