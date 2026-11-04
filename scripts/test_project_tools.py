"""Standard-library tests for pin selection, evidence scoping and dependency hashes."""
import hashlib
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

PROJECT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, PROJECT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load_module('prepare_project')
vendor = load_module('import_vendor_ip')


class ProjectToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='anxin-project-tools-')
        self.project = pathlib.Path(self.temp.name)
        (self.project / 'docs/validation').mkdir(parents=True)
        self.write('docs/SENSOR_PIN_CONFIG.json', {'enabled': True, 'scl_pin': 'J12', 'sda_pin': 'K11'})
        for relative in ['docs/PIN_ASSIGNMENT_REFERENCE.json', 'docs/validation/BOARD_TEST_RECORD.json']:
            self.write(relative, json.loads((PROJECT / relative).read_text(encoding='utf-8')))

    def tearDown(self):
        self.temp.cleanup()

    def write(self, relative, data):
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding='utf-8')

    def test_default_verified_pair(self):
        self.assertEqual(prepare.select_pins(self.project), ['J12', 'K11'])

    def test_explicit_pair_and_case(self):
        self.assertEqual(prepare.select_pins(self.project, 'p4', 'n4'), ['P4', 'N4'])

    def test_saved_local_pair_has_priority(self):
        self.write('build/td/SENSOR_PIN_CONFIG.json', {'enabled': True, 'scl_pin': 'P4', 'sda_pin': 'N4'})
        self.assertEqual(prepare.select_pins(self.project), ['P4', 'N4'])
        self.assertEqual(prepare.select_pins(self.project, 'j12', 'k11'), ['J12', 'K11'])

    def test_disabled_local_pair_stays_disabled(self):
        self.write('build/td/SENSOR_PIN_CONFIG.json', {'enabled': False, 'scl_pin': None, 'sda_pin': None})
        self.assertIsNone(prepare.select_pins(self.project))
        self.assertIsNone(prepare.select_pins(self.project, unbound=True))

    def test_incomplete_and_conflicting_options_rejected(self):
        with self.assertRaises(ValueError):
            prepare.select_pins(self.project, 'J12')
        with self.assertRaises(ValueError):
            prepare.select_pins(self.project, 'J12', 'K11', True)

    def test_malformed_saved_configuration_rejected(self):
        self.write('build/td/SENSOR_PIN_CONFIG.json', {'enabled': True, 'scl_pin': 'J12'})
        with self.assertRaises(ValueError):
            prepare.select_pins(self.project)

    def test_occupied_duplicate_and_invalid_pins_rejected(self):
        adc = 'set_pin_assignment { clk } { LOCATION = R7; IOSTANDARD = LVCMOS33; }\n'
        for pins in [['R7', 'K11'], ['J12', 'J12'], ['bad;pin', 'K11']]:
            with self.subTest(pins=pins), self.assertRaises(ValueError):
                prepare.append_pin_constraints(adc, pins)

    def test_comments_do_not_reserve_pins(self):
        result = prepare.append_pin_constraints('# LOCATION = J12;\n', ['J12', 'K11'])
        self.assertIn('vital_i2c_scl', result)
        self.assertIn('LOCATION = K11', result)
        self.assertEqual(prepare.append_pin_constraints('base', None), 'base')

    def test_archived_result_only_matches_tested_pair(self):
        matched = prepare.binding_evidence(self.project, ['J12', 'K11'])
        self.assertTrue(matched['manual_pinout_verified'])
        self.assertEqual(matched['recorded_board_test_status'], 'passed')
        for pins in [['P4', 'N4'], None]:
            with self.subTest(pins=pins):
                result = prepare.binding_evidence(self.project, pins)
                self.assertFalse(result['manual_pinout_verified'])
                self.assertEqual(result['recorded_board_test_status'], 'pending')

    def test_exact_dependency_hash(self):
        data = b'fixed test payload\n'
        dependency = {'sha256': hashlib.sha256(data).hexdigest()}
        self.assertTrue(vendor.matches_dependency(data, dependency))
        self.assertFalse(vendor.matches_dependency(data + b'changed', dependency))

    def test_only_declared_include_relocation_allowed(self):
        old = b'`include "old/place/global_def.v"\r\nfixed payload\r\n'
        moved = b'`include "new/place/global_def.v"\r\nfixed payload\r\n'
        dependency = {'sha256': hashlib.sha256(old).hexdigest(),
                      'relocatable_include_sha256': vendor.relocated_include_digest(old)}
        self.assertTrue(vendor.matches_dependency(moved, dependency))
        self.assertFalse(vendor.matches_dependency(moved.replace(b'fixed', b'edited'), dependency))
        self.assertFalse(vendor.matches_dependency(moved, {'sha256': dependency['sha256']}))
        self.assertFalse(vendor.matches_dependency(moved.replace(b'\r\n', b'\n'), dependency))


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]], verbosity=2)
