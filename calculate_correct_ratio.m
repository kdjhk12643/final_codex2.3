
% 计算正确的负荷分项占比
clear; clc;

% 读取数据
data = readtable('data/fuzhou_metro_dongjiekou_2025.csv');

% 分项负荷列名
componentNames = {'people_load_kw', 'fresh_air_load_kw', 'envelope_load_kw', 'equipment_load_kw'};
componentNamesCN = {'人员负荷', '新风负荷', '围护结构负荷', '设备负荷'};

% 计算各分项均值
componentMeans = zeros(4, 1);
for i = 1:4
    componentMeans(i) = mean(data.(componentNames{i}), 'omitnan');
end

% 计算总负荷均值
totalMean = mean(data.total_cooling_load_kw, 'omitnan');

% 计算分项之和
sumComponents = sum(componentMeans);

% 方式1：以分项之和为分母（正确）
ratioBySum = componentMeans / sumComponents * 100;

% 方式2：以总负荷为分母（当前错误方式）
ratioByTotal = componentMeans / totalMean * 100;

fprintf('=== 分项负荷均值 ===\n');
for i = 1:4
    fprintf('%s: %.2f kW\n', componentNamesCN{i}, componentMeans(i));
end
fprintf('分项之和: %.2f kW\n', sumComponents);
fprintf('总冷负荷均值: %.2f kW\n', totalMean);
fprintf('差值: %.2f kW (%.2f%%)\n\n', totalMean - sumComponents, (totalMean - sumComponents)/totalMean*100);

fprintf('=== 占比计算（方式1：以分项之和为分母）===\n');
for i = 1:4
    fprintf('%s: %.2f%%\n', componentNamesCN{i}, ratioBySum(i));
end
fprintf('合计: %.2f%%\n\n', sum(ratioBySum));

fprintf('=== 占比计算（方式2：以总负荷为分母，当前方式）===\n');
for i = 1:4
    fprintf('%s: %.2f%%\n', componentNamesCN{i}, ratioByTotal(i));
end
fprintf('合计: %.2f%%\n', sum(ratioByTotal));
