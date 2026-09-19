#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/verification/build"
ENV_DIR="$ROOT_DIR/verification/env"
ISA_DIR="$ROOT_DIR/riscv-tests/isa"
VCPU="$ROOT_DIR/obj_dir/Vcpu"
BIN2HEX="$ROOT_DIR/verification/bin2hex.py"

mkdir -p "$BUILD_DIR/ui"
mkdir -p "$BUILD_DIR/um"

# Ensure Vcpu binary exists
if [ ! -f "$VCPU" ]; then
    echo "--- Building Verilator Vcpu simulator ---"
    make -C "$ROOT_DIR"
fi

CC="riscv64-unknown-elf-gcc"
OBJCOPY="riscv64-unknown-elf-objcopy"
NM="riscv64-unknown-elf-nm"
CFLAGS="-march=rv32im_zifencei -mabi=ilp32 -static -nostdlib -nostartfiles -I$ENV_DIR -T$ENV_DIR/link.ld"

UI_TESTS=(
    add addi sub
    and andi or ori xor xori
    sll slli srl srli sra srai
    slt slti sltu sltiu
    lui auipc
    jal jalr
    beq bne blt bge bltu bgeu
    lw sw lh sh lhu lb sb lbu
    fence_i
)

UM_TESTS=(
    mul mulh mulhsu mulhu
    div divu rem remu
)

passed_count=0
failed_count=0
total_count=0

echo "========================================================"
echo "    RISC-V 2-Way OoO Core Official Test Suite Regression "
echo "========================================================"
echo ""

echo ">>> [1/2] Running RV32UI (Base Integer & ALU) Test Suite..."
for test in "${UI_TESTS[@]}"; do
    total_count=$((total_count + 1))
    src="$ISA_DIR/rv32ui/$test.S"
    elf="$BUILD_DIR/ui/$test.elf"
    bin="$BUILD_DIR/ui/$test.bin"
    hex="$BUILD_DIR/ui/$test.hex"
    tohost_file="$hex.tohost"
    sig_start_file="$hex.sig_start"
    sig_end_file="$hex.sig_end"
    sig_out="$BUILD_DIR/ui/$test.sig"

    # Compile
    $CC $CFLAGS "$src" -o "$elf" 2>/dev/null
    $OBJCOPY -O binary "$elf" "$bin"
    python3 "$BIN2HEX" "$bin" "$hex"

    # Extract symbol addresses
    tohost_addr=$($NM "$elf" | grep ' tohost$' | awk '{print "0x" $1}')
    sig_start=$($NM "$elf" | grep ' begin_signature$' | awk '{print "0x" $1}')
    sig_end=$($NM "$elf" | grep ' end_signature$' | awk '{print "0x" $1}')

    echo "$tohost_addr" > "$tohost_file"
    echo "$sig_start" > "$sig_start_file"
    echo "$sig_end" > "$sig_end_file"

    # Execute on Verilator Harness
    printf "  %-12s ... " "$test"
    set +e
    out=$("$VCPU" "$hex" --quiet --signature "$sig_out" 2>&1)
    res=$?
    set -e

    if [ $res -eq 0 ]; then
        echo "[PASS]"
        passed_count=$((passed_count + 1))
    else
        echo "[FAIL] ($out)"
        failed_count=$((failed_count + 1))
    fi
done

echo ""
echo ">>> [2/2] Running RV32UM (Hardware Multiply & Divide) Test Suite..."
for test in "${UM_TESTS[@]}"; do
    total_count=$((total_count + 1))
    src="$ISA_DIR/rv32um/$test.S"
    elf="$BUILD_DIR/um/$test.elf"
    bin="$BUILD_DIR/um/$test.bin"
    hex="$BUILD_DIR/um/$test.hex"
    tohost_file="$hex.tohost"
    sig_start_file="$hex.sig_start"
    sig_end_file="$hex.sig_end"
    sig_out="$BUILD_DIR/um/$test.sig"

    # Compile
    $CC $CFLAGS "$src" -o "$elf" 2>/dev/null
    $OBJCOPY -O binary "$elf" "$bin"
    python3 "$BIN2HEX" "$bin" "$hex"

    # Extract symbol addresses
    tohost_addr=$($NM "$elf" | grep ' tohost$' | awk '{print "0x" $1}')
    sig_start=$($NM "$elf" | grep ' begin_signature$' | awk '{print "0x" $1}')
    sig_end=$($NM "$elf" | grep ' end_signature$' | awk '{print "0x" $1}')

    echo "$tohost_addr" > "$tohost_file"
    echo "$sig_start" > "$sig_start_file"
    echo "$sig_end" > "$sig_end_file"

    # Execute on Verilator Harness
    printf "  %-12s ... " "$test"
    set +e
    out=$("$VCPU" "$hex" --quiet --signature "$sig_out" 2>&1)
    res=$?
    set -e

    if [ $res -eq 0 ]; then
        echo "[PASS]"
        passed_count=$((passed_count + 1))
    else
        echo "[FAIL] ($out)"
        failed_count=$((failed_count + 1))
    fi
done

echo ""
echo "========================================================"
echo "                   Regression Summary                   "
echo "========================================================"
echo "  Total Tests Run:  $total_count"
echo "  Passed:           $passed_count"
echo "  Failed:           $failed_count"
echo "  Total Failures:   $failed_count"
echo "========================================================"

if [ $failed_count -eq 0 ]; then
    echo ">>> ALL RISC-V SUITE TESTS PASSED WITH ZERO FAILURES! <<<"
    exit 0
else
    echo ">>> REGRESSION SUITE FAILED! <<<"
    exit 1
fi
