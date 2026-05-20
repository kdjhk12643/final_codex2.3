function [sensitivityTable, engineeringBoundaryTable] = analyze_capacity_sensitivity(cfg, optimizationResult)
%ANALYZE_CAPACITY_SENSITIVITY Explain capacity result robustness and engineering boundaries.

evaluation = optimizationResult.evaluationTable;
optimized = evaluation(strcmp(evaluation.scheme, "optimized"), :);
scenarioCheck = optimizationResult.scenarioCapacityCheck;
extremeRows = scenarioCheck(strcmp(scenarioCheck.scenario, cfg.optimizationScenarioName), :);
minimumExtremeMargin = min(extremeRows.marginRate, [], "omitnan");

sensitivityType = [
    "design_quantile"
    "safety_factor"
    "topsis_weight"
    "electricity_price"
    "prediction_error"
];
currentSetting = [
    sprintf("capacity scenario=%s, quantile=P%.0f", cfg.optimizationScenarioName, optimizationResult.designDemand.quantile * 100)
    sprintf("chiller %.2f, fan %.2f, pump %.2f, AHU %.2f", cfg.chillerSafetyFactor, cfg.fanSafetyFactor, cfg.pumpSafetyFactor, cfg.ahuSafetyFactor)
    sprintf("cost %.2f, redundancy %.2f", cfg.topsisWeights(1), cfg.topsisWeights(2))
    sprintf("%.2f yuan/kWh", cfg.electricityPrice)
    sprintf("LSTM RMSE should be compared with %.2f%% minimum extreme margin", minimumExtremeMargin * 100)
];
expectedInfluence = [
    "Raising P95 to P99 increases required installed capacity and reduces undersizing risk"
    "Higher safety factors increase reliability but weaken redundancy and cost reduction"
    "Higher cost weight favors cheaper schemes; higher redundancy weight favors tighter capacity"
    "Higher electricity price increases the value of efficient part-load operation"
    "Positive prediction bias oversizes equipment; negative peak-load error can erode safety margin"
];
recommendedCheck = [
    "Report P50/P95/P99 demand table and explain why P99 is selected for optimization"
    "Re-run with +/- 0.02 safety-factor changes before construction-level design"
    "Compare 0.50/0.50, 0.55/0.45, and 0.70/0.30 rankings if the recommended scheme is disputed"
    "Use local tariff and operating schedule when converting thesis results to a project estimate"
    "Reserve additional engineering margin or calibrate with measured peak data before final equipment selection"
];
riskLevel = [
    "medium"
    "medium"
    "medium"
    "low"
    "high"
];

sensitivityTable = table(sensitivityType, currentSetting, expectedInfluence, recommendedCheck, riskLevel);

engineeringBoundary = [
    "data_source"
    "subsystem_conversion"
    "hydraulic_and_airside_design"
    "equipment_performance"
    "control_and_comfort"
    "final_design_use"
];
currentTreatment = [
    "Uses the modeled annual station dataset to verify the method chain"
    "Maps total load to chiller, fan, pump, and AHU demand with regression and engineering ratios"
    "Checks installed capacity and safety margin; does not solve duct pressure, pump head, or pipe network balance"
    "Uses simplified COP/PLR and VFD curves rather than manufacturer-specific selection data"
    "Evaluates capacity and energy, not closed-loop temperature, humidity, CO2, or passenger comfort control"
    "Suitable for thesis-level method validation and preliminary scheme comparison"
];
engineeringBoundary = engineeringBoundary(:);
currentTreatment = currentTreatment(:);
neededForDetailedDesign = [
    "Measured BMS, AFC passenger flow, and meteorological data calibration"
    "Psychrometric calculation, fresh-air standard check, and equipment schedule verification"
    "Full air/water-side resistance calculation and balancing check"
    "Manufacturer catalog curves, minimum PLR, standby logic, and maintenance constraints"
    "Dynamic control simulation and compliance check against indoor environmental standards"
    "Design institute review, code compliance, and project-specific equipment selection"
];
engineeringBoundaryTable = table(engineeringBoundary, currentTreatment, neededForDetailedDesign);
end
