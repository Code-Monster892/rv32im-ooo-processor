OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY {
    ram : ORIGIN = 0x00000000, LENGTH = 0x01000000 /* 16MB of RAM */
}

SECTIONS {
    .text : {
        *(.init)       /* Ensures crt0.s _start is placed at address 0x00000000 */
        *(.text*)
    } > ram

    .rodata : {
        . = ALIGN(4);
        *(.rodata*)
        *(.srodata*)
    } > ram

    .data : {
        . = ALIGN(4);
        *(.data*)
        *(.sdata*)
    } > ram

    .bss : {
        . = ALIGN(4);
        PROVIDE(__bss_start = .);
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        PROVIDE(__bss_end = .);
    } > ram
}
