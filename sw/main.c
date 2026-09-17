// Comprehensive RISC-V Out-of-Order Core Stress Benchmark Suite
#include <stdint.h>

#define MMIO_CONSOLE (*(volatile uint8_t *)0x10000000)

// --- Fast Bare-Metal Console Output ---
static void print_str(const char *s) {
    while (*s) {
        MMIO_CONSOLE = (uint8_t)(*s++);
    }
}

static void print_int(int val) {
    if (val == 0) {
        MMIO_CONSOLE = '0';
        return;
    }
    char buf[12];
    int i = 0;
    int is_neg = 0;
    if (val < 0) {
        is_neg = 1;
        val = -val;
    }
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    if (is_neg) buf[i++] = '-';
    while (i > 0) {
        MMIO_CONSOLE = buf[--i];
    }
}

static void print_hex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    print_str("0x");
    for (int i = 7; i >= 0; i--) {
        uint8_t nibble = (val >> (i * 4)) & 0xF;
        MMIO_CONSOLE = hex_chars[nibble];
    }
}

// 1. Matrix Multiplication (4x4 Integers in RAM)
static int mat_A[4][4] = {
    { 1,  2,  3,  4 },
    { 5,  6,  7,  8 },
    { 9, 10, 11, 12 },
    {13, 14, 15, 16 }
};
static int mat_B[4][4] = {
    { 2,  0, -1,  1 },
    { 1,  3,  2,  0 },
    { 0,  1,  4, -2 },
    {-1,  2,  0,  3 }
};
static int mat_C[4][4];

__attribute__((noinline)) int test_matrix_mult(void) {
    int total_sum = 0;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            int acc = 0;
            for (int k = 0; k < 4; k++) {
                acc += mat_A[i][k] * mat_B[k][j];
            }
            mat_C[i][j] = acc;
            total_sum += acc;
        }
    }
    return total_sum;
}

// 2. Hardware Divide & Convergence: Integer Square Root (Newton-Raphson)
__attribute__((noinline)) int isqrt(int n) {
    if (n <= 0) return 0;
    int x = n;
    int y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

// 3. Deep Recursive Call-Stack Stress: Fibonacci
__attribute__((noinline)) int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

// 4. Memory Pointer Manipulation & Data Hazard Stress: Bubble Sort
static int sort_arr[12] = { 87, 12, 45, 99, 23, 56, 1, 38, 70, 14, 62, 5 };

__attribute__((noinline)) int test_sort(void) {
    int n = 12;
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (sort_arr[j] > sort_arr[j + 1]) {
                int temp = sort_arr[j];
                sort_arr[j] = sort_arr[j + 1];
                sort_arr[j + 1] = temp;
            }
        }
    }

    // Check monotonic order
    for (int i = 0; i < n - 1; i++) {
        if (sort_arr[i] > sort_arr[i + 1]) return 0;
    }
    // Verify min and max bounds
    if (sort_arr[0] != 1 || sort_arr[11] != 99) return 0;
    return 1;
}

// 5. Control Flow & Branch Predictor Stress: Prime Sieve
__attribute__((noinline)) int count_primes(int limit) {
    int count = 0;
    for (int n = 2; n <= limit; n++) {
        int is_prime = 1;
        for (int d = 2; d < n; d++) {
            if (n % d == 0) {
                is_prime = 0;
                break;
            }
        }
        if (is_prime) {
            count++;
        }
    }
    return count;
}

// 6. Horner's Polynomial & Fast Bit Manipulation (Xorshift32 PRNG)
__attribute__((noinline)) int evaluate_polynomial(int x) {
    // P(x) = 2*x^3 - 3*x^2 + 5*x - 7 = ((2*x - 3)*x + 5)*x - 7
    return ((2 * x - 3) * x + 5) * x - 7;
}

__attribute__((noinline)) uint32_t xorshift32_rounds(uint32_t seed, int rounds) {
    uint32_t state = seed;
    for (int i = 0; i < rounds; i++) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
    }
    return state;
}

// 7. Directed Regression: Older Store with Delayed Address followed by Same-Address Load
// Verifies that the Load Queue stalls/replays when an older store's address is unresolved,
// and correctly receives forwarded data instead of reading stale RAM.
__attribute__((noinline)) int test_delayed_older_store(void) {
    volatile uint32_t mem_var = 0x11111111;
    uint32_t loaded_val = 0;
    uint32_t store_val = 0x22222222;

    asm volatile (
        "addi t0, %2, -128\n\t"
        "addi t0, t0, 64\n\t"
        "addi t0, t0, 32\n\t"
        "addi t0, t0, 16\n\t"
        "addi t0, t0, 8\n\t"
        "addi t0, t0, 8\n\t"
        "sw   %1, 0(t0)\n\t"
        "lw   %0, 0(%2)\n\t"
        : "=r"(loaded_val)
        : "r"(store_val), "r"(&mem_var)
        : "t0", "memory"
    );

    return (loaded_val == 0x22222222);
}

// 8. Directed Regression: Load followed by Younger Same-Address Store
// Verifies that the Store Queue uses ROB age comparison to ignore younger stores,
// preventing the load from observing speculative future store data.
__attribute__((noinline)) int test_younger_store_isolation(void) {
    volatile uint32_t mem_var = 0xAAAAAAAA;
    uint32_t loaded_val = 0;
    uint32_t store_val = 0xBBBBBBBB;

    asm volatile (
        "addi t0, %2, -128\n\t"
        "addi t0, t0, 64\n\t"
        "addi t0, t0, 32\n\t"
        "addi t0, t0, 16\n\t"
        "addi t0, t0, 8\n\t"
        "addi t0, t0, 8\n\t"
        "lw   %0, 0(t0)\n\t"
        "sw   %1, 0(%2)\n\t"
        : "=r"(loaded_val)
        : "r"(store_val), "r"(&mem_var)
        : "t0", "memory"
    );

    return (loaded_val == 0xAAAAAAAA);
}

// Main Benchmark Controller
int main(void) {    
    // Exercise FENCE instruction (safe memory barrier NOP)
    asm volatile ("fence\n\t");

    print_str("   RISC-V OoO Dual-Issue Core Advanced Benchmark Suite   \n");

    int all_passed = 1;

    // --- Task 1: 4x4 Matrix Multiply ---
    print_str("[TASK 1] 4x4 Integer Matrix Multiplication...\n");
    int mat_sum = test_matrix_mult();
    print_str("         Result Sum = ");
    print_int(mat_sum);
    print_str(" (Expected: 516) -> ");
    if (mat_sum == 516) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 2: Newton-Raphson Integer Square Root ---
    print_str("[TASK 2] Newton-Raphson Integer Square Root...\n");
    int r1 = isqrt(65536);
    int r2 = isqrt(1234567);
    print_str("         isqrt(65536)   = ");
    print_int(r1);
    print_str(" (Expected: 256)\n");
    print_str("         isqrt(1234567) = ");
    print_int(r2);
    print_str(" (Expected: 1111) -> ");
    if (r1 == 256 && r2 == 1111) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 3: Deep Recursive Call-Stack (Fibonacci) ---
    print_str("[TASK 3] Deep Call Stack Recursion: fib(12)...\n");
    int fib_res = fib(12);
    print_str("         fib(12) = ");
    print_int(fib_res);
    print_str(" (Expected: 144) -> ");
    if (fib_res == 144) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 4: In-Memory Bubble Sort ---
    print_str("[TASK 4] In-Memory Array Bubble Sort (12 elements)...\n");
    int sort_res = test_sort();
    print_str("         Sorted Monotonicity & Bounds Check -> ");
    if (sort_res == 1) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 5: Prime Number Sieve ---
    print_str("[TASK 5] Prime Sieve (count primes <= 50)...\n");
    int prime_count = count_primes(50);
    print_str("         Prime Count = ");
    print_int(prime_count);
    print_str(" (Expected: 15) -> ");
    if (prime_count == 15) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 6: Horner Polynomial & Xorshift32 PRNG ---
    print_str("[TASK 6] Horner Polynomial & Xorshift32 PRNG...\n");
    int poly_res = evaluate_polynomial(7);
    uint32_t prng_res = xorshift32_rounds(0x12345678, 50);
    print_str("         P(7) = ");
    print_int(poly_res);
    print_str(" (Expected: 567)\n");
    print_str("         PRNG(50 rounds) = ");
    print_hex(prng_res);
    print_str(" (Expected: 0x14539EC0) -> ");
    if (poly_res == 567 && prng_res == 0x14539EC0) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 7: Directed Memory Ordering (Delayed Older Store) ---
    print_str("[TASK 7] Directed Memory Ordering: Delayed Older Store...\n");
    int delay_store_res = test_delayed_older_store();
    print_str("         Forwarded Store Data vs Stale RAM -> ");
    if (delay_store_res) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Task 8: Directed Younger Store Isolation ---
    print_str("[TASK 8] Directed Memory Ordering: Younger Store Isolation...\n");
    int young_store_res = test_younger_store_isolation();
    print_str("         Younger Store Forwarding Suppression -> ");
    if (young_store_res) {
        print_str("PASS\n");
    } else {
        print_str("FAIL\n");
        all_passed = 0;
    }

    // --- Final Summary ---
    print_str("--------------------------------------------------------\n");
    if (all_passed) {
        print_str(">>> ALL HARDWARE WORKLOADS COMPLETED & PASSED! <<<\n");
        print_str("--------------------------------------------------------\n");
        return 0;
    } else {
        print_str(">>> BENCHMARK SUITE FAILED! <<<\n");
        print_str("--------------------------------------------------------\n");
        return -1;
    }
}
