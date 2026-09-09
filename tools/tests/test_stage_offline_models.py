import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("stager", Path(__file__).parents[1] / "stage_offline_models.py")
stager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stager)

class OfflineStageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for model, revision in stager.MODELS.items():
            folder = self.root / model.replace("/", "--")
            folder.mkdir()
            (folder / "weight").write_bytes(b"test")
            (folder / stager.MANIFEST).write_text(json.dumps({"modelID": model, "revision": revision,
                "files": [{"path": "weight", "bytes": 4, "sha256": hashlib.sha256(b"test").hexdigest()}]}))
        self.first = self.root / next(iter(stager.MODELS)).replace("/", "--")

    def tearDown(self):
        self.temp.cleanup()

    def test_all_models_verify(self):
        self.assertEqual(stager.verify(self.root), 4 * len(stager.MODELS))

    def test_same_length_corruption_rejected(self):
        (self.first / "weight").write_bytes(b"fail")
        with self.assertRaises(ValueError): stager.verify(self.root)

    def test_missing_model_rejected(self):
        (self.first / stager.MANIFEST).unlink()
        with self.assertRaises(FileNotFoundError): stager.verify(self.root)

    def test_extra_stale_weight_rejected(self):
        (self.first / "unexpected.safetensors").write_bytes(b"old")
        with self.assertRaises(ValueError): stager.verify(self.root)

    def test_unsafe_path_rejected(self):
        for path in ["../private", "/private", "nested/../../private", ""]:
            self.assertFalse(stager.safe_path(path))

if __name__ == "__main__": unittest.main()
