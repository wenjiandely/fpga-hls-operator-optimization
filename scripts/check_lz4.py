"""Check the testbench's size-prefixed raw LZ4 block without dependencies."""
from pathlib import Path
import argparse
import struct


def decode_block(data):
    out = bytearray()
    pos = 0

    def length(initial):
        nonlocal pos
        value = initial
        if initial == 15:
            while True:
                if pos >= len(data):
                    raise ValueError("Truncated LZ4 length")
                item = data[pos]
                pos += 1
                value += item
                if item != 255:
                    break
        return value

    while pos < len(data):
        token = data[pos]
        pos += 1
        count = length(token >> 4)
        if pos + count > len(data):
            raise ValueError("Truncated literals")
        out.extend(data[pos:pos + count])
        pos += count
        if pos == len(data):
            break
        if pos + 2 > len(data):
            raise ValueError("Truncated offset")
        offset = int.from_bytes(data[pos:pos + 2], "little")
        pos += 2
        if not 0 < offset <= len(out):
            raise ValueError("Invalid match offset")
        count = length(token & 15) + 4
        for _ in range(count):
            out.append(out[-offset])
    return bytes(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("encoded", type=Path)
    args = parser.parse_args()
    packed = args.encoded.read_bytes()
    if len(packed) < 4:
        raise SystemExit("FAIL: missing size prefix")
    decoded = decode_block(packed[4:])
    original = args.original.read_bytes()
    if len(decoded) != struct.unpack("<I", packed[:4])[0] or decoded != original:
        raise SystemExit("FAIL: decoded data differs from input")
    print(f"PASS: {len(original)} bytes recovered from {len(packed) - 4} compressed bytes")
