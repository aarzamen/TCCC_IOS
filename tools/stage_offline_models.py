#!/usr/bin/env python3
"""Stage model-only files for an offline app build. No network unless --download.
Run in a Python 3.12 uv venv with huggingface_hub installed for downloads.
Default stage directory must be outside Git; SHA-256 manifests accompany all files.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

MODELS = {
    "mlx-community/LFM2-1.2B-4bit": "3843e4ad0fcb8b7ed8a050908ac8f0bb5320d1bf",
    "mlx-community/Qwen3-1.7B-4bit": "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
    "mlx-community/granite-4.0-h-1b-base-4bit": "c31361138fab2f0725a796f5fc50097a820759f1",
    "mlx-community/granite-4.0-1b-speech-5bit": "371e6922faffba916e983e9c083049ad44536e94",
    "FluidInference/parakeet-realtime-eou-120m-coreml": "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
    "FluidInference/kokoro-82m-coreml": "acac8811a9acefe8bf7a5e3fcba99bd8fc50dcd6",
}
PARAKEET = "FluidInference/parakeet-realtime-eou-120m-coreml"
KOKORO = "FluidInference/kokoro-82m-coreml"
KOKORO_DIRS = {"kokoro_21_5s.mlmodelc", "kokoro_21_15s.mlmodelc", "G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc"}
COREML_DIRS = {"streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc"}
MANIFEST = "asset-manifest.json"
LICENSE_URLS = {
    "mlx-community/LFM2-1.2B-4bit": "https://huggingface.co/LiquidAI/LFM2-1.2B/raw/main/LICENSE",
    "mlx-community/Qwen3-1.7B-4bit": "https://www.apache.org/licenses/LICENSE-2.0.txt",
    "mlx-community/granite-4.0-h-1b-base-4bit": "https://www.apache.org/licenses/LICENSE-2.0.txt",
    "mlx-community/granite-4.0-1b-speech-5bit": "https://www.apache.org/licenses/LICENSE-2.0.txt",
    PARAKEET: "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/",
    KOKORO: "https://www.apache.org/licenses/LICENSE-2.0.txt",
}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def safe_path(path):
    return bool(path) and not Path(path).is_absolute() and ".." not in Path(path).parts


def verify(root):
    total = 0
    for model, revision in MODELS.items():
        folder = root / model.replace("/", "--")
        manifest = json.loads((folder / MANIFEST).read_text())
        if manifest["modelID"] != model or manifest["revision"] != revision or not manifest["files"]:
            raise ValueError(f"Wrong identity, revision or empty manifest: {folder}")
        declared = {item["path"] for item in manifest["files"]}
        actual = {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file() and p.name != MANIFEST}
        if declared != actual or len(declared) != len(manifest["files"]):
            raise ValueError(f"Unlisted, duplicate or missing files: {folder}")
        for item in manifest["files"]:
            if not safe_path(item["path"]):
                raise ValueError("Unsafe manifest path")
            path = folder / item["path"]
            if not path.is_file() or path.stat().st_size != item["bytes"] or digest(path) != item["sha256"]:
                raise ValueError(f"Missing, truncated or corrupt asset: {path}")
            total += item["bytes"]
    return total


def stage(source_root, destination, download):
    repository = Path(__file__).resolve().parents[1]
    if destination.resolve().is_relative_to(repository) or source_root.resolve().is_relative_to(repository):
        raise ValueError("Model sources and staged weights must live outside the source repository")
    if destination.exists():
        raise ValueError(f"Destination exists; use --verify or choose a new path: {destination}")
    if download:
        from huggingface_hub import snapshot_download, HfApi
    pending = destination.with_name(destination.name + ".preparing")
    pending.mkdir(parents=True, exist_ok=True)
    for model, revision in MODELS.items():
        source = source_root / model.replace("/", "--")
        if download:
            # All files at the exact pinned revision; only 160ms is offered by the app.
            patterns = [f"160ms/{name}/**" for name in COREML_DIRS] + ["160ms/vocab.json", "README.md", "LICENSE*", "NOTICE*"] if model == PARAKEET else None
            if model == KOKORO:
                patterns = [f"{name}/**" for name in KOKORO_DIRS] + ["*.json", "voices/*.json", "README.md", "LICENSE*", "NOTICE*"]
            snapshot_download(model, revision=revision, local_dir=source, allow_patterns=patterns)
            # Verify against upstream LFS SHA-256 / Git blob identities, not just our own copy.
            info = HfApi().model_info(model, revision=revision, files_metadata=True)
            for sibling in info.siblings:
                if model == PARAKEET and not (sibling.rfilename == "160ms/vocab.json"
                    or any(sibling.rfilename.startswith(f"160ms/{name}/") for name in COREML_DIRS)
                    or sibling.rfilename == "README.md" or sibling.rfilename.startswith(("LICENSE", "NOTICE"))):
                    continue
                if model == KOKORO and not (sibling.rfilename.split("/")[0] in KOKORO_DIRS
                    or sibling.rfilename.startswith("voices/") and sibling.rfilename.endswith(".json")
                    or "/" not in sibling.rfilename and (sibling.rfilename.endswith((".json", ".md")) or sibling.rfilename.startswith(("LICENSE", "NOTICE")))):
                    continue
                local = source / sibling.rfilename
                if not local.is_file():
                    if model != PARAKEET or sibling.rfilename.startswith("160ms/"):
                        raise ValueError(f"Download incomplete: {sibling.rfilename}")
                    continue
                if sibling.lfs:
                    if digest(local) != sibling.lfs.sha256:
                        raise ValueError(f"Upstream checksum mismatch: {local}")
                elif sibling.blob_id:
                    data = local.read_bytes()
                    if hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() != sibling.blob_id:
                        raise ValueError(f"Upstream Git blob mismatch: {local}")
        asset_source = source / "160ms" if model == PARAKEET else source
        if not asset_source.is_dir():
            raise ValueError(f"Missing source folder: {asset_source}; use --download during preparation")
        folder = pending / model.replace("/", "--")
        folder.mkdir(exist_ok=True)
        files = []
        for path in sorted(asset_source.rglob("*")):
            relative = path.relative_to(asset_source)
            if not path.is_file() or any(part.startswith(".") for part in relative.parts):
                continue
            if model == PARAKEET and relative.parts[0] not in COREML_DIRS | {"vocab.json"}:
                continue
            if model == KOKORO and not (relative.parts[0] in KOKORO_DIRS | {"voices"}
                or len(relative.parts) == 1 and (path.suffix in {".json", ".md"} or path.name.startswith(("LICENSE", "NOTICE")))):
                continue
            # Stage inference resources and upstream notice/model-card files only.
            if model not in {PARAKEET, KOKORO} and not (path.suffix in {".json", ".safetensors", ".model", ".txt", ".jinja", ".md"} or path.name.startswith(("LICENSE", "NOTICE"))):
                continue
            target = folder / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target, follow_symlinks=True)
            files.append({"path": relative.as_posix(), "bytes": target.stat().st_size, "sha256": digest(target)})
        if model == PARAKEET:
            for path in sorted(source.iterdir()):
                if path.is_file() and (path.name == "README.md" or path.name.startswith(("LICENSE", "NOTICE"))):
                    shutil.copyfile(path, folder / path.name)
                    files.append({"path": path.name, "bytes": path.stat().st_size, "sha256": digest(path)})
        license_name = "UPSTREAM-LICENSE.html" if model == PARAKEET else "UPSTREAM-LICENSE.txt"
        license_source = source / license_name
        if download:
            request = urllib.request.Request(LICENSE_URLS[model], headers={"User-Agent": "TCCC-offline-model-staging/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                license_source.write_bytes(response.read())
        if not license_source.is_file() or license_source.stat().st_size < 100:
            raise ValueError(f"Missing upstream license: {license_source}; rerun with --download")
        shutil.copyfile(license_source, folder / license_name)
        # External notices may already have been included on a local restage.
        files = [item for item in files if item["path"] != license_name]
        files.append({"path": license_name, "bytes": license_source.stat().st_size, "sha256": digest(license_source)})
        if model == PARAKEET:
            notice = folder / "Notice.txt"
            notice.write_text("Licensed by NVIDIA Corporation under the NVIDIA Open Model License\n")
            files = [item for item in files if item["path"] != "Notice.txt"]
            files.append({"path": "Notice.txt", "bytes": notice.stat().st_size, "sha256": digest(notice)})
        (folder / MANIFEST).write_text(json.dumps({"schemaVersion": 1, "modelID": model,
            "revision": revision, "source": f"https://huggingface.co/{model}/tree/{revision}",
            "upstreamVerified": download, "licenseSource": LICENSE_URLS[model], "files": files}, indent=2) + "\n")
        print(f"Staged {model}: {sum(f['bytes'] for f in files):,} bytes", flush=True)
    total = verify(pending)
    pending.rename(destination)
    print(f"Verified offline package: {destination} ({total:,} bytes)", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download", action="store_true", help="Explicitly authorize public model downloads")
    parser.add_argument("--verify", action="store_true", help="Read-only SHA-256 verification; never uses network")
    args = parser.parse_args()
    if args.verify:
        print(f"Verified {verify(args.output):,} asset bytes")
    elif args.sources is None:
        parser.error("--sources required for staging")
    else:
        stage(args.sources, args.output, args.download)


if __name__ == "__main__":
    main()
