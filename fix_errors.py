import os
import glob
import re

for file in glob.glob('*.mq*'):
    if file.endswith('.bak'):
        continue
    content = ""
    enc = 'utf-8'
    try:
        with open(file, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e1:
        try:
            enc = 'utf-16'
            with open(file, 'r', encoding='utf-16') as f:
                content = f.read()
        except Exception as e2:
            print(f"Failed to read {file}: {e1} | {e2}")
            continue
            
    modified = False
    
    if '#include "MultiBotPro_GridZone.mqh"' in content:
        print(f"Found GridZone include in {file}")
        content = content.replace('#include "MultiBotPro_GridZone.mqh"', '')
        modified = True
        
    if 'm_systemState->' in content:
        content = content.replace('m_systemState->', 'm_systemState.')
        modified = True
        
    if 'const ulong HEARTBEAT_TIMEOUT_MS = 5000;' in content:
        content = content.replace('const ulong HEARTBEAT_TIMEOUT_MS = 5000;', 'static const ulong HEARTBEAT_TIMEOUT_MS = 5000;')
        modified = True
        
    if 'const int STRESS_OPERATIONS = 100;' in content:
        content = content.replace('const int STRESS_OPERATIONS = 100;', 'static const int STRESS_OPERATIONS = 100;')
        modified = True
        
    if 'StringTrim(numStr);' in content:
        content = content.replace('StringTrim(numStr);', 'StringTrimLeft(numStr);\n      StringTrimRight(numStr);')
        modified = True
        
    if file == 'MultiBotPro_RiskEngine.mqh':
        if 'int todayDayOfYear = TimeYear(TimeCurrent()) * 366 +' in content:
            replacement = '''MqlDateTime dt;\n      TimeToStruct(TimeCurrent(), dt);\n      int todayDayOfYear = dt.year * 366 + dt.day_of_year;'''
            content = re.sub(r'int todayDayOfYear = TimeYear\(TimeCurrent\(\)\) \* 366 \+\s*TimeDayOfYear\(TimeCurrent\(\)\);', replacement, content)
            modified = True

    if file == 'MultiBotPro.mq5':
        if 'G_SystemState.SetCurrentDayOfYear(TimeDayOfYear(TimeCurrent()));' in content:
            replacement = '''MqlDateTime dt;\n   TimeToStruct(TimeCurrent(), dt);\n   G_SystemState.SetCurrentDayOfYear(dt.day_of_year);'''
            content = content.replace('G_SystemState.SetCurrentDayOfYear(TimeDayOfYear(TimeCurrent()));', replacement)
            modified = True
            
    if modified:
        with open(file, 'w', encoding=enc) as f:
            f.write(content)
        print(f"Fixed {file}")

