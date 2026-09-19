#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: bin2hex.py <input.bin> <output.hex>")
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        b = f.read()
    rem = len(b) % 4
    if rem != 0:
        b += b'\x00' * (4 - rem)
    with open(sys.argv[2], 'w') as f:
        for i in range(0, len(b), 4):
            word = b[i:i+4][::-1].hex()
            f.write(word + '\n')

if __name__ == '__main__':
    main()
