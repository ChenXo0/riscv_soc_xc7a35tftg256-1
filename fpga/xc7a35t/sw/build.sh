#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLVM_BIN_DEFAULT="/home/cx/llvm/build-vortex_2.x-rv32/bin"
LLVM_BIN="${LLVM_BIN:-$LLVM_BIN_DEFAULT}"

CLANG="${CLANG:-$LLVM_BIN/clang}"
READELF="${READELF:-$LLVM_BIN/llvm-readelf}"
OBJCOPY="${OBJCOPY:-$LLVM_BIN/llvm-objcopy}"

OUT_ELF="$SCRIPT_DIR/uart_hello.elf"
OUT_MAP="$SCRIPT_DIR/uart_hello.map"
OUT_BIN="$SCRIPT_DIR/uart_hello.bin"
OUT_MEM="$SCRIPT_DIR/uart_hello.mem"
OUT_JTAG_MEM="$SCRIPT_DIR/uart_hello_jtag.mem"
OUT_VH="$SCRIPT_DIR/uart_hello_mem.vh"

"$CLANG" \
  --target=riscv32-unknown-elf \
  -march=rv32ima_zicsr \
  -mabi=ilp32 \
  -nostdlib \
  -ffreestanding \
  -fno-pic \
  -Wl,-T,"$SCRIPT_DIR/link.ld" \
  -Wl,-Map,"$OUT_MAP" \
  -Wl,--no-relax \
  -o "$OUT_ELF" \
  "$SCRIPT_DIR/uart_hello.S"

"$OBJCOPY" -O binary "$OUT_ELF" "$OUT_BIN"

python3 - <<PY
from pathlib import Path
import struct

bin_path = Path(r"$OUT_BIN")
mem_path = Path(r"$OUT_MEM")
jtag_mem_path = Path(r"$OUT_JTAG_MEM")
vh_path = Path(r"$OUT_VH")
data = bin_path.read_bytes()
pad = (-len(data)) % 4
if pad:
    data += b"\x00" * pad
words = [struct.unpack_from("<I", data, i)[0] for i in range(0, len(data), 4)]
mem_text = "\n".join(f"{w:08x}" for w in words) + ("\n" if words else "")
mem_path.write_text(mem_text, encoding="utf-8")
jtag_mem_path.write_text(mem_text, encoding="utf-8")
vh_path.write_text(
    "".join(f"    ram[{idx}] = 32'h{word:08x};\n" for idx, word in enumerate(words)),
    encoding="utf-8",
)
print(f"Generated: {mem_path}")
print(f"Generated: {jtag_mem_path}")
print(f"Generated: {vh_path}")
PY

echo "Generated: $OUT_ELF"
"$READELF" -l "$OUT_ELF"
