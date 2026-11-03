"""Visible RTL elaboration only; explicitly records excluded vendor black boxes."""
import argparse,json,pathlib,re,subprocess,shutil,os
parser=argparse.ArgumentParser();parser.add_argument('project');p=pathlib.Path(parser.parse_args().project).resolve()
out=p/'results';out.mkdir(exist_ok=True)
iv=os.environ.get('IVERILOG') or shutil.which('iverilog')
if not iv:raise SystemExit('Install Icarus Verilog, add it to PATH or set IVERILOG')
files=sorted((p/'inputs').rglob('*.v'))+sorted((p/'rtl').glob('*.v'))
cmd=[iv,'-g2005','-DSIMULATION','-I',str(p/'inputs/frozen/rtl/common'),'-Wall','-s','top_4bank_720p_m9_final_candidate','-o',str(out/'top_visible_elaboration.vvp'),*map(str,files)]
a=subprocess.run(cmd,capture_output=True,text=True)
(out/'top_strict_elaboration.log').write_text(a.stdout+a.stderr,encoding='utf-8')
b=subprocess.run(cmd[:1]+['-i']+cmd[1:],capture_output=True,text=True)
(out/'top_visible_elaboration.log').write_text(b.stdout+b.stderr,encoding='utf-8')
missing=set(re.findall(r'Unknown module type: ([a-zA-Z_0-9]+)',a.stderr))
deps=json.loads((p/'docs/vendor_dependencies.json').read_text(encoding='utf-8'))['files']
allowed={m for d in deps for m in d['modules']}|{'EG_PHY_SDRAM_2M_32'}
record={'strict_return_code':a.returncode,'visible_blackbox_return_code':b.returncode,'unexpanded_vendor_types':sorted(missing),'unexpected_missing_types':sorted(missing-allowed),'scope':'SIMULATION branch visible RTL elaboration only; no whole-system simulation, synthesis or board test'}
(out/'top_elaboration_status.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps(record));raise SystemExit(0 if b.returncode==0 and not missing-allowed else 1)
