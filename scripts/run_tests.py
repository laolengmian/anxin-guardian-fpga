"""Run all HDL regressions. Requires Icarus Verilog and vvp, no TD or hardware."""
import os
import argparse,csv,datetime,hashlib,json,pathlib,shutil,statistics,subprocess,sys
parser=argparse.ArgumentParser();parser.add_argument('project');a=parser.parse_args()
p=pathlib.Path(a.project).resolve();out=p/'results';out.mkdir(exist_ok=True)
iv=os.environ.get('IVERILOG') or shutil.which('iverilog');vv=os.environ.get('VVP') or shutil.which('vvp')
if not iv or not vv:raise SystemExit('Install Icarus Verilog and add iverilog/vvp to PATH, or set IVERILOG and VVP.')
(out/'TEST_REPORT.json').write_text(json.dumps({'pass':False,'status':'running'}),encoding='utf-8')
rtl=sorted((p/'rtl').glob('*.v'));reports=[]
def execute(name,command):
    result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=600)
    (out/(name+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode:print(result.stdout+result.stderr,flush=True)
    result.check_returncode();return result.stdout

def bench(name,files,extra=()):
    exe=out/(name+'.vvp')
    execute(name+'_compile',[iv,'-g2012','-Wall','-s',name,'-o',exe,*rtl,*files])
    text=execute(name,[vv,exe,*extra]);print(text.strip(),flush=True)
    reports.append({'suite':name,'pass':True,'log':name+'.log'})
bench('tb_math',[p/'sim/tb_math.sv'])
bench('tb_acquisition',[p/'sim/max3010x_model.sv',p/'sim/tb_acquisition.sv'])
bench('tb_vital_cdc',[p/'sim/tb_vital_cdc.sv'])
text=execute('algorithm_regression',[sys.executable,'-I',p/'scripts/test_algorithm.py',p]);print(text.strip(),flush=True)
algorithm=json.loads((out/'algorithm_results.json').read_text(encoding='utf-8'))
assert len(algorithm)==13 and all(x['pass'] for x in algorithm)
reports.append({'suite':'raw_PPG_waveforms','cases':13,'pass':True,'results':'algorithm_results.json'})
exe=out/'tb_calibration.vvp'
execute('calibration_compile',[iv,'-g2012','-s','tb_ppg_vitals','-Ptb_ppg_vitals.CAL_A_Q8=28416','-o',exe,*rtl,p/'sim/tb_ppg_vitals.sv'])
execute('calibration',[vv,exe,'+INPUT='+str(p/'sim/vectors/normal.txt'),'+OUTPUT='+str(out/'calibration.csv'),'+N=9000'])
rows=[x for x in csv.DictReader((out/'calibration.csv').open()) if int(x['sample'])>=6000 and int(x['spo2_valid'])]
cal=statistics.median(int(x['spo2']) for x in rows)
assert cal==99,cal
reports.append({'suite':'configurable_calibration','pass':True,'expected_spo2':99,'measured_spo2':cal})
print('PASS configurable calibration: A=111, output SpO2=99',flush=True)
bench('tb_vital_integration',[p/'inputs/candidate/rtl/m9_vital_monitor_overlay.v',p/'inputs/candidate/rtl/m9_monitor_chinese_glyph_rom.v',p/'sim/max3010x_model.sv',p/'sim/tb_vital_integration.sv'],['+INPUT='+str(p/'sim/vectors/normal.txt'),'+VCD='+str(out/'vital_integration.vcd')])
# Compile the complete new sensor/DSP subsystem under Verilog-2005 as well.
execute('verilog2005_compile',[iv,'-g2005','-Wall','-s','m9_vital_processing_subsystem','-o',out/'subsystem_compile.vvp',*rtl])
reports.append({'suite':'Verilog2005_subsystem_compile','pass':True})
identities={str(f.relative_to(p)).replace(chr(92),'/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in rtl+[p/'inputs/candidate/rtl/top_4bank_720p_m9_vitals.v',p/'inputs/candidate/rtl/m9_vital_monitor_overlay.v']}
report={'completed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pass':True,'suites':reports,'tested_source_sha256':identities,
        'signal_source':'Deterministic raw red/IR PPG stimuli; I2C behavioral peripheral model',
        'performed':['HDL simulation','sensor-register protocol tests','CDC reset tests','algorithm waveform regression'],
        'not_performed':['TD synthesis/place/route/bitgen','board programming or sensor capture','clinical accuracy validation']}
(out/'TEST_REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('ALL REQUESTED HDL REGRESSIONS PASSED',flush=True)
