
import pandas as pd

# 读取数据
data = pd.read_csv('data/fuzhou_metro_dongjiekou_2025.csv')

# 分项负荷列名
component_names = ['people_load_kw', 'fresh_air_load_kw', 'envelope_load_kw', 'equipment_load_kw']
component_names_cn = ['人员负荷', '新风负荷', '围护结构负荷', '设备负荷']

# 计算各分项均值
component_means = data[component_names].mean()

# 计算总负荷均值
total_mean = data['total_cooling_load_kw'].mean()

# 计算分项之和
sum_components = component_means.sum()

# 方式1：以分项之和为分母（正确）
ratio_by_sum = (component_means / sum_components * 100).tolist()

# 方式2：以总负荷为分母（当前错误方式）
ratio_by_total = (component_means / total_mean * 100).tolist()

print('=== 分项负荷均值 ===')
for name, mean in zip(component_names_cn, component_means):
    print(f'{name}: {mean:.2f} kW')
print(f'分项之和: {sum_components:.2f} kW')
print(f'总冷负荷均值: {total_mean:.2f} kW')
print(f'差值: {total_mean - sum_components:.2f} kW ({(total_mean - sum_components)/total_mean*100:.2f}%)\n')

print('=== 占比计算（方式1：以分项之和为分母）===')
for name, ratio in zip(component_names_cn, ratio_by_sum):
    print(f'{name}: {ratio:.2f}%')
print(f'合计: {sum(ratio_by_sum):.2f}%\n')

print('=== 占比计算（方式2：以总负荷为分母，当前方式）===')
for name, ratio in zip(component_names_cn, ratio_by_total):
    print(f'{name}: {ratio:.2f}%')
print(f'合计: {sum(ratio_by_total):.2f}%')
