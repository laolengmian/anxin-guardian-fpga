"""Import only listed dependencies from a source the user is licensed to use."""
import argparse,hashlib,json,pathlib,shutil

def main():
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('project');a.add_argument('--source',required=True)
    args=a.parse_args();p=pathlib.Path(args.project).resolve();source=pathlib.Path(args.source).resolve()
    dependencies=json.loads((p/'docs/vendor_dependencies.json').read_text(encoding='utf-8'))['files']
    if source==p:raise SystemExit('Use a separate, lawfully obtained complete source directory')
    for d in dependencies:
        rel=pathlib.PurePosixPath(d['path']);f=source/rel
        if rel.is_absolute() or '..' in rel.parts:raise SystemExit('Invalid dependency path')
        if not f.is_file():raise SystemExit('Missing external dependency: '+d['path'])
        if hashlib.sha256(f.read_bytes()).hexdigest()!=d['sha256']:
            raise SystemExit('Dependency version differs from the tested source: '+d['path'])
    for d in dependencies:
        dest=p/'.local_vendor'/d['path'];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/d['path'],dest)
    print('Imported '+str(len(dependencies))+' local-only files. Vendor rights are unchanged.');return 0

if __name__=='__main__':raise SystemExit(main())
