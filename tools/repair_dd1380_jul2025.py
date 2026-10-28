#!/usr/bin/env python3
"""Repair the official DD Form 1380 JUL 2025 PDF from esd.whs.mil so every reader can draw it.

What is wrong with the published file (SHA-256 2e5df8d7...f633523, checked 2026-10-28):
it is AES-encrypted with an empty open password, and after encryption it was
"optimized" (linearized), which renumbered objects. AES keys are per object
number, so 493 of 1,438 encrypted objects decrypt to garbage in Apple PDFKit,
poppler and PDFium: blank pages, scrambled field names. This tool finds each
object's original number (shifts of 1795, 1457, 243 and a few others), decrypts
it with the right key and writes a plain copy. Apple PDFKit still draws that
copy blank; `pdftocairo -pdf repaired.pdf vector.pdf` gives artwork PDFKit
draws correctly (no fields). The repaired copy keeps the form's own widgets:
305 fields with honest names (form1[0].P1[0].info[0].male[0], ...).

Run (tool-only dependencies, never shipped):
    uv run --python 3.12 --with pypdf --with cryptography python -I \
        tools/repair_dd1380_jul2025.py ~/Desktop/dd1380-2025.pdf /tmp/dd1380_jul2025_repaired.pdf
"""
import sys, copy, zlib, hashlib, collections
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from pypdf import PdfReader, PdfWriter
from pypdf import _encryption as E
from pypdf.errors import PdfStreamError
from pypdf.generic import StreamObject, DictionaryObject, ArrayObject, ByteStringObject, TextStringObject

src, out = sys.argv[1], sys.argv[2]
stats = collections.Counter(); fixes = {}
orig = E.Encryption.decrypt_object
MAXN = 4400

def leaves(o):
    if isinstance(o, StreamObject):
        yield o._data
        for v in o.values(): yield from leaves(v)
    elif isinstance(o, (ByteStringObject, TextStringObject)): yield o.original_bytes
    elif isinstance(o, DictionaryObject):
        for v in o.values(): yield from leaves(v)
    elif isinstance(o, ArrayObject):
        for v in o: yield from leaves(v)

def flate_ok(o):
    if isinstance(o, StreamObject):
        f = o.get("/Filter"); names = list(f) if isinstance(f, ArrayObject) else [f]
        if names and names[0] == "/FlateDecode":
            try: zlib.decompressobj().decompress(o._data)
            except Exception: return False
    return True

def try_n(self, obj, n, gen):
    trial = copy.deepcopy(obj)
    try: res = self._make_crypt_filter(n, gen).decrypt_object(trial, strict=True)
    except PdfStreamError: return None
    return res if flate_ok(res) else None

def pad_ok(key, ct):
    if len(ct) < 32 or len(ct) % 16: return False
    d = Cipher(algorithms.AES(key), modes.CBC(ct[-32:-16])).decryptor()
    b = d.update(ct[-16:]); p = b[-1]
    return 1 <= p <= 16 and b.endswith(bytes([p])*p)

def patched(self, obj, idnum, generation, *, strict=True):
    if not self._is_encryption_object(obj): return obj
    ls = [l for l in leaves(obj) if len(l) >= 32]
    if not ls: return orig(self, obj, idnum, generation, strict=False)
    cands = [idnum, idnum - 1795]
    for n in cands:
        if n > 0 and (res := try_n(self, obj, n, generation)) is not None:
            stats["own" if n == idnum else "-1795"] += 1; return res
    # search: object key = md5(filekey + n + gen + sAlT)
    fk = self._key if hasattr(self, "_key") else None
    longest = max(ls, key=len)
    for n in range(1, MAXN):
        k = hashlib.md5(fk + n.to_bytes(3, "little") + generation.to_bytes(2, "little") + b"sAlT").digest()[:16]
        if pad_ok(k, longest) and (res := try_n(self, obj, n, generation)) is not None:
            stats["searched"] += 1; fixes[idnum] = n; return res
    stats["unrepaired"] += 1
    return orig(self, obj, idnum, generation, strict=False)

E.Encryption.decrypt_object = patched
r = PdfReader(src, strict=False)
r.decrypt("")
assert getattr(r._encryption, "_key", None), "no file key"
w = PdfWriter(clone_from=r)
w.write(out)
print("objects:", dict(stats))
offs = collections.Counter(i - n for i, n in fixes.items()); print("searched offsets:", offs.most_common(8))
