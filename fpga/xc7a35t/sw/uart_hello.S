.section .text.boot
.globl _start

.equ UART_BASE,      0x92000000
.equ ULITE_TX,       0x4
.equ ULITE_STATUS,   0x8
.equ ULITE_TXFULL,   0x8
.equ GPIO_BASE,      0x94000000
.equ GPIO_DIRECTION, 0x0
.equ GPIO_OUTPUT,    0x8

_start:
    .option push
    .option norvc

    la   sp, _stack_top

    # Enable GPIO[3:0] as outputs and light LED2/LED3.
    li   t0, GPIO_BASE
    li   t1, 0x0000000f
    sw   t1, GPIO_DIRECTION(t0)
    li   t1, 0x0000000c
    sw   t1, GPIO_OUTPUT(t0)

    la   a0, hello_msg
1:
    lbu  a1, 0(a0)
    beqz a1, 2f
    mv   a2, a1
    jal  ra, uart_putc
    addi a0, a0, 1
    j    1b

2:
    li   s0, GPIO_BASE
    li   s1, 0x00000004
    li   s2, 0x00000008

blink_loop:
    sw   s1, GPIO_OUTPUT(s0)
    jal  ra, delay
    sw   s2, GPIO_OUTPUT(s0)
    jal  ra, delay
    j    blink_loop

uart_putc:
    li   t0, UART_BASE
3:
    lw   t1, ULITE_STATUS(t0)
    andi t1, t1, ULITE_TXFULL
    bnez t1, 3b
    sw   a2, ULITE_TX(t0)
    ret

delay:
    li   t2, 25000000
4:
    addi t2, t2, -1
    bnez t2, 4b
    ret

    .option pop

.section .rodata
hello_msg:
    .asciz "xc7a35t riscv_soc v1 hello\r\n"
