#!/usr/bin/env python3
import sys

def bin2hex(bin_path, hex_path):
    with open(bin_path, "rb") as f:
        data = f.read()
    # Pad to 4-byte boundary
    pad = (4 - len(data) % 4) % 4
    data += b'\x00' * pad
    
    with open(hex_path, "w") as f:
        for i in range(0, len(data), 4):
            word = data[i:i+4]
            # Reverse for little-endian word representation in hex line
            f.write(word[::-1].hex() + "\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: bin2hex.py <input.bin> <output.hex>")
        sys.exit(1)
    bin2hex(sys.argv[1], sys.argv[2])
