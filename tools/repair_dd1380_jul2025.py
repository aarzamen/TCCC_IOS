#!/usr/bin/env python3
"""Repair a damaged copy of the official DD Form 1380 JUL 2025 PDF so every reader can draw it.

What is wrong with the copy (SHA-256 2e5df8d7...f633523, checked 2026-10-28):
it is AES-encrypted with an empty open password, and its encrypted objects
were renumbered after encryption. AES keys are per object number, so 493 of
1,438 objects decrypt to garbage in Apple PDFKit, poppler and PDFium: blank
pages, scrambled field names. Its metadata says it was last written by macOS
Quartz on 2026-10-27 22:16, so a Mac re-save probably did the damage; whether
the file served by esd.whs.mil has the same fault is not checked. This tool
finds each object's original number (shifts of 1795, 1457, 243 and a few
others), decrypts it with the right key and writes a plain copy: both pages
as published and the form's own 305 widgets with honest names
(form1[0].P1[0].info[0].male[0], ...). Apple PDFKit draws the repaired copy.

Run (tool-only dependencies, never shipped):
    uv run --python 3.12 --with pypdf --with cryptography python -I \
        tools/repair_dd1380_jul2025.py ~/Desktop/dd1380-2025.pdf /tmp/dd1380_jul2025_repaired.pdf
"""
import collections
import copy
import hashlib
import sys
import zlib
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from pypdf import PdfReader, PdfWriter
from pypdf import _encryption
from pypdf.errors import PdfStreamError
from pypdf.generic import ArrayObject, ByteStringObject, DictionaryObject, StreamObject, TextStringObject

SOURCE_SHA256 = "2e5df8d75f8dfcc0fa17ac8b70c4493c1f26c9866e733192919bb4918f633523"
# Most moved objects shifted by this much; the rest are found by search.
COMMON_SHIFT = 1795
MAX_OBJECT_NUMBER = 4400


def _leaves(obj):
    """Every encrypted byte string inside an object (stream data and strings)."""
    if isinstance(obj, StreamObject):
        yield obj._data
        for value in obj.values():
            yield from _leaves(value)
    elif isinstance(obj, (ByteStringObject, TextStringObject)):
        yield obj.original_bytes
    elif isinstance(obj, DictionaryObject):
        for value in obj.values():
            yield from _leaves(value)
    elif isinstance(obj, ArrayObject):
        for value in obj:
            yield from _leaves(value)


def _flate_ok(obj):
    if isinstance(obj, StreamObject):
        filters = obj.get("/Filter")
        names = list(filters) if isinstance(filters, ArrayObject) else [filters]
        if names and names[0] == "/FlateDecode":
            try:
                zlib.decompressobj().decompress(obj._data)
            except zlib.error:
                return False
    return True


def _padding_ok(key, ciphertext):
    """Cheap pre-check: does the last AES block end in valid PKCS#7 padding under this key?"""
    if len(ciphertext) < 32 or len(ciphertext) % 16:
        return False
    block = Cipher(algorithms.AES(key), modes.CBC(ciphertext[-32:-16])).decryptor().update(ciphertext[-16:])
    pad = block[-1]
    return 1 <= pad <= 16 and block.endswith(bytes([pad]) * pad)


def repair(source: Path, out: Path) -> collections.Counter:
    """Write a decrypted, readable copy of `source` to `out`. Returns how each object was keyed."""
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError(f"source SHA-256 {digest} is not the inspected DD 1380 JUL 2025 ({SOURCE_SHA256})")
    stats = collections.Counter()
    original = _encryption.Encryption.decrypt_object

    def decrypt_trial(self, obj, number, generation):
        trial = copy.deepcopy(obj)
        try:
            result = self._make_crypt_filter(number, generation).decrypt_object(trial, strict=True)
        except PdfStreamError:
            return None
        return result if _flate_ok(result) else None

    def decrypt_object(self, obj, idnum, generation, *, strict=True):
        if not self._is_encryption_object(obj):
            return obj
        leaves = [leaf for leaf in _leaves(obj) if len(leaf) >= 32]
        if not leaves:
            return original(self, obj, idnum, generation, strict=False)
        for number, label in ((idnum, "own number"), (idnum - COMMON_SHIFT, f"shift {COMMON_SHIFT}")):
            if number > 0 and (result := decrypt_trial(self, obj, number, generation)) is not None:
                stats[label] += 1
                return result
        longest = max(leaves, key=len)
        for number in range(1, MAX_OBJECT_NUMBER):
            key = hashlib.md5(self._key + number.to_bytes(3, "little") + generation.to_bytes(2, "little")
                              + b"sAlT").digest()[:16]
            if _padding_ok(key, longest) and (result := decrypt_trial(self, obj, number, generation)) is not None:
                stats["searched"] += 1
                return result
        stats["unrepaired"] += 1
        return original(self, obj, idnum, generation, strict=False)

    _encryption.Encryption.decrypt_object = decrypt_object
    try:
        reader = PdfReader(source, strict=False)
        reader.decrypt("")
        writer = PdfWriter(clone_from=reader)
    finally:
        _encryption.Encryption.decrypt_object = original
    if stats["unrepaired"]:
        raise ValueError(f"{stats['unrepaired']} objects could not be repaired")
    with out.open("wb") as stream:
        writer.write(stream)
    return stats


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    try:
        stats = repair(Path(sys.argv[1]).expanduser(), Path(sys.argv[2]).expanduser())
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"repaired {sum(stats.values())} encrypted objects: {dict(stats)}")


if __name__ == "__main__":
    main()
