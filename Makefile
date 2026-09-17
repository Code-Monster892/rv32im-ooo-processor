# ==============================================================================
# 2-Way Superscalar Out-of-Order RV32IM CPU Makefile
# ==============================================================================

# Toolchain Configuration
CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
CFLAGS  = -march=rv32im -mabi=ilp32 -O3 -T sw/link.ld -nostartfiles -nostdlib

# Source Directories & Files
RTL_DIR  = rtl
SIM_DIR  = sim
SW_DIR   = sw

RTL_SRCS = $(RTL_DIR)/pipeline_types.sv $(filter-out $(RTL_DIR)/pipeline_types.sv, $(wildcard $(RTL_DIR)/*.sv))
SIM_SRCS = $(SIM_DIR)/memory.sv
TB_CPP   = $(SIM_DIR)/main.cpp
SW_SRCS  = $(SW_DIR)/crt0.s $(SW_DIR)/main.c

.PHONY: all clean software sim

all: software sim

# 1. Compile Bare-Metal C + Assembly firmware and generate firmware.hex
software:
	@echo "--- Compiling Bare-Metal Firmware (sw/main.c) ---"
	$(CC) $(CFLAGS) $(SW_SRCS) -o prog.elf
	@echo "--- Extracting Raw Machine Binary ---"
	$(OBJCOPY) -O binary prog.elf prog.bin
	@echo "--- Converting Binary to Verilog firmware.hex ---"
	python3 -c "import sys; b=sys.stdin.buffer.read(); b += b'\x00' * ((4 - len(b) % 4) % 4); print('\n'.join(b[i:i+4][::-1].hex() for i in range(0,len(b),4)))" < prog.bin > firmware.hex
	@echo "firmware.hex successfully generated!"

# 2. Build and run Verilator simulation
sim: software
	@echo "--- Compiling CPU with Verilator ---"
	verilator -Wall -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-EOFNEWLINE \
		-Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE \
		-Wno-SYNCASYNCNET -Wno-PINMISSING -Wno-PINCONNECTEMPTY -Wno-MODDUP -Wno-IMPORTSTAR \
		-I$(RTL_DIR) -I$(SIM_DIR) --cc $(RTL_SRCS) $(SIM_SRCS) --exe $(TB_CPP) \
		--top-module cpu --build -j 0
	@echo "--- Running Headless Simulation ---"
	./obj_dir/Vcpu

clean:
	rm -rf obj_dir waveform.vcd prog.elf prog.bin game.elf game.bin firmware.hex


