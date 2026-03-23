#!/usr/bin/env python3
import argparse
import sys

from bus_interface import BusInterface
from stdio import stdio_init, stdio_read


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('-t', dest='type', default='uart',
                        help='Device type (uart|ftdi)')
    parser.add_argument('-d', dest='device', default='/dev/ttyUSB1',
                        help='Serial Device')
    parser.add_argument('-b', dest='baud', default=1000000, type=int,
                        help='Baud rate')
    parser.add_argument('-f', dest='filename', required=True,
                        help='File to load symbols from')
    args = parser.parse_args(argv)

    bus_if = BusInterface(args.type, args.device, args.baud)

    # Keep CPU in reset during setup, then release it.
    bus_if.write_gpio(0x0)
    bus_if.write_gpio(0x1)

    stdio_init()

    try:
        while True:
            if bus_if.bus.uart.in_waiting > 0:
                ch = bus_if.bus.uart.read(1)
                if ch:
                    sys.stdout.buffer.write(ch)
                    sys.stdout.buffer.flush()

            ch = stdio_read()
            if ch is not None:
                bus_if.bus.uart.write(ch)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main(sys.argv[1:])
