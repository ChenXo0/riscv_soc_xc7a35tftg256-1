ENTRY(_start)

MEMORY
{
    ram (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.text.boot))
        *(.text*)
        *(.rodata*)
    } > ram

    .data : ALIGN(4)
    {
        *(.data*)
    } > ram

    .bss : ALIGN(4)
    {
        *(.bss*)
        *(COMMON)
    } > ram

    . = ALIGN(16);
    _end = .;
    _stack_top = ORIGIN(ram) + LENGTH(ram) - 4;
}
