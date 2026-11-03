"""Prepare an ignored TD working copy. Does not synthesize or touch hardware."""
import argparse,json,pathlib,re,shutil,xml.etree.ElementTree as ET

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project');parser.add_argument('--scl-pin');parser.add_argument('--sda-pin')
    a=parser.parse_args();p=pathlib.Path(a.project).resolve()
    if bool(a.scl_pin)!=bool(a.sda_pin):parser.error('Provide both SCL and SDA pins')
    dependencies=json.loads((p/'docs/vendor_dependencies.json').read_text(encoding='utf-8'))['files']
    missing=[d['path'] for d in dependencies if not (p/'.local_vendor'/d['path']).is_file()]
    if missing:
        print('External licensed vendor files are not included. See docs/BUILD.md. Missing:')
        print('\n'.join(missing));return 2
    adc=(p/'inputs/constraints/pin_competition_final_candidate_v2_gpio.adc').read_text(encoding='utf-8-sig')
    pins=None
    if a.scl_pin:
        pins=[a.scl_pin.upper(),a.sda_pin.upper()]
        used=set(re.findall(r'LOCATION\s*=\s*([A-Z]+[0-9]+)',adc))
        if pins[0]==pins[1] or any(x in used or not re.fullmatch(r'[A-Z]+[0-9]+',x) for x in pins):
            parser.error('Pins must be different, syntactically valid and unused; check hardware voltage separately')
        for signal,pin in zip(['vital_i2c_scl','vital_i2c_sda'],pins):
            adc+='\nset_pin_assignment { '+signal+' } { LOCATION = '+pin+'; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }\n'
    view=p/'build/td';view.mkdir(parents=True,exist_ok=True)
    for folder in ['inputs','rtl']:
        shutil.copytree(p/folder,view/folder,dirs_exist_ok=True)
    for dep in dependencies:
        dest=view/dep['path'];dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(p/'.local_vendor'/dep['path'],dest)
    (view/'inputs/constraints/pin_vitals.adc').write_text(adc,encoding='utf-8')
    header=(view/'inputs/frozen/rtl/common/global_def.v').as_posix()
    for f in (view/'inputs').rglob('*.v'):
        text=f.read_text(encoding='utf-8-sig')
        if '`include ' in text and 'global_def.v' in text:
            text=re.sub(r'(`include\s+")[^"]*global_def\.v(")',lambda m:m[1]+header+m[2],text)
            f.write_text(text,encoding='utf-8')
    root=ET.fromstring((p/'td/project_template.al').read_text(encoding='utf-8').replace('&','&amp;'))
    root.set('Path',view.as_posix())
    for item in root.findall('.//File'):
        rel=pathlib.PurePosixPath(item.attrib['Path'])
        if rel.is_absolute() or '..' in rel.parts:raise ValueError('Invalid template path')
        target=view/rel;assert target.is_file(),target;item.set('Path',target.as_posix())
    ET.indent(root,space='    ')
    out=view/'anxin_guardian_vitals.al'
    out.write_text(ET.tostring(root,encoding='unicode').replace('&amp;','&'),encoding='utf-8')
    record={'project':out.relative_to(p).as_posix(),'file_records':len(root.findall('.//File')),'sensor_pins_bound':bool(pins),'scl_pin':pins[0] if pins else None,'sda_pin':pins[1] if pins else None,'tool_started':False}
    (view/'PROJECT_BINDING.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print(json.dumps(record));return 0

if __name__=='__main__':raise SystemExit(main())
