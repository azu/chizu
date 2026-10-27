#!/bin/bash
# Package an Apple Silicon release with the pinned signing identity.
set -euo pipefail
umask 077
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(bash scripts/version.sh)"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf '%s\n' 'Release packaging requires an Apple Silicon Mac.' >&2
    exit 1
fi
[[ -f config/release-signing.json ]] || { printf '%s\n' 'Run scripts/setup-release-signing.sh and commit its public config.' >&2; exit 1; }
mkdir -p dist
staging_dir="$(mktemp -d "$project_dir/dist/.release.XXXXXX")"
keychain="$staging_dir/signing.keychain-db"
previous_keychains=()
while IFS= read -r path; do previous_keychains+=("$path"); done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
cleanup() {
    if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
        python3 - "$keychain" "$staging_dir/certificate.pem" "${trusted_in_ci:-0}" "${previous_keychains[@]}" <<'PY'
import subprocess, sys
keychain, certificate, trusted, *previous = sys.argv[1:]
commands = []
if trusted == "1":
    commands.append(("remove temporary certificate trust", ["sudo", "-n", "security", "remove-trusted-cert", "-d", certificate]))
commands.extend([
    ("restore keychain search list", ["security", "list-keychains", "-d", "user", "-s", *previous]),
    ("delete temporary keychain", ["security", "delete-keychain", keychain]),
])
for label, command in commands:
    print(f"Cleanup: {label}", flush=True)
    try:
        result = subprocess.run(command, timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            print(f"::warning::Could not {label}; the hosted runner will be discarded.", flush=True)
    except subprocess.TimeoutExpired:
        print(f"::warning::Timed out attempting to {label}; the hosted runner will be discarded.", flush=True)
PY
    else
        security list-keychains -d user -s "${previous_keychains[@]}" >/dev/null 2>&1 || true
        security delete-keychain "$keychain" >/dev/null 2>&1 || true
    fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT
python3 - "$project_dir/.release-signing" "$staging_dir" <<'PY'
import base64, os, pathlib, sys
local, target = map(pathlib.Path, sys.argv[1:])
for env, source, dest, encoded in [
    ("CODE_SIGN_P12_BASE64", "code-signing.p12", "identity.p12", True),
    ("CODE_SIGN_P12_PASSWORD", "p12-password", "p12-password", False),
]:
    value = os.environ.get(env)
    if value:
        data = base64.b64decode(value, validate=True) if encoded else value.encode()
    elif (local / source).is_file():
        data = (local / source).read_bytes()
    else:
        raise SystemExit(f"Missing release secret: {env}")
    (target / dest).write_bytes(data)
PY
keychain_password="$(openssl rand -base64 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain" "${previous_keychains[@]}"
security import "$staging_dir/identity.p12" -k "$keychain" -P "$(cat "$staging_dir/p12-password")" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security find-certificate -p "$keychain" > "$staging_dir/certificate.pem"
openssl x509 -in "$staging_dir/certificate.pem" -outform DER -out "$staging_dir/certificate.der"
python3 - config/release-signing.json "$staging_dir/certificate.der" <<'PY'
import hashlib, json, pathlib, sys
expected = json.loads(pathlib.Path(sys.argv[1]).read_text())["certificateSHA256"]
actual = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit("Release certificate changed; refusing to change the app's signing identity")
PY
identity="$(openssl x509 -in "$staging_dir/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
    trusted_in_ci=1
    sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$keychain" "$staging_dir/certificate.pem"
fi
if ! security find-identity -v -p codesigning "$keychain" | grep -Fq "$identity"; then
    printf '%s\n' 'Release certificate is not trusted. Run scripts/trust-release-certificate.sh on this Mac.' >&2
    exit 1
fi
CHIZU_SIGNING_IDENTITY="$identity" bash scripts/build-app.sh
requirement="identifier \"dev.azu.chizu\" and certificate leaf = H\"$identity\""
codesign --verify --strict -R="$requirement" dist/Chizu.app
if codesign -d -r- dist/Chizu.app 2>&1 | sed -n '/designated =>/p' | grep -q 'cdhash'; then
    printf '%s\n' 'Release has a build-specific signing requirement.' >&2
    exit 1
fi
archive="chizu-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Chizu.app "$staging_dir/$archive"
ditto -x -k "$staging_dir/$archive" "$staging_dir/unpacked"
codesign --verify --strict -R="$requirement" "$staging_dir/unpacked/Chizu.app"
actual_version="$(plutil -extract CFBundleShortVersionString raw "$staging_dir/unpacked/Chizu.app/Contents/Info.plist")"
[[ "$actual_version" == "$version" ]]
(cd "$staging_dir" && shasum -a 256 "$archive" > "$archive.sha256")
mv "$staging_dir/$archive" "$staging_dir/$archive.sha256" dist/
printf '%s\n' "$project_dir/dist/$archive"
