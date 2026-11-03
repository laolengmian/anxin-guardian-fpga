"""Validate the redistributable tree; no network or proprietary IP required."""
import hashlib,json,pathlib,re,subprocess,sys,xml.etree.ElementTree as ET
p=pathlib.Path(sys.argv[1]).resolve()
deps=json.loads((p/'docs/vendor_dependencies.json').read_text(encoding='utf-8'))['files']
assert len(deps)==13 and len({d['path'] for d in deps})==13
for d in deps:
    rel=pathlib.PurePosixPath(d['path']);assert not rel.is_absolute() and '..' not in rel.parts
    assert not (p/rel).exists(),'Proprietary dependency must stay outside the public source tree: '+d['path']
assert hashlib.sha256((p/'LICENSES/Adobe-OFL-1.1.txt').read_bytes()).hexdigest()=='6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2'
assert 'MIT License' in (p/'LICENSE').read_text(encoding='utf-8')
root=ET.fromstring((p/'td/project_template.al').read_text(encoding='utf-8').replace('&','&amp;'))
files=root.findall('.//File');assert len(files)==115,len(files)
expected={d['path'] for d in deps}
missing=set()
for item in files:
    rel=pathlib.PurePosixPath(item.attrib['Path']);assert not rel.is_absolute() and ':' not in str(rel) and '..' not in rel.parts
    if not (p/rel).is_file():missing.add(rel.as_posix())
assert missing<=expected,missing-expected
# Preparing TD without local dependencies must stop explicitly, not invent stubs.
if not all((p/'.local_vendor'/d['path']).is_file() for d in deps):
    r=subprocess.run([sys.executable,'-I',str(p/'scripts/prepare_project.py'),str(p)],capture_output=True,text=True)
    assert r.returncode==2,(r.returncode,r.stdout,r.stderr)
for f in list((p/'inputs').rglob('*'))+list((p/'rtl').glob('*.v')):
    if not f.is_file():continue
    text=f.read_text(encoding='utf-8-sig')
    assert not re.search(r'[A-Za-z]:/(?:Users|AnxinGuardian|iverilog)',text.replace(chr(92),'/')),f
print('PASS publication structure: 115 TD records, 13 external dependencies, pinned OFL, no fabricated vendor stubs.')
