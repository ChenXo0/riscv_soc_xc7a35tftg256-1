from uart_bus_interface import UartBusInterface


class BusInterface:
    def __init__(self, iface_type='uart', iface='/dev/ttyUSB1', baud=115200):
        if iface_type == "uart":
            self.bus = UartBusInterface(iface, baud)
        else:
            self.bus = None

    def set_progress_cb(self, prog_cb):
        self.bus.set_progress_cb(prog_cb)

    def open(self):
        pass

    def close(self):
        pass

    def write(self, addr, data, length, addr_incr=True, max_block_size=-1):
        self.bus.write(addr, data, length, addr_incr, max_block_size)

    def read(self, addr, length, addr_incr=True, max_block_size=-1):
        return self.bus.read(addr, length, addr_incr, max_block_size)

    def read32(self, addr):
        return self.bus.read32(addr)

    def write32(self, addr, value):
        return self.bus.write32(addr, value)

    def read_gpio(self):
        return self.bus.read_gpio()

    def write_gpio(self, value):
        return self.bus.write_gpio(value)
