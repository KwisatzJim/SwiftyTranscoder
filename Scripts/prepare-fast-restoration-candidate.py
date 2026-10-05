"""Prepare a research-only compact AI candidate; does not change bundled models.

Run with .build/restoration-evaluation/venv/bin/python. Uses official general-x4v3
weights and the already pinned converter's SRVGG implementation. Average pooling
reduces its native 4x result to the app's existing 2x tensor contract.
"""
import hashlib
import importlib.util
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / ".build/restoration-evaluation"
WORK = RESEARCH / "fast-candidate"
WEIGHTS = WORK / "realesr-general-x4v3.pth"
CONVERTER = RESEARCH / "downloads/convert-88b473f383bd69e0e52ea1f266e6585c4fab34bf.py"

def verify(path, expected):
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(f"Checksum mismatch: {path}")

verify(WEIGHTS, "8dc7edb9ac80ccdc30c3a5dca6616509367f05fbc184ad95b731f05bece96292")
verify(CONVERTER, "152404e3021958c6e51edcde9fd17f2757ccf15f0e0d4e5c485495fd852b4af4")
spec = importlib.util.spec_from_file_location("pinned_converter", CONVERTER)
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)
network = converter.build_torch_srvgg(num_conv=32, upscale=4)
checkpoint = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
network.load_state_dict(checkpoint.get("params_ema", checkpoint.get("params", checkpoint)), strict=True)
network.eval()

class TwoTimes(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.network = network

    def forward(self, image):
        return torch.nn.functional.avg_pool2d(self.network(image), 2)

torch.set_num_threads(4)
wrapped = TwoTimes().eval()
example = torch.zeros(1, 3, 522, 522)
with torch.no_grad():
    traced = torch.jit.trace(wrapped, example)
model = ct.convert(
    traced, inputs=[ct.TensorType(name="input", shape=example.shape, dtype=np.float16)],
    outputs=[ct.TensorType(name="output", dtype=np.float16)],
    compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.macOS14,
)
destination = WORK / "RealESRGAN_general_x2_522_fp16.mlpackage"
model.short_description = "Research compact general-x4v3 AI, averaged to 2x; not yet approved for release"
model.save(str(destination))
print(destination, flush=True)
