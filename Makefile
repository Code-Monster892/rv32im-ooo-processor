# ==============================================================================
# 2-Way Superscalar Out-of-Order RV32IM CPU Makefile
# ==============================================================================

# Toolchain Configuration
CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
CFLAGS  = -march=rv32im -mabi=ilp32 -O3 -T sw/link.ld -nostartfiles -nostdlib -fno-builtin

# Source Directories & Files
RTL_DIR  = rtl
SIM_DIR  = sim
SW_DIR   = sw
APPS_DIR = apps

RTL_SRCS = $(RTL_DIR)/pipeline_types.sv $(filter-out $(RTL_DIR)/pipeline_types.sv, $(wildcard $(RTL_DIR)/*.sv))
SIM_SRCS = $(SIM_DIR)/memory.sv
TB_CPP   = $(SIM_DIR)/main.cpp
SW_SRCS  = $(SW_DIR)/crt0.s $(SW_DIR)/main.c

# Host SDL2 Configuration (Auto-detect GUI support)
SDL2_CFLAGS := $(shell sdl2-config --cflags 2>/dev/null || echo "")
SDL2_LIBS   := $(shell sdl2-config --libs 2>/dev/null || echo "")

.PHONY: all clean software sim donut sim-donut sim-donut-gui verilate

all: software sim

# 1. Compile Bare-Metal C + Assembly firmware and generate firmware.hex
software:
	@echo "--- Compiling Bare-Metal Baseline Firmware (sw/main.c) ---"
	$(CC) $(CFLAGS) $(SW_SRCS) -o prog.elf
	@echo "--- Extracting Raw Machine Binary ---"
	$(OBJCOPY) -O binary prog.elf prog.bin
	@echo "--- Converting Binary to Verilog firmware.hex ---"
	python3 -c "import sys; b=sys.stdin.buffer.read(); b += b'\x00' * ((4 - len(b) % 4) % 4); print('\n'.join(b[i:i+4][::-1].hex() for i in range(0,len(b),4)))" < prog.bin > firmware.hex
	@echo "firmware.hex successfully generated!"

# 2. Build Verilator Simulation Model
verilate:
	@echo "--- Compiling CPU with Verilator (-O3 optimized) ---"
	verilator -O3 -Wall -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-EOFNEWLINE \
		-Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE \
		-Wno-SYNCASYNCNET -Wno-PINMISSING -Wno-PINCONNECTEMPTY -Wno-MODDUP -Wno-IMPORTSTAR \
		-I$(RTL_DIR) -I$(SIM_DIR) --cc $(RTL_SRCS) $(SIM_SRCS) --exe $(TB_CPP) \
		-CFLAGS "-O3 $(SDL2_CFLAGS)" -LDFLAGS "$(SDL2_LIBS)" \
		--top-module cpu --build -j 0

# 3. Run Headless Baseline Simulation
sim: software verilate
	@echo "--- Running Headless Baseline Simulation ---"
	./obj_dir/Vcpu

# 4. Compile 3D Donut Graphics Engine Application
donut:
	@echo "--- Compiling 3D Donut Graphics Engine (apps/donut/donut3d.c) ---"
	$(CC) $(CFLAGS) $(SW_DIR)/crt0.s $(APPS_DIR)/donut/donut3d.c -o prog.elf -lgcc
	@echo "--- Extracting Raw Machine Binary ---"
	$(OBJCOPY) -O binary prog.elf prog.bin
	@echo "--- Converting Binary to Verilog firmware.hex ---"
	python3 -c "import sys; b=sys.stdin.buffer.read(); b += b'\x00' * ((4 - len(b) % 4) % 4); print('\n'.join(b[i:i+4][::-1].hex() for i in range(0,len(b),4)))" < prog.bin > firmware.hex
	@echo "firmware.hex successfully generated for 3D Donut!"

# 5. Run 3D Donut Headless Simulation (Captures frame to donut_frame.ppm)
sim-donut: donut verilate
	@echo "--- Running 3D Donut Headless Simulation (Capture 1st frame) ---"
	./obj_dir/Vcpu --cycles 3500000 --ppm donut_frame.ppm

# 6. Run 3D Donut Real-Time Interactive Simulation (Requires X11/GUI display)
sim-donut-gui: donut verilate
	@echo "--- Running 3D Donut Interactive Simulation (SDL2 Window) ---"
	./obj_dir/Vcpu --gui

clean:
	rm -rf obj_dir waveform.vcd prog.elf prog.bin game.elf game.bin firmware.hex *.ppm *.bmp



