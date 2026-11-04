"""Import only listed dependencies from a source the user is licensed to use."""
import argparse
import hashlib
import json
import pathlib
import re


def relocated_include_digest(data):
    """Normalize only the known relocatable include directory, preserving other bytes."""
    normalized = re.sub(br'(`include[ \t]+")[^"\r\n]*global_def\.v(")', br'\1global_def.v\2', data)
    return hashlib.sha256(normalized).hexdigest()


def matches_dependency(data, dependency):
    if hashlib.sha256(data).hexdigest() == dependency['sha256']:
        return True
    allowed = dependency.get('relocatable_include_sha256')
    return bool(allowed and relocated_include_digest(data) == allowed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project')
    parser.add_argument('--source', required=True)
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    source = pathlib.Path(args.source).resolve()
    dependencies = json.loads((project / 'docs/vendor_dependencies.json').read_text(encoding='utf-8'))['files']
    if source == project:
        raise SystemExit('Use a separate, lawfully obtained complete source directory')
    verified = []
    for dependency in dependencies:
        relative = pathlib.PurePosixPath(dependency['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise SystemExit('Invalid dependency path')
        path = source / relative
        if not path.is_file():
            raise SystemExit('Missing external dependency: ' + dependency['path'])
        data = path.read_bytes()
        if not matches_dependency(data, dependency):
            raise SystemExit('Dependency version differs from the tested source: ' + dependency['path'])
        verified.append((relative, data))
    # All members are verified before writing any member. No unlisted file is imported.
    for relative, data in verified:
        destination = project / '.local_vendor' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    print('Imported ' + str(len(verified)) + ' local-only files. Vendor rights are unchanged.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
