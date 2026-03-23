# XC7A35T JTAG Console V1 方案

## 目标

在**只有 JTAG、没有 UART 线**的板卡条件下，给当前 `xc7a35t` SoC 增加一个最小可用的 console 观察通道：

- **V1 只做 TX-only**
- 把 Linux / bare-metal 写到 UART TX 的字节镜像到一个 **JTAG 可读 FIFO**
- 不改 Linux DTS / bootargs
- 不改变板外 `uart_txd` 引脚行为

本版目标是先解决：

> “能不能不插 UART 线，只靠 JTAG 看 console 输出？”

答案：**可以，但先做只读输出，不做键盘输入。**

---

## 设计思路

当前 Linux console 仍然是：

- `ttyUL0`
- UART Lite base: `0x92000000`
- 波特率：`1000000`

V1 不去解串行波形，也不依赖 ILA 抓 `uart_txd`。

而是在 UART Lite 内部，当软件向 TX 寄存器写入一个字节时：

1. 正常送往原 UART 发送器
2. 同时把这个字节镜像到一个 **JTAG local FIFO**

这样 JTAG 端通过已有 `jtag_axil_bridge` 读取一个本地寄存器，就能把 console 字节取走。

---

## 为什么先做 V1

相比完整双向 JTAG console，V1 有这些优点：

- RTL 改动小
- 不需要碰 Linux
- 不需要改串口驱动
- 不需要做 RX 注入路径
- 风险明显低于全双工

缺点也明确：

- **只能看输出，不能输入**
- JTAG 读得慢时，FIFO 可能溢出
- 更适合看 boot log / printk / shell 输出，不适合作为高体验交互终端

---

## V1 寄存器映射

沿用当前本地 JTAG 调试窗口：

- `0xF0000000` CONTROL
- `0xF0000004` STATUS
- `0xF0000008` VERSION

新增：

- `0xF000000C` **CONSOLE**

### `0xF000000C` 读语义

读返回：

- `bit[31]`：`overflow`，FIFO 曾经满过
- `bit[30]`：`valid`，当前 FIFO 非空
- `bit[29:16]`：`level`，FIFO 当前字节数
- `bit[15:8]`：保留
- `bit[7:0]`：当前队头字节

并且：

- **如果 `valid=1`，本次读取会把队头字节 pop 掉**
- 如果 FIFO 空，则返回 `valid=0` 且不 pop

### `0xF000000C` 写语义

- 写 `bit[31]=1`：清除 `overflow`
- 其他位当前忽略

---

## FIFO 规模

V1 先实现为：

- **1024-byte single-clock FIFO**

原因：

- 当前 UART TX 字节流和 JTAG bridge 都在 `clk_soc` 域
- 不需要跨时钟 FIFO
- 1024 字节足够先验证 Linux log 是否能稳定观察

如果后续发现 boot log 仍容易溢出，可升级为：

- 更深 FIFO
- 一次读多字节的 burst pop 寄存器

---

## 数据路径

### 原路径

`Linux -> uartlite TX reg -> UART serializer -> uart_txd pin`

### V1 路径

`Linux -> uartlite TX reg ->`

- `UART serializer -> uart_txd pin`
- `JTAG console FIFO -> jtag_axil_bridge local reg`

---

## 代码落点

V1 改动点如下：

1. `soc/uart_lite.v`
   - 导出 `tx_wr_o`
   - 导出 `tx_data_o`

2. `soc/soc.v`
   - 把 UART TX mirror 信号往上层透出

3. `soc/riscv_soc.v`
   - 继续把 TX mirror 信号往 `fpga_top` 透出

4. `fpga/xc7a35t/fpga_top.v`
   - 把 TX mirror 送入 `jtag_axil_bridge`

5. `fpga/xc7a35t/jtag_axil_bridge.v`
   - 增加 1024-byte TX FIFO
   - 增加 `0xF000000C` CONSOLE 读写语义

6. `fpga/xc7a35t/jtag_console_tx_v1.tcl`
   - JTAG 侧读取脚本

---

## 使用方式（预期）

下载新 bit 后，可用 Vivado batch：

```tcl
vivado -mode batch -source jtag_console_tx_v1.tcl
```

脚本会：

1. 连接 1MHz JTAG
2. 轮询 `0xF000000C`
3. 把 console 字节持续打印到 stdout

---

## 后续 V2

若 V1 验证有效，再做：

- RX inject
- JTAG 发字符到 Linux console
- 真正接近“JTAG shell”

即：

- **V1 = TX mirror**
- **V2 = TX mirror + RX inject**

