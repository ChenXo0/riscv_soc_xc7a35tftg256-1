# XC7A35T 当前 JTAG Linux 执行完整流程

本文档记录**当前已经验证可用**的 XC7A35T + DDR + Linux + JTAG console 执行流程。

当前状态：

- DDR 版本 bitstream 已可用
- 时序已收敛
  - WNS > 0
  - WHS > 0
- Linux 可启动
- 可通过 **JTAG** 与 Linux shell 交互
- 无需 UART 线

---

## 1. 当前环境

### 本地 Linux 主机

- 工程目录：
  - `/home/cx/riscv_soc/fpga/xc7a35t`

### 远端 Windows Vivado 主机

- SSH：
  - `Administrator@100.125.4.76`
- Vivado：
  - `E:\vivado\2025.1\Vivado\settings64.bat`
- 工程目录：
  - `E:\fpga\repo\riscv_soc\fpga\xc7a35t`

### 板卡 / JTAG

- hw_server target:
  - `TCP:192.168.0.171:51235`
- 当前只通过 **JTAG** 交互
- 不使用 `127.0.0.1`

---

## 2. 当前关键文件

### bitstream / checkpoint

- 远端 bit:
  - `E:\fpga\repo\riscv_soc\fpga\xc7a35t\top.bit`
- 远端 probes:
  - `E:\fpga\repo\riscv_soc\fpga\xc7a35t\top.ltx`
- 远端 routed dcp:
  - `E:\fpga\repo\riscv_soc\fpga\xc7a35t\build\top_routed.dcp`
- 远端 timing report:
  - `E:\fpga\repo\riscv_soc\fpga\xc7a35t\build\top_timing_summary.rpt`

### Linux 镜像分段

这些文件不是手工维护源码，而是由：

- `images/linux_riscv_soc_50m.elf`
- `fpga/xc7a35t/elf_to_mem_segments.py`

生成到：

- `fpga/xc7a35t/build/linux_50m_segments/`

当前生成结果名称为：

- `linux_riscv_soc_50m_seg0_80000000.mem`
- `linux_riscv_soc_50m_seg1_80400000.mem`
- `linux_riscv_soc_50m_seg2_81F00000.mem`
- manifest:
  - `linux_riscv_soc_50m_manifest.txt`

### JTAG / console 脚本

- 下载 bit:
  - `program_top_1m.tcl`
- 通用 JTAG console:
  - `jtag_console_v2.tcl`
- 单命令封装 Tcl:
  - `jtag_exec_cmd.tcl`
- 单命令本地脚本:
  - `jtag_linux_cmd.sh`
- 常驻 Vivado 会话 Tcl:
  - `jtag_vivado_session.tcl`
- 常驻 Vivado 本地会话脚本:
  - `jtag_linux_session.sh`

---

## 3. 当前推荐工作流

分成 4 步：

1. 构建 bitstream
2. 下载 bitstream
3. 通过 JTAG 装载 Linux
4. 通过 JTAG 与 Linux 交互

---

## 3.1 当前工具链流程图（从本地调用一直到 FPGA）

下面画的是**当前实际在用**的两条主路径：

- 路径 A：**构建 / 下载 bitstream**
- 路径 B：**运行时 JTAG Linux 交互**

---

### A. 构建 / 下载路径

```text
本地 Linux 终端
    │
    ├─ 修改 RTL / Tcl
    │    └─ /home/cx/riscv_soc/fpga/xc7a35t/*
    │
    ├─ scp / ssh
    ▼
远端 Windows 主机
    │   Administrator@100.125.4.76
    │
    ├─ Vivado 2025.1
    │    └─ E:\vivado\2025.1\Vivado\settings64.bat
    │
    ├─ build.tcl
    │    └─ 综合 / 实现 / 写 bitstream / 写 dcp
    │
    ├─ program_top_1m.tcl
    │    └─ 连接 hw_server / open_hw_target / program_hw_devices
    │
    ▼
hw_server
    │
    ▼
Digilent JTAG
    │
    ▼
XC7A35T FPGA
    │
    ├─ 下载 top.bit / top.ltx
    └─ 板上逻辑运行
```

---

### B. 当前推荐运行时路径（V2：常驻 Vivado 会话）

```text
本地 Linux 终端
    │
    ├─ jtag_linux_session.sh
    │    ├─ 交互模式
    │    └─ --cmd 单命令模式
    │
    └─ 通过 ssh -T 建立一个远端长连接
         （脚本退出时自动清理）
    ▼
远端 Windows 主机
    │
    ├─ cmd /c
    ├─ call settings64.bat
    └─ vivado -mode tcl -source jtag_vivado_session.tcl
            │
            ├─ open_hw_manager
            ├─ connect_hw_server
            ├─ open_hw_target
            ├─ 获取 JTAG AXI handle
            └─ 常驻等待本地命令
            │
            ├─ 收到本地命令
            ├─ 转成 TX 字节流
            ├─ 写入 CONSOLE_RX_ADDR
            └─ 轮询 CONSOLE_ADDR 取回输出
    ▼
hw_server
    │
    ▼
Digilent JTAG
    │
    ▼
FPGA 内部 JTAG 调试通路
    │
    ├─ JTAG AXI Master
    ├─ jtag_axil_bridge
    ├─ dbg regs / console regs
    └─ UART-like RX/TX 注入/回读
    ▼
SoC / Linux
    │
    ├─ shell 接收命令
    ├─ 执行 ls / cat / uname 等命令
    └─ 输出回到 console FIFO
    ▼
沿原路径返回到本地终端显示
```

---

### C. V1 和 V2 的差别

#### V1：`jtag_linux_cmd.sh`

```text
本地命令
  → SSH
    → 远端 Vivado batch 启动一次
      → JTAG 发一条命令
        → 取回输出
          → Vivado 退出
```

特点：

- 简单
- 一次一条命令
- 每次都会重新启动 Vivado

#### V2：`jtag_linux_session.sh`

```text
本地启动一次会话
  → SSH
    → 远端 Vivado 常驻
      → 连续执行多条 Linux 命令
        → 本地退出
          → 远端 Vivado 自动结束
```

特点：

- 当前推荐
- 同一会话内不重复启动 Vivado
- 本地脚本退出时自动清理远端进程

---

### D. FPGA 内部当前交互链路

从命令真正进入 FPGA 内部的角度看，可以理解为：

```text
本地 shell 命令
    ↓
本地脚本封装为字符串 / HEX
    ↓
远端 Vivado Tcl
    ↓
JTAG AXI 访问调试寄存器
    ↓
CONSOLE_RX_ADDR 写入字符
    ↓
jtag_axil_bridge
    ↓
SoC 内部 UART 注入接口
    ↓
Linux shell
    ↓
Linux 输出字符
    ↓
SoC console status/data 寄存器
    ↓
Vivado Tcl 轮询 CONSOLE_ADDR
    ↓
本地终端显示
```

---

### E. JTAG console 内部实现细化图

下面是更细一层的 **JTAG console 内部结构图**。

```text
Vivado Tcl
    │
    ├─ create_hw_axi_txn / run_hw_axi
    │
    ▼
JTAG AXI Master (Vivado / hw_axi)
    │
    ▼
jtag_axi IP
    │
    ▼
axi_protocol_converter
    │
    ▼
jtag_axil_bridge
    │
    ├──────────────────────────────────────────────┐
    │                                              │
    │  TX 回读路径（Linux -> 本地）                │
    │                                              │
    │   Linux printk / shell output                │
    │        ↓                                     │
    │   uart_lite tx_wr_o / tx_data_o              │
    │        ↓                                     │
    │   jtag_axil_bridge console FIFO              │
    │        ↓                                     │
    │   读 0xF000000C（CONSOLE_TX）                │
    │        ↓                                     │
    │   Tcl 解码 valid / level / char              │
    │        ↓                                     │
    │   本地终端显示                               │
    │                                              │
    └──────────────────────────────────────────────┘
    │
    ├──────────────────────────────────────────────┐
    │                                              │
    │  RX 注入路径（本地 -> Linux）                │
    │                                              │
    │   Tcl 把命令转成字节流                       │
    │        ↓                                     │
    │   写 0xF0000010（CONSOLE_RX）                │
    │        ↓                                     │
    │   rx_inject_pending_q / rx_inject_data_q     │
    │        ↓                                     │
    │   uart_rx_valid_o / uart_rx_data_o           │
    │        ↓                                     │
    │   riscv_soc debug_uart_rx_inject_*           │
    │        ↓                                     │
    │   uart_lite inject_rx_valid_i/data_i         │
    │        ↓                                     │
    │   UART RX 数据寄存器                         │
    │        ↓                                     │
    │   Linux shell 收到字符                       │
    │                                              │
    └──────────────────────────────────────────────┘
```

---

### F. CONSOLE 寄存器语义

#### `0xF000000C` : CONSOLE_TX

读返回：

```text
bit[31]    overflow
bit[30]    valid
bit[29:16] level
bit[15:8]  reserved
bit[7:0]   current char
```

语义：

- `valid=1` 表示 FIFO 非空
- 本次读会把当前字符 **pop** 掉
- `level` 表示 FIFO 当前积压字节数
- `overflow=1` 表示 FIFO 曾经满过

写语义：

- 写 `bit31=1`：清 overflow

#### `0xF0000010` : CONSOLE_RX

读返回：

```text
bit[31]    rx_overflow
bit[30]    pending
bit[29]    ready
bit[7:0]   last/data char
```

写语义：

- `bit[7:0]`：写入一个要注入 Linux UART RX 的字符
- `bit[31]=1`：清除 RX overflow

Tcl 在发送字符前会先看：

- `pending`
- `ready`

确保不会把新的字符覆盖掉还没被 UART 消费的旧字符。

---

### G. 当前为什么能“像串口一样”工作

因为 Linux 实际看到的是：

- 自己的 `ttyUL0`
- `ttyUL0` 的 RX 数据寄存器被写入了字符
- `ttyUL0` 的 TX 字符又被外部读走了

所以从 Linux 角度看，这依然像是一个正常 UART console。

只是物理上不是：

- USB-UART 线
- 板外串口

而是：

- JTAG + AXI 寄存器桥

---

## 4. 构建 bitstream

### 本地改 RTL / Tcl

主要文件：

- `top.v`
- `build.tcl`
- 以及相关 SoC/bridge 文件

### 同步到远端

示例：

```bash
scp -o StrictHostKeyChecking=no \
  /home/cx/riscv_soc/fpga/xc7a35t/top.v \
  /home/cx/riscv_soc/fpga/xc7a35t/build.tcl \
  Administrator@100.125.4.76:

ssh -o StrictHostKeyChecking=no Administrator@100.125.4.76 \
  "cmd /c \"copy /Y %USERPROFILE%\\top.v E:\\fpga\\repo\\riscv_soc\\fpga\\xc7a35t\\top.v && copy /Y %USERPROFILE%\\build.tcl E:\\fpga\\repo\\riscv_soc\\fpga\\xc7a35t\\build.tcl\""
```

### 远端构建

```bash
ssh -o StrictHostKeyChecking=no Administrator@100.125.4.76 \
  "cmd /c \"cd /d E:\\fpga\\repo\\riscv_soc\\fpga\\xc7a35t && call E:\\vivado\\2025.1\\Vivado\\settings64.bat && vivado -mode batch -source build.tcl\""
```

### 当前已验证结果

- Timing Summary:
  - WNS = `+0.091 ns`
  - WHS = `+0.051 ns`

---

## 5. 下载 bitstream 到板卡

使用远端脚本：

```bash
ssh -o StrictHostKeyChecking=no Administrator@100.125.4.76 \
  "cmd /c \"cd /d E:\\fpga\\repo\\riscv_soc\\fpga\\xc7a35t && call E:\\vivado\\2025.1\\Vivado\\settings64.bat && vivado -mode batch -source program_top_1m.tcl\""
```

### 成功标志

输出里应看到：

- `PROGRAM_DONE`
- `HW_AXIS_COUNT=1`
- `VERSION=4A544731`

---

## 6. 通过 JTAG 装载 Linux

### 推荐方式

直接用 `jtag_console_v2.tcl` 装载 Linux 分段，并顺带抓启动日志。

命令：

```bash
ssh -o StrictHostKeyChecking=no Administrator@100.125.4.76 \
  "cmd /v /c \"cd /d E:\\fpga\\repo\\riscv_soc\\fpga\\xc7a35t && call E:\\vivado\\2025.1\\Vivado\\settings64.bat && set JTAG_FREQ_HZ=1000000 && set MAX_BURST_WORDS=256 && set POLL_MS=5 && set MAX_IDLE_LOOPS=8000 && set MAX_DRAIN_READS=2048 && vivado -mode batch -source jtag_console_v2.tcl -tclargs linux_riscv_soc_50m_seg0_80000000.mem 0x80000000 linux_riscv_soc_50m_seg1_80400000.mem 0x80400000 linux_riscv_soc_50m_seg2_81F00000.mem 0x81F00000\""
```

### 预期输出

启动日志会跑到类似：

```text
Run /init as init process
Running init script
Please press Enter to activate this console.
```

---

## 7. 与 Linux 交互：两种方式

---

## 7.1 方式 A：单命令执行（V1）

脚本：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh
```

### 功能

- 启动一个后台 SSH master
- 每次发一条命令到远端
- 远端 Vivado batch 执行一次
- 适合“偶尔发一条命令”

### 常用命令

启动 SSH master：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh --start-master
```

执行命令：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh ls /
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh cat /proc/version
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh uname -a
```

附着看 console：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh --attach
```

关闭 SSH master：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_cmd.sh --stop-master
```

### 缺点

- 每次命令仍会重新启动一次 Vivado
- 单条命令延迟较大

---

## 7.2 方式 B：常驻 Vivado 会话（V2，当前推荐）

脚本：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh
```

### 功能

- 一个本地脚本生命周期内，只启动一次远端 Vivado
- 同一会话中连续执行多条 Linux 命令
- 退出本地脚本时，自动结束远端 `vivado.exe` 和 `hw_server.exe`

### 交互模式

进入会话：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh
```

进入后直接输入：

```text
ls /
cat /proc/version
uname -a
```

退出：

```text
:quit
```

其他 meta 命令：

```text
:ping
:help
```

### 单条命令模式

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd ls /
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd cat /proc/version
```

也可以直接：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh uname -a
```

### 当前已验证

已验证同一会话内连续执行：

- `ls /`
- `cat /proc/version`

并验证：

- 会话运行中，远端存在 `vivado.exe`
- 本地脚本退出后，远端 `vivado.exe` 自动结束

---

## 8. 查看 Linux 版本

推荐：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd cat /proc/version
```

或：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd uname -a
```

当前实测输出：

```text
Linux version 4.20.0-44635-gfe575c9 (rob@macmini) (gcc version 7.2.0 (GCC)) #77 Wed Mar 27 22:12:24 GMT 2019
```

---

## 9. 当前系统限制说明

### 9.1 这不是 SSH 登录 Linux

当前方案本质上是：

- 本地 shell
- SSH 到远端 Windows
- 远端 Vivado
- JTAG AXI / JTAG console
- Linux shell

所以它是：

- **JTAG shell / JTAG console**

不是：

- 真正的 `ssh root@board`

---

### 9.2 为什么 `gcc -v` 不行

因为当前 rootfs 是精简系统，板上**没有 gcc**。

`gcc -v` 返回：

```text
/bin/sh: gcc: not found
```

这是系统镜像内容决定的，不是 JTAG 问题。

---

### 9.3 为什么 `df .` / `df /` 不行

当前系统是非常精简的 BusyBox/rootfs 形式，挂载视图不是标准完整发行版那种块设备根文件系统形态，因此 BusyBox `df` 可能报：

```text
df: .: can't find mount point
df: /: can't find mount point
```

这不代表 Linux 没起来，只代表：

- rootfs 太精简
- `df` 对 mount point 的解析不适配当前 rootfs 形式

---

## 10. 常用命令建议

### 查看版本

```bash
cat /proc/version
uname -a
```

### 查看内存

```bash
free
cat /proc/meminfo
```

### 查看进程

```bash
ps
```

### 查看日志

```bash
dmesg
dmesg | tail
```

### 查看 rootfs 内容

```bash
ls /
ls /bin
ls /usr
```

---

## 11. 常见故障与处理

### 11.1 `Unable to connect to hw_server`

现象：

```text
Unable to connect to hw_server with URL "TCP:192.168.0.171:51235"
```

处理：

- 重新运行会话脚本
- 当前 V2 Tcl 已带自动重连 / 重启 hw_server 逻辑

---

### 11.2 `Cannot support out-of-date hw_server`

现象：

```text
Cannot support an older version of hw_server
```

处理：

- 杀掉旧的 `hw_server.exe`
- 用 `Vivado 2025.1` 自带 hw_server 重新拉起

当前 V2 路径已尽量自动处理此问题。

---

### 11.3 启动日志中 `OVERFLOW_SEEN=1`

表示启动高峰期 console FIFO 有轻微溢出。

现状：

- 不影响 Linux 启动
- 不影响 shell 命令交互

---

## 12. 当前推荐日常使用方式

### 如果只是偶尔发一条命令

用：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd <command>
```

例如：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh --cmd cat /proc/version
```

### 如果要连续调试

用：

```bash
/home/cx/riscv_soc/fpga/xc7a35t/jtag_linux_session.sh
```

进入交互会话后连续输入：

```text
ls /
cat /proc/version
dmesg | tail
:quit
```

这是当前最推荐路径。
