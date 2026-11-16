#!/usr/bin/env python3
"""Connect Codex's local OTLP/JSON exporter to Agent Speed's own receiver. Standard-library Python 3.11+.
Keeps an existing loopback consumer via an optional outgoing relay; never reads that consumer's data.
"""
import argparse
import datetime
import os
from pathlib import Path
import re
import sys
import tomllib
from urllib.parse import urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--codex-home', type=Path, default=Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))))
parser.add_argument('--data-directory', type=Path)
parser.add_argument('--apply', action='store_true', help='Apply after validating the exact change; otherwise dry-run.')
args = parser.parse_args()
config = args.codex_home / 'config.toml'
text = config.read_text()
parsed = tomllib.loads(text)
endpoint = 'http://127.0.0.1:43181/v1/logs'
exporter = parsed.get('otel', {}).get('exporter')
if exporter and exporter != 'none':
    http = exporter.get('otlp-http') if isinstance(exporter, dict) else None
    if not http or http.get('protocol') != 'json':
        raise SystemExit('Existing exporter is not OTLP/HTTP JSON; no change applied.')
    previous = http.get('endpoint', '')
    url = urlsplit(previous)
    if url.scheme != 'http' or url.hostname != '127.0.0.1':
        raise SystemExit('Existing exporter is not loopback HTTP; no change applied.')
    if http.get('headers'):
        raise SystemExit('Existing exporter uses custom headers; no change applied.')
else:
    previous = None
value = 'exporter = { otlp-http = { endpoint = "' + endpoint + '", protocol = "json" } }'
section = re.search(r'(?m)^\[otel\]\s*\n', text)
if section:
    start = section.end(); following = re.search(r'(?m)^\[', text[start:]); end = start + following.start() if following else len(text)
    body = text[start:end]
    line = re.search(r'(?m)^exporter\s*=.*$', body)
    if line:
        # Only rewrite the supported single-line exporter form; preserve all other config and secrets byte for byte.
        candidate = body[:line.start()] + value + body[line.end():]
    elif exporter is None:
        candidate = value + '\n' + body
    else:
        raise SystemExit('Exporter uses a different TOML layout; no change applied.')
    updated = text[:start] + candidate + text[end:]
else:
    if parsed.get('otel'):
        raise SystemExit('OTel uses a different TOML layout; no change applied.')
    updated = text.rstrip() + '\n\n[otel]\n' + value + '\n'
assert tomllib.loads(updated)['otel']['exporter']['otlp-http']['endpoint'] == endpoint
assert {k: v for k, v in tomllib.loads(updated).items() if k != 'otel'} == {k: v for k, v in parsed.items() if k != 'otel'}
if sys.platform == 'darwin':
    default_directory = Path.home() / 'Library/Application Support/Agent Speed'
else:
    default_directory = Path(os.environ.get('LOCALAPPDATA', str(Path.home() / '.local/share'))) / 'AgentSpeed'
directory = args.data_directory or default_directory
relay = previous if previous and previous != endpoint else None
print('Codex exporter -> Agent Speed on 127.0.0.1:43181; existing loopback consumer preserved by relay.' if relay else 'Codex exporter -> Agent Speed on 127.0.0.1:43181.')
if args.apply:
    directory.mkdir(parents=True, exist_ok=True)
    if relay:
        path = directory / 'codex-telemetry-forward.txt'; path.write_text(relay + '\n'); path.chmod(0o600)
    if text != updated:
        backup = args.codex_home / 'backups' / ('config-before-agent-speed-telemetry-' + datetime.datetime.now().strftime('%Y%m%dT%H%M%S') + '.toml')
        backup.parent.mkdir(parents=True, exist_ok=True)
        with backup.open('x') as f:
            os.chmod(backup, 0o600); f.write(text)
        temp = config.with_suffix('.agent-speed.tmp'); temp.write_text(updated); temp.chmod(config.stat().st_mode & 0o777)
        temp.replace(config)
    print('Applied. Existing Codex processes may need restart to load the exporter.')
else:
    print('Dry-run only; use --apply to write.')
