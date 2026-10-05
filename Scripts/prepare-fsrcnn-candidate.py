"""Research conversion of Apache-licensed Saafke FSRCNN x2 to the RGB tile contract.

Frozen graph constants are decoded without executing downloaded Python. The learned
network processes luminance; color differences are scaled bilinearly. This is a
lighter upscaler, not a replacement claim for Real-ESRGAN's restoration quality.
"""
import hashlib
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".build/restoration-evaluation/fsrcnn-candidate"
GRAPH = WORK / "FSRCNN_x2.pb"
if hashlib.sha256(GRAPH.read_bytes()).hexdigest() != "366b33f0084c7b3f2bf6724f0a2c77bca94fcec9d7b6d72389d330073b380d5c":
    raise ValueError("Unexpected FSRCNN frozen graph")
if hashlib.sha256((WORK / "LICENSE").read_bytes()).hexdigest() != "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4":
    raise ValueError("Unexpected FSRCNN license")

def varint(data, position):
    value, shift = 0, 0
    while shift < 70:
        byte = data[position]
        position += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, position
        shift += 7
    raise ValueError("Invalid protobuf varint")

def fields(data):
    position = 0
    while position < len(data):
        tag, position = varint(data, position)
        number, wire = tag >> 3, tag & 7
        if wire == 0:
            value, position = varint(data, position)
        elif wire in (1, 2, 5):
            if wire == 2:
                length, position = varint(data, position)
            else:
                length = 8 if wire == 1 else 4
            value = data[position:position + length]
            if len(value) != length:
                raise ValueError("Truncated protobuf field")
            position += length
        else:
            raise ValueError("Unsupported protobuf wire type")
        yield number, value

def get(data, number):
    return next(value for field, value in fields(data) if field == number)

def graph_constants():
    result = {}
    for field, node in fields(GRAPH.read_bytes()):
        if field != 1 or get(node, 2) != b"Const":
            continue
        name = get(node, 1).decode()
        for key, attr in fields(node):
            if key != 5 or get(attr, 1) != b"value":
                continue
            tensor = get(get(attr, 2), 8)
            if get(tensor, 1) != 1:  # TensorFlow DT_FLOAT
                continue
            shape = [get(dim, 1) for number, dim in fields(get(tensor, 2)) if number == 2]
            content = [value for number, value in fields(tensor) if number == 4]
            if content:
                array = np.frombuffer(content[0], dtype="<f4").copy()
            else:
                values = [value for number, value in fields(tensor) if number == 5]
                array = np.frombuffer(b"".join(values), dtype="<f4").copy()
            expected = int(np.prod(shape)) if shape else 1
            if array.size == 1 and expected > 1:
                array = np.repeat(array, expected)
            result[name] = array.reshape(shape)
    return result

class FSRCNN(torch.nn.Module):
    def __init__(self, constants):
        super().__init__()
        self.layers = torch.nn.ModuleList()
        for index in range(1, 9):
            weight = constants[f"f{index}"]
            kh, kw, inputs, outputs = weight.shape
            layer = torch.nn.Conv2d(inputs, outputs, (kh, kw), padding=(kh // 2, kw // 2), bias=index < 8)
            with torch.no_grad():
                layer.weight.copy_(torch.from_numpy(weight.transpose(3, 2, 0, 1).copy()))
                if index < 8:
                    layer.bias.copy_(torch.from_numpy(constants[f"b{index}"]))
            self.layers.append(layer)
            if index < 8:
                activation = torch.nn.PReLU(outputs)
                with torch.no_grad():
                    activation.weight.copy_(torch.from_numpy(constants[f"alpha{index}"]))
                self.layers.append(activation)
        self.register_buffer("output_bias", torch.from_numpy(constants["b8"]).reshape(1, 1, 1, 1))

    def forward(self, luminance):
        value = luminance
        for layer in self.layers:
            value = layer(value)
        return torch.nn.functional.pixel_shuffle(value, 2) + self.output_bias

class RGBWrapper(torch.nn.Module):
    def __init__(self, network):
        super().__init__()
        self.network = network

    def forward(self, image):
        red, green, blue = image[:, 0:1], image[:, 1:2], image[:, 2:3]
        luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        cr = torch.nn.functional.interpolate((red - luminance) * 0.713, scale_factor=2, mode="bilinear", align_corners=False)
        cb = torch.nn.functional.interpolate((blue - luminance) * 0.564, scale_factor=2, mode="bilinear", align_corners=False)
        restored = self.network(luminance)
        return torch.cat((restored + 1.403 * cr, restored - 0.714 * cr - 0.344 * cb, restored + 1.773 * cb), dim=1).clamp(0, 1)

def main():
    torch.set_num_threads(4)
    network = FSRCNN(graph_constants()).eval()
    # Independent parity check requires the pinned research OpenCV package.
    import cv2
    registration = cv2.dnn_superres.DnnSuperResImpl_create()
    frozen = cv2.dnn.readNetFromTensorflow(str(GRAPH))
    luminance = np.random.default_rng(111).random((1, 1, 64, 64), dtype=np.float32)
    frozen.setInput(luminance)
    original = frozen.forward()
    with torch.no_grad():
        reconstructed = network(torch.from_numpy(luminance)).numpy()
    parity = np.abs(original - reconstructed)
    assert original.shape == reconstructed.shape and float(parity.max()) < 0.0001
    print(f"Frozen graph/PyTorch mean difference {parity.mean()}, maximum {parity.max()}", flush=True)
    model = RGBWrapper(network).eval()
    example = torch.zeros(1, 3, 522, 522)
    with torch.no_grad():
        traced = torch.jit.trace(model, example)
    converted = ct.convert(
        traced, inputs=[ct.TensorType(name="input", shape=example.shape, dtype=np.float16)],
        outputs=[ct.TensorType(name="output", dtype=np.float16)],
        compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.macOS14,
    )
    destination = WORK / "FSRCNN_x2_RGB_522_fp16.mlpackage"
    converted.save(str(destination))
    generator = np.random.default_rng(111)
    sample = generator.random((1, 3, 522, 522), dtype=np.float32).astype(np.float16)
    with torch.no_grad():
        expected = model(torch.from_numpy(sample.astype(np.float32))).numpy()
    actual = converted.predict({"input": sample})["output"].astype(np.float32)
    difference = np.abs(actual - expected)
    assert actual.shape == (1, 3, 1044, 1044) and np.isfinite(actual).all()
    assert float(difference.mean()) < 0.003 and float(difference.max()) < 0.05
    print(f"Core ML/reference mean difference {difference.mean()}, maximum {difference.max()}", flush=True)
    print(destination, flush=True)

if __name__ == "__main__":
    main()
