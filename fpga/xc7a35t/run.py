#!/usr/bin/env python3
import argparse
import shlex
import subprocess
import sys
from pathlib import Path


def run_step(cmd, cwd):
    print("+", shlex.join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


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

    run_path = Path(__file__).resolve().parent / "run"

    run_step([
        sys.executable, str(run_path / "poke.py"),
        "-t", args.type,
        "-d", args.device,
        "-b", str(args.baud),
        "-a", "0xF0000000",
        "-v", "0x0",
    ], run_path)

    run_step([
        sys.executable, str(run_path / "load.py"),
        "-t", args.type,
        "-d", args.device,
        "-b", str(args.baud),
        "-f", args.filename,
        "-p", args.progargs,
    ], run_path)

    run_step([
        sys.executable, str(run_path / "console-uart.py"),
        "-t", args.type,
        "-d", args.device,
        "-b", str(args.baud),
        "-f", args.filename,
    ], run_path)


if __name__ == "__main__":
    main(sys.argv[1:])
