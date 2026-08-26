/* src/cat.ld — cat linker script (ENH-001, paideia-os/cat #17).
 *
 * Mirrors the paideia-os monorepo's src/user/*.ld family byte-for-
 * byte (see src/user/cat.ld / true.ld / shell/link.ld there): text at
 * 0x00400000, data at 0x00600000, bss contiguous with data (the
 * R31.M2-1595 rule — no `. = 0x00700000;` between .data and .bss).
 *
 * Unlike the monorepo's cat.ld (which links exactly one object,
 * because that cat.pdx is self-contained), this cat is nine modules
 * (ArgvDispatch, FileRead, TtySink, Render, AuditStub, FileSchema,
 * PipeOut, RawByteChunk, StdinSource) plus the Entry module's
 * _start — tools/build.sh links every src/*.o produced by
 * `paideia-as build --emit elf64` against this script. Nothing below
 * is otherwise object-count-sensitive: `*(.text .text.*)` and
 * `*(.rodata .rodata.*)` fold in every object's sections regardless
 * of how many there are.
 */

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x00400000;

    .text : ALIGN(4K) {
        KEEP(*(.text._start))
        *(.text .text.*)
    } :text

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    } :text

    . = 0x00600000;

    .data : ALIGN(4K) {
        *(.data .data.*)
    } :data

    /* R31.M2-1595 (#1595): .bss follows .data CONTIGUOUSLY -- there is
     * no `. = 0x00700000;` here, and there must not be one. This
     * repo's .bss footprint is not small (FileRead::fr_chunk_buf +
     * TtySink::tty_out_buf are each 64 KiB, plus the smaller per-
     * module singleton state) -- the contiguity rule is what keeps
     * that from opening a multi-hundred-KiB PT_LOAD hole.
     */
    .bss (NOLOAD) : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
        . = ALIGN(4K);
    } :data

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame*)
        *(.note.*)
    }
}
