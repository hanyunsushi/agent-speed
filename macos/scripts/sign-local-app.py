#!/usr/bin/env python3
"""Sign a local build with its persistent identity, or explicitly allow an ad-hoc fallback.

Signing keys and configuration stay outside the repository. No system trust settings are changed.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess


def run(command):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        # Do not include command arguments: unlock-keychain receives a private signing-store password.
        raise SystemExit(result.stderr.strip() or "Signing operation failed")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity-config", type=Path, default=Path.home() /
                        "Library/Application Support/Agent Speed/Signing/identity.json")
    parser.add_argument("--allow-ad-hoc", action="store_true")
    args = parser.parse_args()
    if not args.app.is_dir():
        raise SystemExit("Application bundle not found")

    command = ["codesign", "--force", "--deep", "--options", "runtime", "--timestamp=none"]
    if args.identity_config.exists():
        config = json.loads(args.identity_config.read_text())
        identity = config["identity"]
        keychain = Path(config["keychain"])
        password_file = Path(config["passwordFile"])
        certificate = Path(config.get("certificate", args.identity_config.parent / "certificate.pem"))
        if not re.fullmatch(r"[0-9A-Fa-f]{40}", identity) or not keychain.is_file() or not password_file.is_file():
            raise SystemExit("Local signing configuration is incomplete; refusing an ad-hoc downgrade")
        run(["security", "verify-cert", "-c", str(certificate), "-p", "codeSign"])
        run(["security", "unlock-keychain", "-p", password_file.read_text(), str(keychain)])
        command += ["--sign", identity, "--keychain", str(keychain)]
        persistent = True
    elif args.allow_ad_hoc:
        command += ["--sign", "-"]
        persistent = False
    else:
        raise SystemExit("No local signing identity configured; ad-hoc fallback was not requested")

    run(command + [str(args.app)])
    run(["codesign", "--verify", "--deep", "--strict", str(args.app)])
    requirement = run(["codesign", "-d", "-r-", str(args.app)])
    if persistent and ("certificate" not in requirement or "designated => cdhash" in requirement):
        raise SystemExit("Signature did not retain a certificate-based identity")
    print("Signed and verified with persistent local identity" if persistent else
          "Signed and verified ad hoc; updates can require Keychain approval again")


if __name__ == "__main__":
    main()
