#!/bin/bash
# Trust only the pinned certificate for code signing on this authoring Mac.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
certificate="$project_dir/.release-signing/code-signing.crt"
python3 - "$project_dir/config/release-signing.json" "$certificate" <<'PY'
import hashlib, json, pathlib, subprocess, sys
expected = json.loads(pathlib.Path(sys.argv[1]).read_text())["certificateSHA256"]
actual = hashlib.sha256(subprocess.check_output(["openssl", "x509", "-in", sys.argv[2], "-outform", "DER"])).hexdigest()
if actual != expected:
    raise SystemExit("Release certificate changed")
PY
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$certificate"
