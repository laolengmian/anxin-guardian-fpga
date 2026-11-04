"""Prepare an ignored TD working copy without changing tracked RTL or hardware."""
import argparse
import json
import pathlib
import re
import shutil
import xml.etree.ElementTree as ET


def select_pins(project, scl=None, sda=None, unbound=False):
    """Resolve explicit options, then local saved settings, then repository defaults."""
    if unbound and (scl or sda):
        raise ValueError('--unbound cannot be combined with pin arguments')
    if bool(scl) != bool(sda):
        raise ValueError('Provide both SCL and SDA pins')
    if unbound:
        return None
    if scl:
        return [scl.upper(), sda.upper()]
    for source in [project / 'build/td/SENSOR_PIN_CONFIG.json', project / 'docs/SENSOR_PIN_CONFIG.json']:
        if not source.is_file():
            continue
        saved = json.loads(source.read_text(encoding='utf-8'))
        if not isinstance(saved.get('enabled'), bool):
            raise ValueError('Saved pin configuration needs a boolean enabled field')
        if not saved['enabled']:
            return None
        pair = [saved.get('scl_pin'), saved.get('sda_pin')]
        if not all(isinstance(pin, str) and pin for pin in pair):
            raise ValueError('Saved configuration must provide both pins')
        return [pin.upper() for pin in pair]
    return None


def append_pin_constraints(adc, pins):
    if not pins:
        return adc
    active = '\n'.join(line.split('#', 1)[0] for line in adc.splitlines())
    used = set(re.findall(r'LOCATION\s*=\s*([A-Z]+[0-9]+)', active))
    if pins[0] == pins[1] or any(not re.fullmatch(r'[A-Z]+[0-9]+', pin) or pin in used for pin in pins):
        raise ValueError('Pins must be different, syntactically valid and unused; check hardware voltage separately')
    for signal, pin in zip(['vital_i2c_scl', 'vital_i2c_sda'], pins):
        adc += '\nset_pin_assignment { ' + signal + ' } { LOCATION = ' + pin + '; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }\n'
    return adc


def binding_evidence(project, pins):
    reference_path = project / 'docs/PIN_ASSIGNMENT_REFERENCE.json'
    board_path = project / 'docs/validation/BOARD_TEST_RECORD.json'
    reference = json.loads(reference_path.read_text(encoding='utf-8')) if reference_path.is_file() else {}
    board = json.loads(board_path.read_text(encoding='utf-8')) if board_path.is_file() else {}
    signals = reference.get('signals', {})
    reference_pair = [signals.get(name, {}).get('FPGA_ball') for name in ['vital_i2c_scl', 'vital_i2c_sda']]
    manual = bool(pins and pins == reference_pair and reference.get('manual_pinout_verified'))
    tested = board.get('pin_assignment', {})
    test_pair = [tested.get('scl_ball'), tested.get('sda_ball')]
    passed = bool(pins and pins == test_pair and board.get('status') == 'passed'
                  and board.get('test_type') == 'board_functional_test' and board.get('pass') is True)
    return {
        'assignment_status': 'manual_pinout_verified' if manual else ('custom_pin_assignment_pending_verification' if pins else 'unbound'),
        'manual_pinout_verified': manual,
        'recorded_board_test_status': 'passed' if passed else 'pending',
        'board_test_record': 'docs/validation/BOARD_TEST_RECORD.json' if passed else None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project')
    parser.add_argument('--scl-pin')
    parser.add_argument('--sda-pin')
    parser.add_argument('--unbound', action='store_true')
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        pins = select_pins(project, args.scl_pin, args.sda_pin, args.unbound)
        adc = append_pin_constraints((project / 'inputs/constraints/pin_competition_final_candidate_v2_gpio.adc').read_text(encoding='utf-8-sig'), pins)
    except (ValueError, TypeError) as error:
        parser.error(str(error))
    dependencies = json.loads((project / 'docs/vendor_dependencies.json').read_text(encoding='utf-8'))['files']
    missing = [dep['path'] for dep in dependencies if not (project / '.local_vendor' / dep['path']).is_file()]
    if missing:
        print('External licensed vendor files are not included. See docs/BUILD.md. Missing:')
        print('\n'.join(missing))
        return 2
    view = project / 'build/td'
    view.mkdir(parents=True, exist_ok=True)
    for folder in ['inputs', 'rtl']:
        shutil.copytree(project / folder, view / folder, dirs_exist_ok=True)
    for dep in dependencies:
        destination = view / dep['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(project / '.local_vendor' / dep['path'], destination)
    (view / 'inputs/constraints/pin_vitals.adc').write_bytes(adc.encode('utf-8'))
    header = (view / 'inputs/frozen/rtl/common/global_def.v').as_posix()
    for source in (view / 'inputs').rglob('*.v'):
        data = source.read_bytes()
        if b'`include ' in data and b'global_def.v' in data:
            text = re.sub(r'(`include[ \t]+")[^"\r\n]*global_def\.v(")', lambda match: match[1] + header + match[2], data.decode('utf-8'))
            source.write_bytes(text.encode('utf-8'))
    template = ET.fromstring((project / 'td/project_template.al').read_text(encoding='utf-8').replace('&', '&amp;'))
    template.set('Path', view.as_posix())
    for item in template.findall('.//File'):
        relative = pathlib.PurePosixPath(item.attrib['Path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Invalid template path')
        target = view / relative
        if not target.is_file():
            raise FileNotFoundError(target)
        item.set('Path', target.as_posix())
    ET.indent(template, space='    ')
    output = view / 'anxin_guardian_vitals.al'
    output.write_bytes(ET.tostring(template, encoding='unicode').replace('&amp;', '&').encode('utf-8'))
    record = {
        'project': output.relative_to(project).as_posix(),
        'file_records': len(template.findall('.//File')),
        'sensor_pins_bound': bool(pins), 'scl_pin': pins[0] if pins else None, 'sda_pin': pins[1] if pins else None,
        'tool_started': False, 'hardware_test_executed_by_script': False,
        **binding_evidence(project, pins),
    }
    saved = {'enabled': bool(pins), 'scl_pin': pins[0] if pins else None, 'sda_pin': pins[1] if pins else None}
    (view / 'SENSOR_PIN_CONFIG.json').write_text(json.dumps(saved, indent=2) + '\n', encoding='utf-8')
    (view / 'PROJECT_BINDING.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(record))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
