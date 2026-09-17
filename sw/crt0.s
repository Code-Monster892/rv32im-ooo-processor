.global _start

.section .init
_start:
    # 1. Initialize Stack Pointer (sp / x2) to 8MB mark (0x00800000)
    li sp, 0x00800000

    # 2. Clear the .bss section (initialize global static variables to 0)
    la t0, __bss_start
    la t1, __bss_end
    bgeu t0, t1, 2f
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:

    # 3. Call C main() function
    call main

    # 4. Infinite trap loop if main ever returns
3:  j 3b