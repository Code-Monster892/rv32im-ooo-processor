// ============================================================================
// BARE-METAL 3D GRAPHICS RENDERER (SPINNING DONUT / TORUS)
// Target: 2-Way Superscalar Out-of-Order RV32IM Processor
// Resolution: 320x200 32-bit ARGB TrueColor Framebuffer (MMIO 0x02000000)
// Math: 16.16 Fixed-Point with Precomputed 3x3 Rotation Matrix & HW Divide
// ============================================================================

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int   uint32_t;
typedef unsigned long long uint64_t;
typedef signed char    int8_t;
typedef signed short   int16_t;
typedef signed int     int32_t;
typedef signed long long int64_t;
typedef uint32_t       size_t;

#define NULL ((void*)0)

// MMIO Peripheral Addresses
#define MMIO_VRAM       ((volatile uint32_t*)0x02000000)
#define MMIO_TIMER      ((volatile uint32_t*)0x02500000)
#define MMIO_KEYBOARD   ((volatile uint32_t*)0x02600000)
#define MMIO_UART       ((volatile uint32_t*)0x10000000)
#define MMIO_TOHOST     ((volatile uint32_t*)0x10000004)

// Screen Dimensions
#define SCREEN_W 320
#define SCREEN_H 200
#define NUM_PIXELS (SCREEN_W * SCREEN_H)

// 16.16 Fixed-Point Math Definitions
typedef int32_t fixed_t;
#define FP_SHIFT 16
#define FP_ONE   (1 << FP_SHIFT) // 65536
#define FP_HALF  (1 << (FP_SHIFT - 1)) // 32768
#define INT_TO_FP(x) ((fixed_t)((x) << FP_SHIFT))
#define FP_TO_INT(x) ((int32_t)((x) >> FP_SHIFT))

static inline fixed_t fp_mul(fixed_t a, fixed_t b) {
    return (fixed_t)(((int64_t)a * b) >> FP_SHIFT);
}

// Ultra-Fast Hardware-Accelerated 1/Z Perspective Divide using RV32IM divu instruction
static inline fixed_t fast_ooz(fixed_t z_cam) {
    uint32_t z_scaled = (uint32_t)z_cam >> 8;
    if (z_scaled == 0) return 0;
    return (fixed_t)(16777216U / z_scaled);
}

// 256-Entry Fixed-Point Sine Table (0 to 2*PI, where 65536 = 1.0)
static const fixed_t sin_lut[256] = {
    0, 1608, 3216, 4821, 6424, 8022, 9616, 11204, 12785, 14359, 15924, 17479, 19024, 20557, 22078, 23586,
    25080, 26558, 28020, 29466, 30893, 32303, 33692, 35062, 36410, 37736, 39040, 40320, 41576, 42806, 44011, 45190,
    46341, 47464, 48559, 49624, 50660, 51665, 52639, 53581, 54491, 55368, 56212, 57022, 57798, 58538, 59244, 59914,
    60547, 61145, 61705, 62228, 62714, 63162, 63572, 63944, 64277, 64571, 64827, 65043, 65220, 65358, 65457, 65516,
    65536, 65516, 65457, 65358, 65220, 65043, 64827, 64571, 64277, 63944, 63572, 63162, 62714, 62228, 61705, 61145,
    60547, 59914, 59244, 58538, 57798, 57022, 56212, 55368, 54491, 53581, 52639, 51665, 50660, 49624, 48559, 47464,
    46341, 45190, 44011, 42806, 41576, 40320, 39040, 37736, 36410, 35062, 33692, 32303, 30893, 29466, 28020, 26558,
    25080, 23586, 22078, 20557, 19024, 17479, 15924, 14359, 12785, 11204, 9616, 8022, 6424, 4821, 3216, 1608,
    0, -1608, -3216, -4821, -6424, -8022, -9616, -11204, -12785, -14359, -15924, -17479, -19024, -20557, -22078, -23586,
    -25080, -26558, -28020, -29466, -30893, -32303, -33692, -35062, -36410, -37736, -39040, -40320, -41576, -42806, -44011, -45190,
    -46341, -47464, -48559, -49624, -50660, -51665, -52639, -53581, -54491, -55368, -56212, -57022, -57798, -58538, -59244, -59914,
    -60547, -61145, -61705, -62228, -62714, -63162, -63572, -63944, -64277, -64571, -64827, -65043, -65220, -65358, -65457, -65516,
    -65536, -65516, -65457, -65358, -65220, -65043, -64827, -64571, -64277, -63944, -63572, -63162, -62714, -62228, -61705, -61145,
    -60547, -59914, -59244, -58538, -57798, -57022, -56212, -55368, -54491, -53581, -52639, -51665, -50660, -49624, -48559, -47464,
    -46341, -45190, -44011, -42806, -41576, -40320, -39040, -37736, -36410, -35062, -33692, -32303, -30893, -29466, -28020, -26558,
    -25080, -23586, -22078, -20557, -19024, -17479, -15924, -14359, -12785, -11204, -9616, -8022, -6424, -4821, -3216, -1608
};

static inline fixed_t sin_fp(uint8_t angle) {
    return sin_lut[angle];
}

static inline fixed_t cos_fp(uint8_t angle) {
    return sin_lut[(uint8_t)(angle + 64)];
}

// Memory Buffers in RAM
static uint32_t back_buffer[NUM_PIXELS];
static fixed_t  z_buffer[NUM_PIXELS];

// Fast 32-bit Memory Operations
static void fast_memset32(uint32_t *dst, uint32_t val, uint32_t words) {
    uint32_t i = 0;
    while (i + 7 < words) {
        dst[i+0] = val; dst[i+1] = val; dst[i+2] = val; dst[i+3] = val;
        dst[i+4] = val; dst[i+5] = val; dst[i+6] = val; dst[i+7] = val;
        i += 8;
    }
    while (i < words) {
        dst[i++] = val;
    }
}

static void fast_memcpy32(volatile uint32_t *dst, const uint32_t *src, uint32_t words) {
    uint32_t i = 0;
    while (i + 7 < words) {
        dst[i+0] = src[i+0]; dst[i+1] = src[i+1]; dst[i+2] = src[i+2]; dst[i+3] = src[i+3];
        dst[i+4] = src[i+4]; dst[i+5] = src[i+5]; dst[i+6] = src[i+6]; dst[i+7] = src[i+7];
        i += 8;
    }
    while (i < words) {
        dst[i] = src[i];
        i++;
    }
}

// UART Printing Functions
static void uart_putc(char c) {
    *MMIO_UART = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void uart_put_dec(uint32_t n) {
    char buf[12];
    int i = 0;
    if (n == 0) {
        uart_putc('0');
        return;
    }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

// Simple 8x8 ASCII Font
static const uint8_t font8x8_basic[96][8] = {
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, // ' '
    {0x18,0x18,0x18,0x18,0x18,0x00,0x18,0x00}, // '!'
    {0x66,0x66,0x66,0x00,0x00,0x00,0x00,0x00}, // '"'
    {0x6c,0x6c,0xfe,0x6c,0xfe,0x6c,0x6c,0x00}, // '#'
    {0x18,0x7e,0xc0,0x7c,0x06,0xfc,0x18,0x00}, // '$'
    {0x00,0xc6,0xcc,0x18,0x30,0x66,0xc6,0x00}, // '%'
    {0x38,0x6c,0x38,0x76,0xdc,0xcc,0x76,0x00}, // '&'
    {0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00}, // '\''
    {0x0c,0x18,0x30,0x30,0x30,0x18,0x0c,0x00}, // '('
    {0x30,0x18,0x0c,0x0c,0x0c,0x18,0x30,0x00}, // ')'
    {0x00,0x66,0x3c,0xff,0x3c,0x66,0x00,0x00}, // '*'
    {0x00,0x18,0x18,0x7e,0x18,0x18,0x00,0x00}, // '+'
    {0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30}, // ','
    {0x00,0x00,0x00,0x7e,0x00,0x00,0x00,0x00}, // '-'
    {0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00}, // '.'
    {0x06,0x0c,0x18,0x30,0x60,0xc0,0x80,0x00}, // '/'
    {0x3c,0x66,0x6e,0x76,0x66,0x66,0x3c,0x00}, // '0'
    {0x18,0x38,0x18,0x18,0x18,0x18,0x7e,0x00}, // '1'
    {0x3c,0x66,0x06,0x0c,0x18,0x30,0x7e,0x00}, // '2'
    {0x7e,0x0c,0x18,0x0c,0x06,0x66,0x3c,0x00}, // '3'
    {0x0c,0x1c,0x3c,0x6c,0xfe,0x0c,0x0c,0x00}, // '4'
    {0x7e,0x60,0x7c,0x06,0x06,0x66,0x3c,0x00}, // '5'
    {0x3c,0x66,0x60,0x7c,0x66,0x66,0x3c,0x00}, // '6'
    {0x7e,0x06,0x0c,0x18,0x30,0x30,0x30,0x00}, // '7'
    {0x3c,0x66,0x66,0x3c,0x66,0x66,0x3c,0x00}, // '8'
    {0x3c,0x66,0x66,0x3e,0x06,0x66,0x3c,0x00}, // '9'
    {0x00,0x18,0x18,0x00,0x18,0x18,0x00,0x00}, // ':'
    {0x00,0x18,0x18,0x00,0x18,0x18,0x30,0x00}, // ';'
    {0x0c,0x18,0x30,0x60,0x30,0x18,0x0c,0x00}, // '<'
    {0x00,0x7e,0x00,0x7e,0x00,0x00,0x00,0x00}, // '='
    {0x30,0x18,0x0c,0x06,0x0c,0x18,0x30,0x00}, // '>'
    {0x3c,0x66,0x06,0x0c,0x18,0x00,0x18,0x00}, // '?'
    {0x3c,0x66,0x6e,0x6e,0x60,0x62,0x3c,0x00}, // '@'
    {0x18,0x3c,0x66,0x7e,0x66,0x66,0x66,0x00}, // 'A'
    {0x7c,0x66,0x66,0x7c,0x66,0x66,0x7c,0x00}, // 'B'
    {0x3c,0x66,0x60,0x60,0x60,0x66,0x3c,0x00}, // 'C'
    {0x78,0x6c,0x66,0x66,0x66,0x6c,0x78,0x00}, // 'D'
    {0x7e,0x60,0x60,0x7c,0x60,0x60,0x7e,0x00}, // 'E'
    {0x7e,0x60,0x60,0x7c,0x60,0x60,0x60,0x00}, // 'F'
    {0x3c,0x66,0x60,0x6e,0x66,0x66,0x3a,0x00}, // 'G'
    {0x66,0x66,0x66,0x7e,0x66,0x66,0x66,0x00}, // 'H'
    {0x7e,0x18,0x18,0x18,0x18,0x18,0x7e,0x00}, // 'I'
    {0x0e,0x06,0x06,0x06,0x06,0x66,0x3c,0x00}, // 'J'
    {0x66,0x6c,0x78,0x70,0x78,0x6c,0x66,0x00}, // 'K'
    {0x60,0x60,0x60,0x60,0x60,0x60,0x7e,0x00}, // 'L'
    {0x63,0x77,0x7f,0x6b,0x63,0x63,0x63,0x00}, // 'M'
    {0x66,0x76,0x7e,0x7e,0x6e,0x66,0x66,0x00}, // 'N'
    {0x3c,0x66,0x66,0x66,0x66,0x66,0x3c,0x00}, // 'O'
    {0x7c,0x66,0x66,0x7c,0x60,0x60,0x60,0x00}, // 'P'
    {0x3c,0x66,0x66,0x66,0x6a,0x6c,0x36,0x00}, // 'Q'
    {0x7c,0x66,0x66,0x7c,0x6c,0x66,0x66,0x00}, // 'R'
    {0x3c,0x66,0x60,0x3c,0x06,0x66,0x3c,0x00}, // 'S'
    {0x7e,0x18,0x18,0x18,0x18,0x18,0x18,0x00}, // 'T'
    {0x66,0x66,0x66,0x66,0x66,0x66,0x3c,0x00}, // 'U'
    {0x66,0x66,0x66,0x66,0x66,0x3c,0x18,0x00}, // 'V'
    {0x63,0x63,0x63,0x6b,0x7f,0x77,0x63,0x00}, // 'W'
    {0x66,0x66,0x3c,0x18,0x3c,0x66,0x66,0x00}, // 'X'
    {0x66,0x66,0x66,0x3c,0x18,0x18,0x18,0x00}, // 'Y'
    {0x7e,0x06,0x0c,0x18,0x30,0x60,0x7e,0x00}, // 'Z'
    {0x3c,0x30,0x30,0x30,0x30,0x30,0x3c,0x00}, // '['
    {0xc0,0x60,0x30,0x18,0x0c,0x06,0x02,0x00}, // '\'
    {0x3c,0x0c,0x0c,0x0c,0x0c,0x0c,0x3c,0x00}, // ']'
    {0x18,0x3c,0x66,0x00,0x00,0x00,0x00,0x00}, // '^'
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff}, // '_'
    {0x30,0x18,0x0c,0x00,0x00,0x00,0x00,0x00}, // '`'
    {0x18,0x3c,0x66,0x7e,0x66,0x66,0x66,0x00}, // 'a'
    {0x7c,0x66,0x66,0x7c,0x66,0x66,0x7c,0x00}, // 'b'
    {0x3c,0x66,0x60,0x60,0x60,0x66,0x3c,0x00}, // 'c'
    {0x78,0x6c,0x66,0x66,0x66,0x6c,0x78,0x00}, // 'd'
    {0x7e,0x60,0x60,0x7c,0x60,0x60,0x7e,0x00}, // 'e'
    {0x7e,0x60,0x60,0x7c,0x60,0x60,0x60,0x00}, // 'f'
    {0x3c,0x66,0x60,0x6e,0x66,0x66,0x3a,0x00}, // 'g'
    {0x66,0x66,0x66,0x7e,0x66,0x66,0x66,0x00}, // 'h'
    {0x7e,0x18,0x18,0x18,0x18,0x18,0x7e,0x00}, // 'i'
    {0x0e,0x06,0x06,0x06,0x06,0x66,0x3c,0x00}, // 'j'
    {0x66,0x6c,0x78,0x70,0x78,0x6c,0x66,0x00}, // 'k'
    {0x60,0x60,0x60,0x60,0x60,0x60,0x7e,0x00}, // 'l'
    {0x63,0x77,0x7f,0x6b,0x63,0x63,0x63,0x00}, // 'm'
    {0x66,0x76,0x7e,0x7e,0x6e,0x66,0x66,0x00}, // 'n'
    {0x3c,0x66,0x66,0x66,0x66,0x66,0x3c,0x00}, // 'o'
    {0x7c,0x66,0x66,0x7c,0x60,0x60,0x60,0x00}, // 'p'
    {0x3c,0x66,0x66,0x66,0x6a,0x6c,0x36,0x00}, // 'q'
    {0x7c,0x66,0x66,0x7c,0x6c,0x66,0x66,0x00}, // 'r'
    {0x3c,0x66,0x60,0x3c,0x06,0x66,0x3c,0x00}, // 's'
    {0x7e,0x18,0x18,0x18,0x18,0x18,0x18,0x00}, // 't'
    {0x66,0x66,0x66,0x66,0x66,0x66,0x3c,0x00}, // 'u'
    {0x66,0x66,0x66,0x66,0x66,0x3c,0x18,0x00}, // 'v'
    {0x63,0x63,0x63,0x6b,0x7f,0x77,0x63,0x00}, // 'w'
    {0x66,0x66,0x3c,0x18,0x3c,0x66,0x66,0x00}, // 'x'
    {0x66,0x66,0x66,0x3c,0x18,0x18,0x18,0x00}, // 'y'
    {0x7e,0x06,0x0c,0x18,0x30,0x60,0x7e,0x00}, // 'z'
    {0x1c,0x18,0x18,0x30,0x18,0x18,0x1c,0x00}, // '{'
    {0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x00}, // '|'
    {0x38,0x18,0x18,0x0c,0x18,0x18,0x38,0x00}, // '}'
    {0x3b,0x6e,0x00,0x00,0x00,0x00,0x00,0x00}, // '~'
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}
};

static void draw_char(int x, int y, char c, uint32_t color) {
    if (c < 32 || c > 126) c = ' ';
    const uint8_t *glyph = font8x8_basic[c - 32];
    for (int row = 0; row < 8; row++) {
        int py = y + row;
        if (py < 0 || py >= SCREEN_H) continue;
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            int px = x + col;
            if (px < 0 || px >= SCREEN_W) continue;
            if (bits & (0x80 >> col)) {
                back_buffer[py * SCREEN_W + px] = color;
            }
        }
    }
}

static void draw_string(int x, int y, const char *s, uint32_t color) {
    while (*s) {
        draw_char(x + 1, y + 1, *s, 0xFF050505);
        draw_char(x, y, *s, color);
        x += 8;
        s++;
    }
}

// Color Palettes (16 Shading Levels from Ambient to Specular)
static const uint32_t palette_donut[16] = {
    0xFF1A0A02, 0xFF2E1304, 0xFF451D08, 0xFF5C280D,
    0xFF733312, 0xFF8A3E17, 0xFFA1491D, 0xFFB85523,
    0xFFCF622B, 0xFFE07336, 0xFFED8547, 0xFFF5995E,
    0xFFFCAE77, 0xFFFCC595, 0xFFFDDAB5, 0xFFFFF0D6
};

static const uint32_t palette_neon[16] = {
    0xFF0D021A, 0xFF1B0533, 0xFF2E0A4F, 0xFF46106E,
    0xFF63188F, 0xFF8321B0, 0xFFA42BD0, 0xFFC537ED,
    0xFFDE45F7, 0xFFE65DF7, 0xFFC97AF7, 0xFF96A5FA,
    0xFF62D2FC, 0xFF4AE2FC, 0xFF7BF0FD, 0xFFE0FFFF
};

static const uint32_t palette_magma[16] = {
    0xFF150402, 0xFF2A0603, 0xFF450904, 0xFF660D06,
    0xFF8A1207, 0xFFB01908, 0xFFD42509, 0xFFF03B0D,
    0xFFF75815, 0xFFFA771F, 0xFFFC992D, 0xFFFDBC42,
    0xFFFED860, 0xFFFEEC87, 0xFFFFF8B8, 0xFFFFFFF0
};

static const uint32_t palette_matrix[16] = {
    0xFF021204, 0xFF042108, 0xFF07360E, 0xFF0B4F15,
    0xFF106B1E, 0xFF168A28, 0xFF1EAA34, 0xFF27CB41,
    0xFF36E852, 0xFF57F06E, 0xFF7CF48E, 0xFFA0F7B0,
    0xFFC3FBD1, 0xFFDFFDE8, 0xFFF2FFF6, 0xFFFFFFFF
};

static const uint32_t *active_palette = palette_donut;
static int active_theme = 0;
static const char *theme_names[4] = {
    "GOLDEN GLAZED",
    "CYBERPUNK NEON",
    "MOLTEN MAGMA",
    "MATRIX EMERALD"
};

// Torus Geometric Parameters in 16.16 Fixed Point
#define TORUS_R1 INT_TO_FP(1)      // Tube radius = 1.0
#define TORUS_R2 (INT_TO_FP(2))    // Major ring radius = 2.0
#define CAM_K2   (INT_TO_FP(5))    // Distance from camera = 5.0
#define CAM_K1   (INT_TO_FP(130))  // Projection scaling factor

// Directional Light Vector: (0.577, 0.577, -0.577) normalized -> 37814 in 16.16
#define LIGHT_X 37814
#define LIGHT_Y 37814
#define LIGHT_Z (-37814)

// Draw Shaded 3D Torus Frame using Precomputed 3x3 Compound Rotation Matrix
static void render_torus(uint8_t angle_A, uint8_t angle_B) {
    fast_memset32(back_buffer, 0xFF080C14, NUM_PIXELS);
    fast_memset32((uint32_t*)z_buffer, 0, NUM_PIXELS);

    fixed_t sinA = sin_fp(angle_A);
    fixed_t cosA = cos_fp(angle_A);
    fixed_t sinB = sin_fp(angle_B);
    fixed_t cosB = cos_fp(angle_B);

    // Precalculate 3x3 Compound Rotation Matrix R = Rz(B) * Rx(A)
    // [ X' ]   [ m00  m01  m02 ]   [ X0 ]
    // [ Y' ] = [ m10  m11  m12 ] * [ Y0 ]
    // [ Z' ]   [  0   m21  m22 ]   [ Z0 ]
    fixed_t m00 = cosB;
    fixed_t m01 = -fp_mul(sinB, cosA);
    fixed_t m02 =  fp_mul(sinB, sinA);

    fixed_t m10 = sinB;
    fixed_t m11 =  fp_mul(cosB, cosA);
    fixed_t m12 = -fp_mul(cosB, sinA);

    fixed_t m21 = sinA;
    fixed_t m22 = cosA;

    // Phi: 85 steps around major ring (step 3)
    // Theta: 51 steps around tube (step 5)
    // Ultra-dense sampling for lush, watertight, perfectly smooth geometry
    for (uint32_t phi_idx = 0; phi_idx < 256; phi_idx += 3) {
        uint8_t phi = (uint8_t)phi_idx;
        fixed_t sinPhi = sin_fp(phi);
        fixed_t cosPhi = cos_fp(phi);

        for (uint32_t theta_idx = 0; theta_idx < 256; theta_idx += 5) {
            uint8_t theta = (uint8_t)theta_idx;
            fixed_t sinTheta = sin_fp(theta);
            fixed_t cosTheta = cos_fp(theta);

            // 1. Unrotated coordinates & surface normal
            fixed_t circle_x = TORUS_R2 + fp_mul(TORUS_R1, cosTheta);
            fixed_t circle_y = fp_mul(TORUS_R1, sinTheta);

            fixed_t x0 = fp_mul(circle_x, cosPhi);
            fixed_t y0 = fp_mul(circle_x, sinPhi);
            fixed_t z0 = circle_y;

            fixed_t nx0 = fp_mul(cosTheta, cosPhi);
            fixed_t ny0 = fp_mul(cosTheta, sinPhi);
            fixed_t nz0 = sinTheta;

            // 2. Optimized 3x3 Matrix Multiplication (Fused 3D Rotation)
            fixed_t x2 = fp_mul(m00, x0) + fp_mul(m01, y0) + fp_mul(m02, z0);
            fixed_t y2 = fp_mul(m10, x0) + fp_mul(m11, y0) + fp_mul(m12, z0);
            fixed_t z2 = fp_mul(m21, y0) + fp_mul(m22, z0);

            fixed_t nx2 = fp_mul(m00, nx0) + fp_mul(m01, ny0) + fp_mul(m02, nz0);
            fixed_t ny2 = fp_mul(m10, nx0) + fp_mul(m11, ny0) + fp_mul(m12, nz0);
            fixed_t nz2 = fp_mul(m21, ny0) + fp_mul(m22, nz0);

            // 3. Directional Lighting: N · L
            fixed_t illum = fp_mul(nx2, LIGHT_X) + fp_mul(ny2, LIGHT_Y) + fp_mul(nz2, LIGHT_Z);

            // 4. Perspective Projection with 1-cycle hardware divide
            fixed_t z_cam = z2 + CAM_K2;
            if (z_cam <= FP_HALF) continue;

            fixed_t ooz = fast_ooz(z_cam);

            int32_t xp = (SCREEN_W / 2) + FP_TO_INT(fp_mul(fp_mul(x2, CAM_K1), ooz));
            int32_t yp = (SCREEN_H / 2) - FP_TO_INT(fp_mul(fp_mul(y2, CAM_K1), ooz));

            if (xp >= 1 && xp < SCREEN_W - 2 && yp >= 16 && yp < SCREEN_H - 18) {
                int32_t lum_idx = FP_TO_INT(fp_mul(illum + INT_TO_FP(1), INT_TO_FP(8)));
                if (lum_idx < 0)  lum_idx = 0;
                if (lum_idx > 15) lum_idx = 15;
                uint32_t col = active_palette[lum_idx];

                // 2x2 watertight splatting into Z-buffer
                int base_idx = yp * SCREEN_W + xp;
                if (ooz > z_buffer[base_idx]) {
                    z_buffer[base_idx] = ooz;
                    back_buffer[base_idx] = col;
                }
                if (ooz > z_buffer[base_idx + 1]) {
                    z_buffer[base_idx + 1] = ooz;
                    back_buffer[base_idx + 1] = col;
                }
                int base_idx_down = base_idx + SCREEN_W;
                if (ooz > z_buffer[base_idx_down]) {
                    z_buffer[base_idx_down] = ooz;
                    back_buffer[base_idx_down] = col;
                }
                if (ooz > z_buffer[base_idx_down + 1]) {
                    z_buffer[base_idx_down + 1] = ooz;
                    back_buffer[base_idx_down + 1] = col;
                }
            }
        }
    }
}

// Render Retro Cyberpunk HUD Headers and Footers
static void render_hud(uint32_t frame_num, uint32_t cycles, uint8_t angle_A, uint8_t angle_B) {
    for (int y = 0; y < 14; y++) {
        for (int x = 0; x < SCREEN_W; x++) {
            back_buffer[y * SCREEN_W + x] = 0xFF101826;
        }
    }
    for (int x = 0; x < SCREEN_W; x++) {
        back_buffer[14 * SCREEN_W + x] = 0xFF35527A;
    }
    draw_string(16, 3, "RV32IM 2-WAY OoO * 3D DONUT RENDERER", 0xFF66D9EF);

    for (int y = SCREEN_H - 16; y < SCREEN_H; y++) {
        for (int x = 0; x < SCREEN_W; x++) {
            back_buffer[y * SCREEN_W + x] = 0xFF101826;
        }
    }
    for (int x = 0; x < SCREEN_W; x++) {
        back_buffer[(SCREEN_H - 16) * SCREEN_W + x] = 0xFF35527A;
    }

    char stat[64];
    int idx = 0;
    stat[idx++] = 'F'; stat[idx++] = ':';
    uint32_t fn = frame_num;
    char fbuf[8]; int fi = 0;
    if (fn == 0) fbuf[fi++] = '0';
    while (fn > 0) { fbuf[fi++] = '0' + (fn % 10); fn /= 10; }
    while (fi > 0) stat[idx++] = fbuf[--fi];

    stat[idx++] = ' '; stat[idx++] = '|'; stat[idx++] = ' ';
    const char *tn = theme_names[active_theme];
    while (*tn) stat[idx++] = *tn++;

    stat[idx++] = ' '; stat[idx++] = '|'; stat[idx++] = ' ';
    stat[idx++] = '1'; stat[idx++] = '-'; stat[idx++] = '4'; stat[idx++] = ':'; 
    stat[idx++] = 'T'; stat[idx++] = 'h'; stat[idx++] = 'e'; stat[idx++] = 'm'; stat[idx++] = 'e';
    stat[idx] = '\0';

    draw_string(10, SCREEN_H - 12, stat, 0xFFA6E22E);
}

// Check Keyboard Input from MMIO Queue
static void process_keyboard(int *auto_spin, int *spin_speed) {
    uint32_t key_event = *MMIO_KEYBOARD;
    while (key_event != 0) {
        uint32_t is_down = (key_event >> 8) & 1;
        uint32_t scancode = key_event & 0xFF;

        if (is_down) {
            if (scancode == 30) { active_theme = 0; active_palette = palette_donut; }
            else if (scancode == 31) { active_theme = 1; active_palette = palette_neon; }
            else if (scancode == 32) { active_theme = 2; active_palette = palette_magma; }
            else if (scancode == 33) { active_theme = 3; active_palette = palette_matrix; }
            else if (scancode == 44) {
                *auto_spin = !(*auto_spin);
            }
            else if (scancode == 41) {
                *MMIO_TOHOST = 0;
            }
        }
        key_event = *MMIO_KEYBOARD;
    }
}

// Main Program Entry Point
int main(void) {
    uart_puts("\n==============================================\n");
    uart_puts("   RV32IM 2-Way OoO Real-Time 3D Renderer     \n");
    uart_puts("       Spinning Torus (Donut) Engine          \n");
    uart_puts("==============================================\n");
    uart_puts("[3D] Initializing 16.16 Fixed-Point Math & Z-Buffer...\n");
    uart_puts("[3D] VRAM Framebuffer mapped at 0x02000000 (320x200 ARGB)\n");
    uart_puts("[3D] Starting real-time animation loop...\n");

    uint8_t angle_A = 0;
    uint8_t angle_B = 0;
    uint32_t frame_count = 0;
    int auto_spin = 1;
    int spin_speed = 3; // Smooth, gentle rotational progression

    while (1) {
        uint32_t frame_start_cycle = *MMIO_TIMER;

        process_keyboard(&auto_spin, &spin_speed);
        render_torus(angle_A, angle_B);
        render_hud(frame_count, frame_start_cycle, angle_A, angle_B);
        fast_memcpy32(MMIO_VRAM, back_buffer, NUM_PIXELS);

        if (auto_spin) {
            angle_A += (uint8_t)(spin_speed + 1);
            angle_B += (uint8_t)(spin_speed + 2);
        }

        uint32_t frame_end_cycle = *MMIO_TIMER;
        uint32_t delta_cycles = frame_end_cycle - frame_start_cycle;
        uart_puts("[FRAME ");
        uart_put_dec(frame_count);
        uart_puts("] Cycles: ");
        uart_put_dec(delta_cycles);
        uart_puts(" | A: ");
        uart_put_dec(angle_A);
        uart_puts(" B: ");
        uart_put_dec(angle_B);
        uart_puts(" | Theme: ");
        uart_puts(theme_names[active_theme]);
        uart_puts("\n");

        frame_count++;
    }

    return 0;
}
