import pandas as pd
from openpyxl import Workbook
from openpyxl.chart import LineChart, Reference
from openpyxl.utils.dataframe import dataframe_to_rows

# 加载Excel文件到DataFrame
df = pd.read_excel('result_Cycle1.xlsx')

# 创建一个新的Excel工作簿
wb = Workbook()
ws = wb.active

# 将DataFrame写入Excel工作表中
for r in dataframe_to_rows(df, index=False, header=True):
    ws.append(r)

data_columns = [col for col in df.columns if col != 'SN']

# 创建折线图
chart = LineChart()

# 选择所有数据作为绘图的数据范围
data = Reference(ws, min_col=2, min_row=1, max_col=df.shape[1], max_row=df.shape[0])
cats = Reference(ws, min_col=1, min_row=2, max_row=df.shape[0])
chart.add_data(data, titles_from_data=True)
chart.set_categories(cats)

# 设置图表标题
chart.title = "Your Chart Title Here"

# 设置图表样式，只显示坐标轴，不显示网格线
chart.y_axis.majorGridlines = None
chart.x_axis.majorGridlines = None

# 添加图表到Excel工作表
ws.add_chart(chart, "D2")

# 保存Excel文件
wb.save('data_with_chart.xlsx')
