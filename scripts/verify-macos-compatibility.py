#!/usr/bin/env python3
"""Fail when an application bundle contains code newer than its advertised macOS floor."""

import plistlib
import re
import subprocess
import sys
from pathlib import Path


MACH_O_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


def version_tuple(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def is_mach_o(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    try:
        with path.open("rb") as source:
            return source.read(4) in MACH_O_MAGICS
    except OSError:
        return False


def minimum_versions(path: Path) -> list[str]:
    completed = subprocess.run(
        ["xcrun", "vtool", "-show-build", str(path)],
        capture_output=True, text=True, check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"cannot inspect {path}: {completed.stderr.strip()}")
    versions = re.findall(r"^\s*minos\s+(\d+(?:\.\d+)*)\s*$", completed.stdout, re.MULTILINE)
    if not versions:
        raise RuntimeError(f"{path} has no macOS build-version command")
    return versions


def verify(app: Path, expected: str) -> list[str]:
    failures: list[str] = []
    expected_version = version_tuple(expected)
    root_info = app / "Contents" / "Info.plist"

    try:
        with root_info.open("rb") as source:
            bundle_info = plistlib.load(source)
            advertised = bundle_info.get("LSMinimumSystemVersion")
    except (OSError, plistlib.InvalidFileException) as error:
        return [f"cannot read {root_info}: {error}"]

    if advertised != expected:
        failures.append(
            f"{root_info}: LSMinimumSystemVersion is {advertised!r}, expected {expected!r}"
        )

    executable_name = bundle_info.get("CFBundleExecutable")
    if executable_name:
        executable = app / "Contents" / "MacOS" / str(executable_name)
        if not is_mach_o(executable):
            failures.append(f"{executable}: declared executable is missing or is not Mach-O")

    for info_plist in app.rglob("Info.plist"):
        if info_plist == root_info:
            continue
        try:
            with info_plist.open("rb") as source:
                nested_minimum = plistlib.load(source).get("LSMinimumSystemVersion")
        except (OSError, plistlib.InvalidFileException) as error:
            failures.append(f"cannot read {info_plist}: {error}")
            continue
        if nested_minimum and version_tuple(str(nested_minimum)) > expected_version:
            failures.append(
                f"{info_plist}: requires macOS {nested_minimum}, newer than {expected}"
            )

    for candidate in app.rglob("*"):
        if not is_mach_o(candidate):
            continue
        try:
            versions = minimum_versions(candidate)
        except RuntimeError as error:
            failures.append(str(error))
            continue
        for minimum in versions:
            if version_tuple(minimum) > expected_version:
                failures.append(
                    f"{candidate}: Mach-O requires macOS {minimum}, newer than {expected}"
                )

    return failures


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {Path(sys.argv[0]).name} APP MINIMUM_MACOS", file=sys.stderr)
        return 2
    app = Path(sys.argv[1])
    expected = sys.argv[2]
    failures = verify(app, expected)
    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    print(f"{app} is compatible with macOS {expected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
