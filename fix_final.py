import os
import re

file = 'MultiBotPro_Coordinator.mqh'
try:
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()
except:
    with open(file, 'r', encoding='utf-16') as f:
        content = f.read()

content = content.replace('m_systemState.SetMasterUiPriorityUntilMs(GetTickCount() + 250);', 'G_MasterUiPriorityUntilMs = GetTickCount() + 250;')
content = content.replace('!IsNonTradingHour()', 'IsTradingTime()')

with open(file, 'w', encoding='utf-8') as f:
    f.write(content)
print("Replaced errors in MultiBotPro_Coordinator.mqh")

