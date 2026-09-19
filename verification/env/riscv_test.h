#ifndef _ENV_PHYSICAL_SINGLE_CORE_H
#define _ENV_PHYSICAL_SINGLE_CORE_H

#define RVTEST_RV32U
#define RVTEST_RV64U
#define RVTEST_RV32M
#define RVTEST_RV64M

#define TESTNUM gp

#define RVTEST_CODE_BEGIN \
    .section .text.init; \
    .align 4; \
    .globl _start; \
_start: \
    li TESTNUM, 0;

#define RVTEST_CODE_END

#define RVTEST_PASS \
    fence; \
    li TESTNUM, 1; \
    la t0, tohost; \
    sw TESTNUM, 0(t0); \
1:  j 1b;

#define RVTEST_FAIL \
    fence; \
1:  beqz TESTNUM, 1b; \
    sll TESTNUM, TESTNUM, 1; \
    or  TESTNUM, TESTNUM, 1; \
    la  t0, tohost; \
    sw  TESTNUM, 0(t0); \
2:  j   2b;

#define RVTEST_DATA_BEGIN \
    .pushsection .tohost, "aw", @progbits; \
    .align 6; \
    .globl tohost; tohost: .dword 0; \
    .globl fromhost; fromhost: .dword 0; \
    .popsection; \
    .data; \
    .align 4; \
    .globl begin_signature; begin_signature:

#define RVTEST_DATA_END \
    .align 4; \
    .globl end_signature; end_signature:

#endif
