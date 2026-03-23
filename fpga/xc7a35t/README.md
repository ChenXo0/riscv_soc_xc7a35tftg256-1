# XC7A35T FTG256 port

这个目录包含 `riscv_soc` 面向 **XC7A35T-FTG256-1** 板卡的移植版本。

当前已经落地并验证了两条路径：

1. **V1 bring-up**
   - 纯 JTAG 下载 / 控制
   - 通过 `jtag_axi + axi_protocol_converter` 暴露 `hw_axi`
   - 通过 `0xF0000000` 控制 CPU reset
   - 通过 JTAG 向主存窗口写入程序

2. **V2 DDR + Linux**
   - 恢复 DDR3
   - 支持 50MHz Linux 镜像
   - 支持 **JTAG-only Linux console**
   - 无需外接 UART 线即可读取 console 并向 shell 注入命令

## 当前状态

- 目标器件：`xc7a35tftg256-1`
- 系统主频：`50MHz`
- DDR3 Linux 路径已可用
- 时序已收敛
  - `WNS > 0`
  - `WHS > 0`
- 当前推荐使用 **JTAG console** 与 Linux 交互

## 关键文档

- 迁移规划：
  - `../README_xc7a35t_port_plan.md`
- JTAG console 设计说明：
  - `JTAG_CONSOLE_V1.md`
- 当前完整操作流程：
  - `JTAG_LINUX_CURRENT_FLOW.md`
- DDR AXI 宽度修复说明：
  - `V2_DDR_AXI_WIDTH_FIX.md`

## 关键文件

- `top.v`
  - 当前板级顶层
- `fpga_top.v`
  - SoC / debug / bridge 顶层
- `xc7a35t_ddr_axi.v`
  - DDR3 / MIG / AXI 路径封装
- `jtag_axil_bridge.v`
  - JTAG AXI 本地调试寄存器桥
- `build.tcl`
  - Vivado batch 构建
- `program_top_1m.tcl`
  - 1MHz JTAG 下载 bitstream
- `jtag_console_v2.tcl`
  - JTAG console attach / load / command inject
- `jtag_linux_session.sh`
  - 常驻 Vivado 会话方式执行 Linux 命令

## 目录补充

- `ip/`
  - DDR3 MIG / PLL / CDC IP 定义
- `run.py`, `run/`
  - 兼容原有 UART 下载路径的 Python 3 脚本
- `sw/`
  - 小型 bring-up 示例程序与构建脚本

## 快速开始

### 1. 构建

```bash
cd /home/cx/riscv_soc/fpga/xc7a35t
vivado -mode batch -source build.tcl
```

### 2. 下载 bitstream

```bash
cd /home/cx/riscv_soc/fpga/xc7a35t
vivado -mode batch -source program_top_1m.tcl
```

### 3. JTAG 交互查看 Linux 版本

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd cat /proc/version
```

### 4. 进入持续交互会话

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh
```

进入后可直接执行：

```text
ls /
cat /proc/version
dmesg | tail
:quit
```

## 说明

当前 Linux 交互本质上是：

- Vivado `hw_axi`
- 通过 JTAG 访问 FPGA 内一小段 console/debug CSR
- `jtag_axil_bridge` 把 Linux UART TX 缓存出来
- 同时把写入的字符注入 UART RX

因此这是 **JTAG shell / JTAG console**，不是板上原生 `ssh`。
