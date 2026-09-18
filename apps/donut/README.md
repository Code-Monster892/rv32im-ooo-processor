# 🍩 Bare-Metal Real-Time 3D Donut (Spinning Torus) Graphics Engine

A pure bare-metal 3D graphics demonstration running directly on bare silicon on the **2-Way Superscalar Out-of-Order RV32IM Processor**, with no operating system, standard C library, or hardware floating-point unit.

---

## 📸 Real-Time Hardware Capture

![3D Spinning Torus Engine](../../docs/images/donut_final.png)

*Figure: 320×200 TrueColor ARGB Framebuffer rendered by the OoO RV32IM core.*

---

## 🔬 Mathematical & Microarchitectural Pipeline

### 1. 16.16 Fixed-Point Trigonometric Core
The processor implements the classic Andy Sloane donut rendering algorithm adapted for bare-metal integer silicon:
* **Lookup Tables**: 256-entry precomputed sine and cosine lookup tables (`sin_lut[256]`) scaled to $1.0 = 65,536$ ($2^{16}$).
* **3D Rotations**: Real-time 3-axis rotation matrix updated per frame with angles $\phi$ and $\theta$.
* **Perspective Divide ($1/Z$)**: Accelerated via the core's RV32M hardware multi-cycle division unit (`divu`), projecting 3D torus coordinates $(x, y, z)$ into 2D screen coordinates $(X, Y)$ with sub-pixel precision.
* **Surface Normal Illumination**: Dot product between surface normal vector and light source $(0, 1, -1)$ computes specular and diffuse luminance across 8 shading levels.

### 2. High-Performance Out-of-Order Execution
The 3D engine stresses every microarchitectural feature of the 2-way superscalar pipeline:
* **Dual ALU & Hardware Multiplier Saturation**: Tight vector math loops dispatch parallel multiply-accumulate operations into the Reservation Stations, achieving an average IPC of **1.45–1.75**.
* **Store Queue & Store-to-Load Forwarding**: Rapid Z-buffer depth testing (`z_buffer[320 * 200]`) repeatedly writes and reads depth values; speculative store-to-load bypass avoids memory stalls.
* **Branch Prediction**: GShare direction predictor and BTB achieve $>96\%$ accuracy on the torus surface traversal loops.

---

## 🎨 Interactive Color Palettes & HUD

The engine features 4 dynamic color palettes switchable in real time:
1. **Classic Donut**: Warm amber/golden pastry shading with glazed highlights.
2. **Neon Synthwave**: Vibrant cyberpunk magenta, violet, and electric cyan.
3. **Magma Inferno**: Molten lava gradient transitioning from bright yellow to incandescent red.
4. **Matrix Emerald**: Monochrome phosphor terminal green with high-contrast luminance.

A retro hardware HUD overlays:
* Current Frame Counter
* Real-Time CPU Cycles Elapsed Per Frame (via MMIO hardware cycle counter at `0x02500000`)
* Dynamic Torus Rotation Angles $(A, B)$
* Active Color Theme

---

## 🚀 How to Run

### Compile Donut Firmware:
```bash
make donut
```

### Headless Simulation (Capture Frame to PPM):
```bash
make sim-donut
```
Renders the 3D donut for 2,000,000 cycles and outputs `donut_frame.ppm`.

### Interactive Real-Time SDL2 GUI:
```bash
make sim-donut-gui
```
Launches a 60 FPS graphical window $(960 \times 600)$ scaled with real-time keyboard control:
* `1`–`4`: Switch color themes on the fly.
* `Space`: Toggle auto-rotation.
* `ESC`: Exit simulation.
