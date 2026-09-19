#!/bin/bash
set -e

ELF="$1"
SIG_FILE="$2"
DUT_EXE="$3"
BIN2HEX="$4"

if [ -z "$ELF" ] || [ -z "$SIG_FILE" ] || [ -z "$DUT_EXE" ] || [ -z "$BIN2HEX" ]; then
    echo "Usage: run_dut.sh <elf_file> <sig_file> <dut_exe> <bin2hex_script>"
    exit 1
fi

# 1. Convert ELF to binary
riscv64-unknown-elf-objcopy -O binary "$ELF" my.bin

# 2. Convert binary to hex
python3 "$BIN2HEX" my.bin my.hex

# 3. Extract symbols
TOHOST=$(riscv64-unknown-elf-nm "$ELF" | grep " tohost$" | awk '{print "0x"$1}')
SIG_START=$(riscv64-unknown-elf-nm "$ELF" | grep " begin_signature$" | awk '{print "0x"$1}')
SIG_END=$(riscv64-unknown-elf-nm "$ELF" | grep " end_signature$" | awk '{print "0x"$1}')

if [ -z "$TOHOST" ] || [ -z "$SIG_START" ] || [ -z "$SIG_END" ]; then
    echo "[ERROR] Missing required symbols in $ELF"
    exit 1
fi

# 4. Run DUT simulation
"$DUT_EXE" my.hex --tohost "$TOHOST" --signature "$SIG_FILE" --sig-start "$SIG_START" --sig-end "$SIG_END" --quiet
