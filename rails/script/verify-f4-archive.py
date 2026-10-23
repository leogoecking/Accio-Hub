"""Read-only verification of the private F4 evidence archive. Never extracts files."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(chunk)
    return result.hexdigest()


def verify(archive, manifest_path):
    manifest = json.loads(manifest_path.read_text())
    if archive.stat().st_size != manifest['archive_size_bytes']:
        raise ValueError('Archive size mismatch')
    with archive.open('rb') as stream:
        if digest(stream) != manifest['sha256']:
            raise ValueError('Archive SHA-256 mismatch')
    index_bytes = (manifest_path.parent / manifest['index_file']).read_bytes()
    index = json.loads(index_bytes)
    if index['set_id'] != manifest['set_id']:
        raise ValueError('Set identifier mismatch')
    with tarfile.open(archive, 'r:gz') as package:
        members = package.getmembers()
        if len(members) != manifest['archive_members']:
            raise ValueError('Archive member count mismatch')
        if members[0].name != 'ARCHIVE_FILE_INDEX.json':
            raise ValueError('Missing internal inventory')
        if package.extractfile(members[0]).read() != index_bytes:
            raise ValueError('Internal/external inventory mismatch')
        rows = index['files']
        if len(rows) != manifest['source_files'] or len(members) != len(rows) + 1:
            raise ValueError('Source file count mismatch')
        if len({row['path'] for row in rows}) != len(rows):
            raise ValueError('Duplicate inventory paths')
        for member, row in zip(members[1:], rows):
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not member.isfile():
                raise ValueError('Unsafe archive member')
            if member.name != row['path'] or member.size != row['size']:
                raise ValueError('Member metadata mismatch')
            with package.extractfile(member) as stream:
                if digest(stream) != row['sha256']:
                    raise ValueError('Member content mismatch')
    print(json.dumps({'verified': True, 'source_files': len(rows),
                      'archive_sha256': manifest['sha256'], 'extracted': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    verify(args.archive, args.manifest)
