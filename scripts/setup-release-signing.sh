#!/bin/bash
# One-time setup. Do not rotate this identity during an ordinary release.
set -euo pipefail
umask 077
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
destination="$project_dir/.release-signing"
config="$project_dir/config/release-signing.json"
if [[ -e "$destination" || -e "$config" ]]; then
    printf '%s\n' 'Release signing material already exists. Refusing to replace it.' >&2
    exit 1
fi
secret_dir="$(mktemp -d "$project_dir/.release-signing.staging.XXXXXX")"
trap 'rm -rf "$secret_dir"' EXIT
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -subj '/CN=Chizu Release/' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$secret_dir/code-signing.key" -out "$secret_dir/code-signing.crt" 2>"$secret_dir/openssl.log"
openssl rand -base64 32 > "$secret_dir/p12-password"
# The macOS Security framework needs legacy PKCS#12 encryption for import.
openssl pkcs12 -export -legacy -inkey "$secret_dir/code-signing.key" \
    -in "$secret_dir/code-signing.crt" -name 'Chizu Release' \
    -out "$secret_dir/code-signing.p12" -passout "file:$secret_dir/p12-password"
openssl x509 -in "$secret_dir/code-signing.crt" -outform DER -out "$secret_dir/code-signing.der"
mkdir -p config
python3 - "$secret_dir/code-signing.der" "$config" <<'PY'
import hashlib, json, pathlib, sys
fingerprint = hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()
pathlib.Path(sys.argv[2]).write_text(json.dumps({"certificateSHA256": fingerprint}, indent=2) + "\n")
PY
chmod 644 "$config"
mv "$secret_dir" "$destination"
printf '%s\n' 'Created public config/release-signing.json and private .release-signing/.' \
    'Back up .release-signing/ securely; future releases need the same identity.'
