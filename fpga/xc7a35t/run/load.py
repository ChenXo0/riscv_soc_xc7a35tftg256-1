#!/usr/bin/env python3
import argparse
import struct
import sys

try:
    from elftools.elf.elffile import ELFFile
    HAVE_PYELFTOOLS = True
except ImportError as exc:
    ELFFile = None
    HAVE_PYELFTOOLS = False

from bus_interface import BusInterface


def print_progress(iteration, total, prefix='', suffix='', decimals=1, bar_length=50):
    if total <= 0:
        total = 1
    str_format = "{0:." + str(decimals) + "f}"
    percents = str_format.format(100 * (iteration / float(total)))
    filled_length = int(round(bar_length * iteration / float(total)))
    bar = 'X' * filled_length + ' ' * (bar_length - filled_length)
    sys.stdout.write(f'\r{prefix} |{bar}| {percents}% {suffix}')
    if iteration == total:
        sys.stdout.write('\n')
    sys.stdout.flush()


def load_elf(filename, bus_if):
    if HAVE_PYELFTOOLS:
        with open(filename, "rb") as elf_fp:
            elf_file = ELFFile(elf_fp)

            for seg in elf_file.iter_segments():
                load_addr = seg['p_paddr']
                length = seg['p_filesz']
                data = seg.data()
                if data:
                    print(f"ELF: Loading 0x{load_addr:x} - size {(length + 1023) // 1024}KB")
                    bus_if.write(load_addr, bytearray(data), length)
        return

    for load_addr, data in iter_elf32_load_segments(filename):
        length = len(data)
        if length:
            print(f"ELF: Loading 0x{load_addr:x} - size {(length + 1023) // 1024}KB")
            bus_if.write(load_addr, bytearray(data), length)


def iter_elf32_load_segments(filename):
    with open(filename, "rb") as elf_fp:
        image = elf_fp.read()

    if len(image) < 52 or image[0:4] != b"\x7fELF":
        raise SystemExit(f"Unsupported ELF file: {filename}")
    if image[4] != 1 or image[5] != 1:
        raise SystemExit("Only ELF32 little-endian files are supported without pyelftools")

    e_phoff = struct.unpack_from("<I", image, 28)[0]
    e_phentsize = struct.unpack_from("<H", image, 42)[0]
    e_phnum = struct.unpack_from("<H", image, 44)[0]

    for idx in range(e_phnum):
        off = e_phoff + idx * e_phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from(
            "<IIIIIIII", image, off
        )
        if p_type != 1 or p_filesz == 0:
            continue
        yield p_paddr, image[p_offset:p_offset + p_filesz]


def find_symbol(filename, symbolname, unfound_value=0xFFFFFFFF):
    if not HAVE_PYELFTOOLS:
        return unfound_value
    try:
        with open(filename, "rb") as elf_fp:
            elf_file = ELFFile(elf_fp)
            symtab = elf_file.get_section_by_name(".symtab")
            if symtab is None:
                return unfound_value

            for sym in symtab.iter_symbols():
                if sym.name == symbolname:
                    return sym['st_value']
        return unfound_value
    except Exception:
        return unfound_value


def load_prog_args(filename, bus_if, args):
    args = args.strip()
    if args == "":
        return

    arg_list = []
    for item in args.split('-'):
        item = item.strip()
        if item != "":
            arg_list.append("-" + item)

    arg_argc_addr = find_symbol(filename, "arg_argc")
    arg_argv_addr = find_symbol(filename, "arg_argv")

    if arg_argc_addr != 0xFFFFFFFF and arg_argv_addr != 0xFFFFFFFF:
        argc = len(arg_list)
        bus_if.write32(arg_argc_addr, argc)

        offset = arg_argv_addr
        str_offset = offset + 4 * argc
        for arg in arg_list:
            buf = bytearray(arg.encode("utf-8"))
            buf.extend(b"\0")
            bus_if.write32(offset, str_offset)
            bus_if.write(str_offset, buf, len(buf))
            str_offset += len(buf)
            offset += 4


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('-t', dest='type', default='uart',
                        help='Device type (uart|ftdi)')
    parser.add_argument('-d', dest='device', default='/dev/ttyUSB1',
                        help='Serial Device')
    parser.add_argument('-b', dest='baud', default=1000000, type=int,
                        help='Baud rate')
    parser.add_argument('-f', dest='filename', required=True,
                        help='File to load')
    parser.add_argument('-p', dest='progargs', default='',
                        help='Program load argument string')
    args = parser.parse_args(argv)

    if not HAVE_PYELFTOOLS and args.progargs.strip():
        print("Warning: program arguments require pyelftools; ignoring -p without it.", file=sys.stderr)
        args.progargs = ''

    bus_if = BusInterface(args.type, args.device, args.baud)
    bus_if.set_progress_cb(print_progress)

    load_elf(args.filename, bus_if)
    bus_if.set_progress_cb(None)
    load_prog_args(args.filename, bus_if, args.progargs)


if __name__ == "__main__":
    main(sys.argv[1:])
