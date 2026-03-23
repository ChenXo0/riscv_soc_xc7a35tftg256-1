try:
    import serial
except ImportError as exc:
    raise SystemExit(
        "Missing dependency 'pyserial'. "
        "Install it with: python3 -m pip install pyserial"
    ) from exc


class UartBusInterface:
    def __init__(self, iface='/dev/ttyUSB1', baud=115200):
        self.interface = iface
        self.baud = baud
        self.uart = None
        self.prog_cb = None
        self.CMD_WRITE = 0x10
        self.CMD_READ = 0x11
        self.MAX_SIZE = 255
        self.BLOCK_SIZE = 128
        self.GPIO_ADDR = 0xF0000000
        self.STS_ADDR = 0xF0000004

    def set_progress_cb(self, prog_cb):
        self.prog_cb = prog_cb

    def connect(self):
        self.uart = serial.Serial(
            port=self.interface,
            baudrate=self.baud,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            bytesize=serial.EIGHTBITS,
            timeout=1.0,
            write_timeout=1.0,
        )
        if not self.uart.is_open:
            self.uart.open()

    def read32(self, addr):
        if self.uart is None:
            self.connect()

        cmd = bytearray([
            self.CMD_READ,
            4,
            (addr >> 24) & 0xFF,
            (addr >> 16) & 0xFF,
            (addr >> 8) & 0xFF,
            (addr >> 0) & 0xFF,
        ])
        self.uart.write(cmd)

        value = 0
        idx = 0
        while idx < 4:
            value |= (self.uart.read(1)[0] << (idx * 8))
            idx += 1

        return value

    def write32(self, addr, value):
        if self.uart is None:
            self.connect()

        cmd = bytearray([
            self.CMD_WRITE,
            4,
            (addr >> 24) & 0xFF,
            (addr >> 16) & 0xFF,
            (addr >> 8) & 0xFF,
            (addr >> 0) & 0xFF,
            (value >> 0) & 0xFF,
            (value >> 8) & 0xFF,
            (value >> 16) & 0xFF,
            (value >> 24) & 0xFF,
        ])
        self.uart.write(cmd)

    def write(self, addr, data, length, addr_incr=True, max_block_size=-1):
        if self.uart is None:
            self.connect()

        idx = 0
        remainder = length

        if self.prog_cb is not None:
            self.prog_cb(0, length)

        if max_block_size == -1:
            max_block_size = self.BLOCK_SIZE

        while remainder > 0:
            block_len = min(max_block_size, remainder)

            cmd = bytearray(2 + 4 + block_len)
            cmd[0] = self.CMD_WRITE
            cmd[1] = block_len & 0xFF
            cmd[2] = (addr >> 24) & 0xFF
            cmd[3] = (addr >> 16) & 0xFF
            cmd[4] = (addr >> 8) & 0xFF
            cmd[5] = (addr >> 0) & 0xFF

            for i in range(block_len):
                cmd[6 + i] = data[idx]
                idx += 1

            self.uart.write(cmd)

            if self.prog_cb is not None:
                self.prog_cb(idx, length)

            if addr_incr:
                addr += block_len
            remainder -= block_len

    def read(self, addr, length, addr_incr=True, max_block_size=-1):
        if self.uart is None:
            self.connect()

        idx = 0
        remainder = length
        data = bytearray(length)

        if self.prog_cb is not None:
            self.prog_cb(0, length)

        if max_block_size == -1:
            max_block_size = self.BLOCK_SIZE

        while remainder > 0:
            block_len = min(max_block_size, remainder)

            cmd = bytearray(2 + 4)
            cmd[0] = self.CMD_READ
            cmd[1] = block_len & 0xFF
            cmd[2] = (addr >> 24) & 0xFF
            cmd[3] = (addr >> 16) & 0xFF
            cmd[4] = (addr >> 8) & 0xFF
            cmd[5] = (addr >> 0) & 0xFF

            self.uart.write(cmd)

            for _ in range(block_len):
                data[idx] = self.uart.read(1)[0]
                idx += 1

            if self.prog_cb is not None:
                self.prog_cb(idx, length)

            if addr_incr:
                addr += block_len
            remainder -= block_len

        return data

    def read_gpio(self):
        return self.read32(self.GPIO_ADDR)

    def write_gpio(self, value):
        self.write32(self.GPIO_ADDR, value)
