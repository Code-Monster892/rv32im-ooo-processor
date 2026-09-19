OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    ram : ORIGIN = 0x00000000, LENGTH = 0x01000000 /* 16MB */
}

SECTIONS {
    . = 0x00000000;
    .text.init : {
        *(.text.init)
    } > ram

    .text : {
        *(.text*)
    } > ram

    .rodata : {
        . = ALIGN(4);
        *(.rodata*)
    } > ram

    .tohost : {
        . = ALIGN(4);
        *(.tohost)
    } > ram

    .data : {
        . = ALIGN(4);
        *(.data*)
    } > ram

    .bss : {
        . = ALIGN(4);
        PROVIDE(__bss_start = .);
        *(.bss*)
        PROVIDE(__bss_end = .);
    } > ram

    _end = .;
}
