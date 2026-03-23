#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path


PT_LOAD = 1


def iter_elf32_load_segments(filename):
    image = Path(filename).read_bytes()

    if len(image) < 52 or image[0:4] != b"\x7fELF":
        raise SystemExit(f"Unsupported ELF file: {filename}")
    if image[4] != 1 or image[5] != 1:
        raise SystemExit("Only ELF32 little-endian files are supported")

    e_phoff = struct.unpack_from("<I", image, 28)[0]
    e_phentsize = struct.unpack_from("<H", image, 42)[0]
    e_phnum = struct.unpack_from("<H", image, 44)[0]

    for idx in range(e_phnum):
        off = e_phoff + idx * e_phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from(
            "<IIIIIIII", image, off
        )
        if p_type != PT_LOAD or p_filesz == 0:
            continue
        yield idx, p_paddr, image[p_offset:p_offset + p_filesz]


def bytes_to_mem_words(data):
    padded = bytearray(data)
    if len(padded) % 4:
        padded.extend(b"\x00" * (4 - (len(padded) % 4)))

    for idx in range(0, len(padded), 4):
        yield f"{struct.unpack_from('<I', padded, idx)[0]:08X}"


def main():
    parser = argparse.ArgumentParser(description="Convert ELF PT_LOAD segments to JTAG .mem files")
    parser.add_argument("elf", help="Input ELF file")
    parser.add_argument("--output-dir", required=True, help="Output directory for generated .mem files")
    parser.add_argument("--prefix", default="segment", help="Generated file prefix")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest_lines = []
    for out_idx, (_, paddr, data) in enumerate(iter_elf32_load_segments(args.elf)):
        mem_path = out_dir / f"{args.prefix}_seg{out_idx}_{paddr:08X}.mem"
        with mem_path.open("w") as fp:
            for word in bytes_to_mem_words(data):
                fp.write(word + "\n")
        manifest_lines.append(f"{mem_path} 0x{paddr:08X} {len(data)}")
        print(f"Wrote {mem_path} @ 0x{paddr:08X} ({len(data)} bytes)")

    manifest_path = out_dir / f"{args.prefix}_manifest.txt"
    manifest_path.write_text("\n".join(manifest_lines) + ("\n" if manifest_lines else ""))
    print(f"Wrote manifest {manifest_path}")


if __name__ == "__main__":
    main()
