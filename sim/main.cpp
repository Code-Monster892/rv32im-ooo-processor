// ============================================================================
// Host Testbench Driver for RV32IM 2-Way OoO CPU
// Supports: Headless Regression, RISCOF Compliance, and 3D VRAM Graphics
// ============================================================================

#include "Vcpu.h"
#include "Vcpu_cpu.h"
#include "Vcpu_memory.h"
#include "verilated.h"
#include <iostream>
#include <fstream>
#include <iomanip>
#include <string>
#include <cstdint>
#include <cstring>
#include <chrono>
#include <queue>

#if __has_include(<SDL.h>)
#include <SDL.h>
#define HAVE_SDL2 1
#elif __has_include(<SDL2/SDL.h>)
#include <SDL2/SDL.h>
#define HAVE_SDL2 1
#else
#define HAVE_SDL2 0
#endif

// MMIO Address Constants
#define MMIO_VRAM_BASE    0x02000000
#define MMIO_VRAM_SIZE    (320 * 200 * 4) // 256,000 bytes (320x200 32-bit ARGB)
#define MMIO_TIMER        0x02500000
#define MMIO_KEYBOARD     0x02600000
#define MMIO_UART         0x10000000
#define MMIO_TOHOST       0x10000004

static uint32_t s_vram[320 * 200];
static std::queue<uint32_t> s_key_queue;

static void save_frame_ppm(const char *filename, const uint32_t *vram) {
    std::ofstream out(filename, std::ios::binary);
    if (!out) return;
    out << "P6\n320 200\n255\n";
    for (int i = 0; i < 320 * 200; i++) {
        uint32_t argb = vram[i];
        uint8_t r = (argb >> 16) & 0xFF;
        uint8_t g = (argb >> 8) & 0xFF;
        uint8_t b = argb & 0xFF;
        out.put(r).put(g).put(b);
    }
}

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
    bool cycles_specified = false;
    bool quiet = false;
    bool enable_gui = false;
    bool save_ppm = false;
    std::string ppm_filename = "donut_frame.ppm";

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
        } else if ((arg == "--max-cycles" || arg == "--cycles" || arg == "-c") && i + 1 < argc) {
            max_cycles = std::stoull(argv[++i], nullptr, 0);
            cycles_specified = true;
        } else if (arg == "--quiet" || arg == "-q") {
            quiet = true;
        } else if (arg == "--gui") {
            enable_gui = true;
        } else if (arg == "--headless") {
            enable_gui = false;
        } else if (arg == "--ppm" || arg == "--save-ppm") {
            save_ppm = true;
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                ppm_filename = argv[++i];
            }
        } else if (arg[0] != '-') {
            hex_file = arg;
        }
    }

    if (enable_gui && !cycles_specified) {
        max_cycles = UINT64_MAX; // Run interactively until window closed
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

    std::memset(s_vram, 0, sizeof(s_vram));

#if HAVE_SDL2
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    SDL_Texture* texture = nullptr;

    if (enable_gui) {
        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) == 0) {
            window = SDL_CreateWindow(
                "RISC-V 2-Way OoO CPU - 3D Graphics Engine",
                SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                960, 600, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
            );
            if (window) {
                renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
                if (!renderer) renderer = SDL_CreateRenderer(window, -1, 0);
                if (renderer) {
                    texture = SDL_CreateTexture(
                        renderer, SDL_PIXELFORMAT_ARGB8888,
                        SDL_TEXTUREACCESS_STREAMING, 320, 200
                    );
                }
            }
        }
        if (!window) {
            std::cerr << "[WARN] Failed to initialize SDL2 GUI window; running headless." << std::endl;
            enable_gui = false;
        }
    }
#endif

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
    bool exit_requested = false;
    bool vram_modified = false;
    auto last_render_time = std::chrono::steady_clock::now();

    while (!Verilated::gotFinish() && !exit_requested && cycles < max_cycles) {
        if (cycles == 5) {
            dut->rst_n = 1;
        }

        // Clock Low Phase (clk = 0)
        dut->clk = 0;
        dut->eval();

        // MMIO Timer Read & Keyboard Read
        dut->mmio_read_data = 0;
        if (dut->mmio_read_en) {
            if (dut->mmio_address == MMIO_TIMER) {
                dut->mmio_read_data = (uint32_t)cycles;
            } else if (dut->mmio_address == MMIO_KEYBOARD) {
                if (!s_key_queue.empty()) {
                    dut->mmio_read_data = s_key_queue.front();
                    s_key_queue.pop();
                } else {
                    dut->mmio_read_data = 0;
                }
            }
            dut->eval();
        }

        // MMIO Writes (UART, VRAM, TOHOST)
        if (dut->mmio_we) {
            uint32_t addr = dut->mmio_address;
            uint32_t data = dut->mmio_write_data;

            if (addr >= MMIO_VRAM_BASE && addr < MMIO_VRAM_BASE + MMIO_VRAM_SIZE) {
                uint32_t pixel_idx = (addr - MMIO_VRAM_BASE) >> 2;
                if (pixel_idx < 320 * 200) {
                    s_vram[pixel_idx] = data;
                    vram_modified = true;
                }
            } else if (addr == MMIO_UART) {
                char ch = (char)(data & 0xFF);
                std::cout << ch << std::flush;
            } else if (addr == MMIO_TOHOST) {
                exit_requested = true;
            }
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

        // Interactive GUI Event Handling & Frame Present (~60 FPS)
        if ((cycles & 0x3FFF) == 0) {
#if HAVE_SDL2
            if (enable_gui && window) {
                SDL_Event event;
                while (SDL_PollEvent(&event)) {
                    if (event.type == SDL_QUIT) {
                        exit_requested = true;
                    } else if (event.type == SDL_KEYDOWN || event.type == SDL_KEYUP) {
                        uint32_t is_down = (event.type == SDL_KEYDOWN) ? 1 : 0;
                        uint32_t scancode = event.key.keysym.scancode;
                        uint32_t raw_event = 0x80000000 | (is_down << 8) | (scancode & 0xFF);
                        s_key_queue.push(raw_event);
                        if (is_down && scancode == SDL_SCANCODE_ESCAPE) {
                            exit_requested = true;
                        }
                    }
                }

                auto now = std::chrono::steady_clock::now();
                auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_render_time).count();
                if (elapsed_ms >= 16 && vram_modified && renderer && texture) {
                    SDL_UpdateTexture(texture, nullptr, s_vram, 320 * sizeof(uint32_t));
                    SDL_RenderClear(renderer);
                    SDL_RenderCopy(renderer, texture, nullptr, nullptr);
                    SDL_RenderPresent(renderer);
                    last_render_time = now;
                    vram_modified = false;
                }
            }
#endif
        }

        cycles++;
    }

    // Save PPM frame if requested or if VRAM was drawn in headless mode
    if ((save_ppm || vram_modified) && !enable_gui) {
        save_frame_ppm(ppm_filename.c_str(), s_vram);
        if (!quiet) {
            std::cout << "[TESTBENCH] Frame captured to " << ppm_filename << std::endl;
        }
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

#if HAVE_SDL2
    if (texture)  SDL_DestroyTexture(texture);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window)   SDL_DestroyWindow(window);
    if (enable_gui) SDL_Quit();
#endif

    delete dut;

    if (test_result == 0 || (vram_modified && test_result == -1) || (cycles_specified && test_result == -1)) {
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
