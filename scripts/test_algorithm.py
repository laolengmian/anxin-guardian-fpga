"""Generate deterministic raw PPG stimuli and execute the production RTL."""
import argparse,csv,json,math,pathlib,random,statistics,subprocess,os,shutil
p=argparse.ArgumentParser();p.add_argument('project');a=p.parse_args()
r=pathlib.Path(a.project).resolve();out=r/'results';vec=r/'sim/vectors'
out.mkdir(exist_ok=True);vec.mkdir(parents=True,exist_ok=True)
iv=os.environ.get('IVERILOG') or shutil.which('iverilog');vv=os.environ.get('VVP') or shutil.which('vvp')
if not iv or not vv:raise SystemExit('Install Icarus Verilog and add iverilog/vvp to PATH, or set IVERILOG and VVP.')
sources=[r/'rtl'/x for x in ['m9_unsigned_divider.v','m9_integer_sqrt.v','m9_ppg_rate_estimator.v','m9_ppg_vitals.v']]
exe=out/'tb_ppg_vitals.vvp'
build=subprocess.run([iv,'-g2012','-Wall','-s','tb_ppg_vitals','-o',str(exe),*map(str,sources),str(r/'sim/tb_ppg_vitals.sv')],capture_output=True,text=True)
(out/'algorithm_compile.log').write_text(build.stdout+build.stderr,encoding='utf-8');build.check_returncode()
cases=[('normal',72,98,12,25,5000,.04),('slow',48,96,8,25,5000,.04),('fast',144,95,24,30,5000,.055),('low_spo2',90,90,18,25,5000,.04),('noise',108,97,15,150,5000,.04),('flat',0,0,0,0,0,0),('dark',0,0,0,0,0,0),('saturation',0,0,0,0,0,0),('weak',72,98,12,2,8,0),('no_respiration',72,98,0,15,5000,0),('rate_step',120,90,20,25,5000,.04),('contact_loss',0,0,0,0,0,0),('pulse_loss',0,0,0,0,0,0)]
reports=[]
for ci,(name,hr,sp,rr,noise,amp,resp_amp) in enumerate(cases):
    rng=random.Random(9300+ci);n=9000;f=vec/(name+'.txt')
    with f.open('w') as stream:
        for i in range(n):
            t=i/100
            if name=='rate_step':
                hr,sp,rr=(72,98,12) if i<3000 else (120,90,20)
            if name in ['contact_loss','pulse_loss']:
                hr,sp,rr,amp,resp_amp=(72,98,12,5000,.04) if i<4500 else (0,0,0,0,0)
            breath=math.sin(2*math.pi*rr*t/60) if rr else 0
            pulse=math.sin(2*math.pi*hr*t/60)+.12*math.sin(4*math.pi*hr*t/60+.4) if hr else 0
            red_dc=90000*(1+resp_amp*breath);ir_dc=110000*(1+resp_amp*breath)
            ratio=(110-sp)/25 if sp else .5
            ir=int(ir_dc+amp*pulse+rng.gauss(0,noise))
            red=int(red_dc+amp*ratio*90000/110000*pulse+rng.gauss(0,noise))
            if name=='dark' or (name=='contact_loss' and i>=4500):red=ir=200
            if name=='saturation':red=ir=262143
            red=max(0,min(262143,red));ir=max(0,min(262143,ir))
            stream.write(f'{red:05x} {ir:05x}\n')
    csvpath=out/(name+'.csv')
    run=subprocess.run([vv,str(exe),'+INPUT='+str(f),'+OUTPUT='+str(csvpath),'+N='+str(n)],capture_output=True,text=True,timeout=180)
    (out/(name+'.log')).write_text(run.stdout+run.stderr,encoding='utf-8');run.check_returncode()
    rows=[{k:int(v) for k,v in x.items()} for x in csv.DictReader(csvpath.open()) if int(x['sample'])>=6000]
    measured={};valid={}
    for key,flag in [('hr','hr_valid'),('spo2','spo2_valid'),('rr','rr_valid')]:
        values=[x[key] for x in rows if x[flag]]
        measured[key]=statistics.median(values) if values else None;valid[key]=len(values)/len(rows)
    if name in ['flat','dark','saturation','weak','contact_loss','pulse_loss']:
        ok=all(v==0 for v in valid.values())
    else:
        ok=valid['hr']>=.9 and valid['spo2']>=.9 and abs(measured['hr']-hr)<=2 and abs(measured['spo2']-sp)<=2
        ok=ok and ((valid['rr']>=.9 and abs(measured['rr']-rr)<=2) if rr else valid['rr']==0)
    record={'case':name,'expected':{'hr':hr,'spo2':sp,'rr':rr},'median':measured,'valid_fraction':valid,'pass':ok}
    reports.append(record);print(json.dumps(record),flush=True)
(out/'algorithm_results.json').write_text(json.dumps(reports,indent=2))
raise SystemExit(0 if all(x['pass'] for x in reports) else 1)
