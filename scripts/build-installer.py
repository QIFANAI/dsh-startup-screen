#!/usr/bin/env python3
"""构建 dsh-startup-screen 一键安装包（zip）。

产物：
  releases/dsh-startup-screen-<版本>-installer.zip
  releases/dsh-startup-screen-<版本>-installer.zip.sha256
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "package"
ASSETS = ROOT / "installer"
BUILD = ROOT / "_installer_build"
RELEASES = ROOT / "releases"

ASSET_FILES = [
    "AGENTS.md",
    "README.md",
    "VERSION.txt",  # 由本脚本生成，占位说明；实际写入在 staging
    "common.ps1",
    "install.ps1",
    "verify.ps1",
    "uninstall.ps1",
    "安装.cmd",
    "INSTALL.cmd",
    "验收.cmd",
    "VERIFY.cmd",
    "卸载.cmd",
    "UNINSTALL.cmd",
    "LICENSE",
    "THIRD-PARTY-NOTICES.md",
]


def run(cmd: str, cwd: Path) -> None:
    print("+", cmd)
    subprocess.run(cmd, cwd=str(cwd), shell=True, check=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest = json.loads((PKG / "package.json").read_text(encoding="utf-8"))
    version = manifest["version"]
    name = f"dsh-startup-screen-{version}-installer"
    staging = BUILD / name

    root_resolved = ROOT.resolve()
    build_resolved = BUILD.resolve()
    staging_resolved = staging.resolve()
    if root_resolved not in build_resolved.parents and build_resolved != root_resolved:
        raise SystemExit(f"构建目录不在仓库内：{build_resolved}")
    if build_resolved not in staging_resolved.parents:
        raise SystemExit(f"暂存目录不在构建目录内：{staging_resolved}")

    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    npm = shutil.which("npm")
    if not npm:
        raise SystemExit("找不到 npm。请先安装 Node.js 20+ 并把 npm 放进 PATH。")

    run(f'"{npm}" pack --pack-destination "{staging}"', PKG)
    tarballs = sorted(staging.glob("dsh-startup-screen-*.tgz"))
    if not tarballs:
        raise SystemExit("npm pack 没有生成 tgz。")
    tarball = tarballs[-1]

    for filename in ASSET_FILES:
        if filename == "VERSION.txt":
            continue
        source = ASSETS / filename
        if not source.is_file():
            raise SystemExit(f"缺少安装器文件：{source}")
        shutil.copy2(source, staging / filename)

    digest = sha256(tarball)
    version_text = (
        f"dsh-startup-screen {version} 一键安装包\n"
        f"构建时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"插件包：{tarball.name}\n"
        f"SHA256：{digest}\n"
    )
    (staging / "VERSION.txt").write_text(version_text, encoding="utf-8")

    RELEASES.mkdir(parents=True, exist_ok=True)
    zip_path = RELEASES / f"{name}.zip"
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(staging.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(BUILD).as_posix())

    zip_digest = sha256(zip_path)
    (RELEASES / f"{name}.zip.sha256").write_text(
        f"{zip_digest}  {zip_path.name}\n", encoding="ascii"
    )

    print()
    print(f"[OK] {zip_path}")
    print(f"     {zip_path.stat().st_size:,} bytes")
    print(f"     sha256 {zip_digest}")
    print(f"     tgz    {tarball.name} (sha256 {digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())