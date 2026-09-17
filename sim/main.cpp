// Headless Command-Line C++ Verilator Testbench Driver with tohost & Signature Support
#include "Vcpu.h"
#include "Vcpu_cpu.h"
#include "Vcpu_memory.h"
#include "verilated.h"
#include <iostream>
#include <fstream>
#include <iomanip>
#include <string>
#include <cstdint>

static bool load_hex_file(Vcpu* dut, const std::string& hex_path) {
    std::ifstream infile(hex_path);
    if (!infile.is_open()) {
        std::cerr << "[TESTBENCH ERROR] Cannot open hex file: " << hex_path << std::endl;
        return false;
    }
    // Zero out memory
    for (size_t i = 0; i < 4194304; i++) {
        dut->cpu->mem_inst->mem[i] = 0;
    }
    std::string line;
    uint32_t word_addr = 0;
    while (std::getline(infile, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) {
            line.pop_back();
        }
        if (line.empty()) continue;
        if (line[0] == '@') {
            word_addr = std::stoul(line.substr(1), nullptr, 16) / 4;
        } else {
            uint32_t val = std::stoul(line, nullptr, 16);
            if (word_addr < 4194304) {
                dut->cpu->mem_inst->mem[word_addr++] = val;
            }
        }
    }
    return true;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vcpu* dut = new Vcpu;

    std::string hex_file = "firmware.hex";
    uint32_t tohost_addr = 0x1000;
    bool tohost_specified = false;
    std::string sig_file = "";
    uint32_t sig_start = 0;
    uint32_t sig_end = 0;
    uint64_t max_cycles = 500000;
    bool quiet = false;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--tohost" && i + 1 < argc) {
            tohost_addr = std::stoul(argv[++i], nullptr, 0);
            tohost_specified = true;
        } else if (arg == "--signature" && i + 1 < argc) {
            sig_file = argv[++i];
        } else if (arg == "--sig-start" && i + 1 < argc) {
            sig_start = std::stoul(argv[++i], nullptr, 0);
        } else if (arg == "--sig-end" && i + 1 < argc) {
            sig_end = std::stoul(argv[++i], nullptr, 0);
        } else if (arg == "--max-cycles" && i + 1 < argc) {
            max_cycles = std::stoull(argv[++i], nullptr, 0);
        } else if (arg == "--quiet" || arg == "-q") {
            quiet = true;
        } else if (arg[0] != '-') {
            hex_file = arg;
        }
    }

    // If tohost not explicitly specified, check for companion .tohost file
    if (!tohost_specified) {
        std::string companion = hex_file + ".tohost";
        std::ifstream cf(companion);
        if (cf.is_open()) {
            cf >> std::hex >> tohost_addr;
            tohost_specified = true;
        }
    }
    // Check companion signature bounds if not explicitly passed
    if (sig_start == 0 && sig_end == 0) {
        std::ifstream sf1(hex_file + ".sig_start");
        if (sf1.is_open()) sf1 >> std::hex >> sig_start;
        std::ifstream sf2(hex_file + ".sig_end");
        if (sf2.is_open()) sf2 >> std::hex >> sig_end;
    }

    dut->clk = 0;
    dut->rst_n = 0;
    dut->eval(); // Execute Verilog initial blocks first

    // Load hex file into RAM (overriding default initial memory)
    load_hex_file(dut, hex_file);

    if (!quiet) {
        std::cout << "[TESTBENCH] Running: " << hex_file << " (tohost=0x" 
                  << std::hex << tohost_addr << std::dec << ")" << std::endl;
    }

    uint64_t cycles = 0;
    int test_result = -1; // -1 = running, 0 = pass, >0 = fail testnum

    while (!Verilated::gotFinish() && cycles < max_cycles) {
        if (cycles == 5) {
            dut->rst_n = 1;
        }

        // Clock Low Phase (clk = 0)
        dut->clk = 0;
        dut->eval();

        // MMIO Timer Read
        dut->mmio_read_data = 0;
        if (dut->mmio_read_en) {
            if (dut->mmio_address == 0x02500000) {
                dut->mmio_read_data = (uint32_t)cycles;
            }
            dut->eval();
        }

        // MMIO Console UART
        if (dut->mmio_we && dut->mmio_address == 0x10000000) {
            char ch = (char)(dut->mmio_write_data & 0xFF);
            std::cout << ch << std::flush;
        }

        // Clock High Phase (clk = 1)
        dut->clk = 1;
        dut->eval();

        // Check tohost write in RAM (only when tohost monitoring is active)
        if (tohost_specified) {
            uint32_t tohost_word = tohost_addr / 4;
            if (tohost_word < 4194304) {
                uint32_t tohost_val = dut->cpu->mem_inst->mem[tohost_word];
                if (tohost_val != 0) {
                    if (tohost_val == 1) {
                        test_result = 0;
                    } else {
                        test_result = (int)(tohost_val >> 1);
                        if (test_result == 0) test_result = (int)tohost_val;
                    }
                    break;
                }
            }
        }

        // Exit cleanly when main() benchmark returns and commits trap loop at 0x28
        if (cycles > 100 && dut->debug_commit_valid && dut->debug_commit_pc == 0x28 && dut->debug_sq_empty) {
            test_result = 0;
            break;
        }

        cycles++;
    }

    // Dump signature if requested
    if (!sig_file.empty()) {
        std::ofstream sf(sig_file);
        if (sf.is_open()) {
            for (uint32_t addr = sig_start; addr < sig_end; addr += 4) {
                uint32_t word = dut->cpu->mem_inst->mem[addr / 4];
                char buf[16];
                snprintf(buf, sizeof(buf), "%08x\n", word);
                sf << buf;
            }
            sf.close();
            if (!quiet) {
                std::cout << "[TESTBENCH] Signature dumped to: " << sig_file << std::endl;
            }
        } else {
            std::cerr << "[TESTBENCH ERROR] Failed to open signature file: " << sig_file << std::endl;
        }
    }

    delete dut;

    if (test_result == 0) {
        if (!quiet) std::cout << "[PASS] (cycles: " << cycles << ")" << std::endl;
        return 0;
    } else if (test_result > 0) {
        std::cerr << "[FAIL] Test case " << test_result << " failed! (cycles: " << cycles << ")" << std::endl;
        return 1;
    } else {
        std::cerr << "[TIMEOUT] Exceeded " << max_cycles << " cycles!" << std::endl;
        return 2;
    }
}
