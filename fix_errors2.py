import os
import glob
import re

def process_file(file):
    try:
        content = ""
        enc = 'utf-8'
        try:
            with open(file, 'r', encoding='utf-8') as f:
                content = f.read()
        except:
            enc = 'utf-16'
            with open(file, 'r', encoding='utf-16') as f:
                content = f.read()
                
        modified = False
        
        if file == 'MultiBotPro_Coordinator.mqh':
            if '->' in content:
                content = content.replace('m_workerQueue->', 'm_workerQueue.')
                content = content.replace('m_riskEngine->', 'm_riskEngine.')
                content = content.replace('m_systemState->', 'm_systemState.')
                content = content.replace('m_coordinatorQueue->', 'm_coordinatorQueue.')
                modified = True
            
            if 'm_systemState.SetCurrentDayOfYear(TimeDayOfYear(TimeCurrent()));' in content:
                replacement = '''MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      m_systemState.SetCurrentDayOfYear(dt.day_of_year);'''
                content = content.replace('m_systemState.SetCurrentDayOfYear(TimeDayOfYear(TimeCurrent()));', replacement)
                modified = True

        if file == 'MultiBotPro_AIBridge.mqh':
            content = re.sub(r'StringTrim\(([a-zA-Z0-9_]+)\);', r'StringTrimLeft(\1); StringTrimRight(\1);', content)
            modified = True
            
        if file == 'MultiBotPro_SystemTests.mqh':
            content = content.replace('static const ulong HEARTBEAT_TIMEOUT_MS = 5000;', '')
            content = content.replace('static const int STRESS_OPERATIONS = 100;', '')
            content = content.replace('HEARTBEAT_TIMEOUT_MS', '5000')
            content = content.replace('STRESS_OPERATIONS', '100')
            content = content.replace('SPositionOp &op = m_operations[i];', 'SPositionOp op = m_operations[i];')
            modified = True
            
        if file == 'MultiBotPro_MessageQueue.mqh':
            content = re.sub(r'SMbpMessage\s+&([a-zA-Z0-9_]+)\s*=', r'SMbpMessage \1 =', content)
            modified = True
            
        if file == 'MultiBotPro_RiskEngine.mqh':
            content = content.replace('SymbolInfoDouble(symbol, SYMBOL_TRADE_STOPS_LEVEL)', '(double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL)')
            modified = True

        if modified:
            with open(file, 'w', encoding=enc) as f:
                f.write(content)
            print(f"Fixed {file}")
            
    except Exception as e:
        pass

for file in glob.glob('*.mq*'):
    if not file.endswith('.bak'):
        process_file(file)

