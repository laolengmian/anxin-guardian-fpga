# Third-party notices / 第三方权属说明

The project MIT license applies to the original project code and documentation,
not to third-party font data or separately obtained proprietary IP.

## Adobe-derived glyph data: SIL Open Font License 1.1

Copyright 2014–2021 Adobe. Reserved Font Name: Source.
The original UI ROM identifies Adobe and SIL OFL 1.1. The original asset metadata
pins the license SHA256 to
`6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`.
The matching license was recovered from the official Adobe repository history:
see [font license provenance](docs/font_license_provenance.json).
The font binary is not distributed here, and its exact binary version is not
claimed to have been independently recovered.

The glyph/font components in these files are distributed under OFL 1.1, **not MIT**:

- `inputs/candidate/rtl/m9_ui_glyph_rom.v`
- `inputs/candidate/rtl/m9_monitor_chinese_glyph_rom.v`
- `inputs/assets/m9_ui/u4_generated.json` (embedded glyph bitmap data)
- `inputs/frozen/rtl/osd/m9_u6_glyph_rom.v` (retains its original preparation-artifact hash)

See [LICENSES/Adobe-OFL-1.1.txt](LICENSES/Adobe-OFL-1.1.txt).
No font vendor endorses this project. ROM module identifiers are not font names.

## Anlogic / board reference IP: external, not distributed

The encrypted HDMI/SDRAM implementation, vendor FIFOs and related board-reference
files, generated PLL sources and sidecars are excluded from this repository.
The exact 13 paths and source hashes are listed in
[docs/vendor_dependencies.json](docs/vendor_dependencies.json).
Some are vendor-copyrighted; others are isolated with their reference subsystem
because an explicit redistribution license was not available in the supplied package.

Obtain these files through an authorized vendor/board channel or from a complete
source package you are entitled to use. Importing them locally does not grant
redistribution rights and does not change their licenses. `.local_vendor/` and TD
working copies are ignored by Git. Do not force-add them.

## Media and reports

TF-card BMP/WAV content, Word reports, personal photographs, credentials and the
private original ZIP are not included. Provide your own authorized media matching
[docs/MEDIA.md](docs/MEDIA.md). References to MAX30102, Anlogic and HDMI identify
hardware/interfaces; they do not imply affiliation or certification.
