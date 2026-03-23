# riscv_soc 迁移到当前 XC7A35T(FTG256) 板卡的阶段规划

更新时间：2026-03-21  
适用工程：`/home/cx/riscv_soc`

---

## 1. 目标

本规划将 `riscv_soc` 从当前的 `fpga/arty` 版本迁移到本地已有参考板：

- 器件：`xc7a35tftg256-1`
- 参考工程：`/home/cx/xc7a35t/s1_led_test`

分两版推进：

### V1：最小 bring-up 版

1. **不先碰 DDR**
2. **先做单时钟 + BRAM/AXI RAM**
3. **把主存仍然映射到 `0x8000_0000`**
4. **只用小 ELF 做 bring-up**
5. 验证 UART 下载、内存装载、CPU 释放复位、串口输出

### V2：Linux 支持版

1. 引入当前板实际外部 DDR/SDRAM
2. 恢复“大内存 + Linux 镜像”启动路径
3. 支持类似 `linux_riscv_soc.elf` 的镜像装载与串口启动

---

## 2. 当前已知板卡信息

基于本地参考工程，当前已确认：

- 目标器件：`xc7a35tftg256-1`
- 已知可用基础引脚：
  - `clk -> D4`
  - `rst_n -> C4`
  - `led[0:3] -> K12/L14/L13/M14`
- 当前参考工程使用：
  - `IOSTANDARD = LVCMOS25`
- LED 特性：
  - **低电平点亮**

补充参考：

- 邻近工程 `tinyriscv` 中已有一版当前板最小约束，给出候选 UART：
  - `uart_rxd -> C7`
  - `uart_txd -> E6`

> 说明：时钟频率、UART 管脚、Bank 电压仍需在正式原理图/用户手册上再确认一次。  
> 但 V1 规划先按本地样例工程已验证过的最小集合推进。

---

## 3. 现有 Arty 版本与目标版本的差异

当前 `riscv_soc/fpga/arty/` 方案依赖：

- Arty 专用顶层端口
- Arty 专用 XDC
- Arty 专用 DDR3 MIG
- 双时钟结构：
  - SoC/debug 侧时钟
  - DDR UI 时钟
- 外部主存默认位于 `0x8000_0000`
- 使用 UART debug bridge 先下载程序，再释放 CPU reset

而当前 XC7A35T(FTG256) 板的 V1 目标是：

- **不接 DDR**
- **单时钟**
- 用 **片上 BRAM/AXI RAM** 替代外部 DDR
- 保留 `0x8000_0000` 主存基地址不变
- 保留 debug bridge 的总体装载思路

因此结论是：

### 需要重做

- `top.v`
- `artix7_pll.v`
- `arty_ddr.v`
- `arty_revb.xdc`
- `project.xpr`

### 可以尽量复用

- `fpga_top.v` 的主体结构
- `dbg_bridge`
- `riscv_soc`
- `reset_vector = 32'h80000000`
- “先装载、再释放 CPU” 的调试流程

---

## 4. V1 总体技术路线

### 4.1 架构目标

V1 建议建立新的板级目录：

```text
fpga/xc7a35t/
├─ top.v
├─ xc7a35t.xdc
├─ axi_ram.v            # 或 bram wrapper
├─ fpga_top.v           # 可复用/轻改
├─ program.tcl
└─ run.py               # 视需要复用并升级到 Python3
```

### 4.2 主存方案

V1 用 **BRAM/AXI RAM** 代替 Arty DDR：

- SoC 仍从 `0x8000_0000` 取指/访存
- 但实际后端不再是 MIG DDR，而是片上 RAM
- 有效容量先控制在 **小容量 bring-up 范围**
  - 建议初版从 **64 KiB ~ 128 KiB** 开始
  - 后续依据综合资源再调

建议的地址策略：

- 主存基地址：`0x8000_0000`
- BRAM 实际容量：例如 `64 KiB`
- 则 V1 有效窗口约为：
  - `0x8000_0000 ~ 0x8000_FFFF`

这样做的好处：

1. SoC 内部地址地图不用改大框架
2. `reset_vector` 仍可保持 `0x8000_0000`
3. 后续 V2 引入 DDR 时仍能沿用同一主存基址

### 4.3 时钟方案

V1 先采用 **单时钟**：

- 先不保留 DDR 的双时钟结构
- 板级输入时钟直接作为系统时钟
- 若必须分频/倍频，再补最小 PLL/MMCM

建议：

- 初版优先尝试 **直接用板级时钟**
- 只有在时序/波特率/系统行为需要时，再加入时钟管理模块

### 4.4 调试装载方案

V1 尽量保留原设计的下载思路：

1. bitstream 下载到 FPGA
2. 通过 `dbg_bridge` 从 UART 向主存写入小 ELF
3. 写完后释放 CPU reset
4. 通过 UART 观察串口输出

需要注意：

- 现有 `run.py` 是 Python 2.7 风格
- 当前环境大概率需要整理为 **Python 3 可运行**
- 装载脚本本身可以继续沿用原流程：
  - 先保持 CPU reset
  - 写主存
  - 切到串口控制台

---

## 5. V1 详细任务分解

### 5.1 建立板级目录

目标：

- 从 `fpga/arty/` 复制出 `fpga/xc7a35t/`
- 去掉 Arty/DDR 绑定内容
- 保留 SoC/debug 的核心骨架

预期结果：

- 形成独立于 Arty 的当前板移植目录

### 5.2 新顶层 `top.v`

目标：

- 用当前板最小外设替换 Arty 端口

建议顶层端口：

- `clk`
- `rst_n`
- `uart_rxd`
- `uart_txd`
- `led[3:0]`

顶层职责：

1. 板级输入/输出端口定义
2. 复位同步/极性处理
3. 单时钟分发
4. 例化 `fpga_top`
5. 连接新的 `axi_ram/bram wrapper`
6. 映射 LED 状态输出

注意：

- LED 需按 **低电平点亮** 处理
- 顶层不再暴露 DDR/QSPI 端口

### 5.3 新约束 `xc7a35t.xdc`

V1 先使用当前已知最小约束：

- `clk -> D4`
- `rst_n -> C4`
- `led[0:3] -> K12/L14/L13/M14`
- 候选 UART：
  - `uart_rxd -> C7`
  - `uart_txd -> E6`
- `IOSTANDARD -> LVCMOS25`

任务要求：

1. 写出当前板最小 XDC
2. 建立时钟约束
3. 明确复位、UART、LED 极性
4. 后续根据原理图校正

### 5.4 新内存后端：`axi_ram.v` / `bram wrapper`

这是 V1 的核心工作。

需求：

- 对外表现为 SoC 可访问的主存
- 对内用 BRAM/综合 RAM 实现
- 地址窗口放在 `0x8000_0000`
- 至少支持小 ELF 正常装载和运行

建议优先级：

### 方案 A：单时钟 AXI RAM（优先）

- 直接写一个 AXI 从设备 RAM
- 接到 `riscv_soc` 的 `mem_*` 接口
- 支持基本 burst 访问
- 单时钟，不再需要 `axi4_cdc`

优点：

- 结构清晰
- 与当前 `riscv_soc` 的 AXI 主存接口对口
- 后续切换到 DDR 时，SoC 侧无需大改

### 方案 B：BRAM + AXI wrapper

- 底层是 BRAM
- 外层包一层 AXI 接口

优点：

- 更贴近 FPGA 资源
- 便于后续换成 Xilinx BRAM IP 或推断 RAM

V1 建议先实现 **能稳定工作的最小 AXI RAM**，不追求复杂优化。

### 5.5 `fpga_top.v` 适配

建议：

- 以当前 `fpga/arty/fpga_top.v` 为基础
- 尽量保留：
  - `dbg_bridge`
  - `riscv_soc`
  - `rst_cpu_w` 控制逻辑
  - `reset_vector = 32'h80000000`

V1 可能要做的简化：

- 若内存后端与 SoC 同时钟：
  - 可以去掉 `axi4_cdc`
  - 或保留接口形式但时钟接成一致

目标：

- 保持“Host 装载后再放开 CPU”的核心机制不变

### 5.6 `run.py` / 装载工具

V1 需要确认并整理：

1. 当前脚本是否需要从 Python2 迁移到 Python3
2. 小 ELF 是否能按新内存容量正常下载
3. CPU reset 控制位是否继续沿用

建议：

- 脚本逻辑保留
- 语言/串口兼容性补齐
- 增加针对小 ELF 的使用说明

### 5.7 小 ELF bring-up 集合

V1 明确不跑 Linux 镜像，只跑小程序。

建议准备的 bring-up 程序：

1. **UART hello**
   - 上电后打印固定字符串
2. **内存读写测试**
   - 验证主存窗口可读写
3. **Timer 中断测试**
   - 验证 SoC 基本外设
4. **GPIO/LED 测试**
   - 验证板级连线和 LED 极性

要求：

- 链接地址统一放在 `0x8000_0000`
- 程序体积控制在 BRAM 容量内
- 不依赖 Linux/大根文件系统/initrd

---

## 6. V1 交付标准

满足以下条件即可认为 V1 完成：

1. 当前板 bitstream 可成功生成并下载
2. SoC 可在 `0x8000_0000` 取指运行
3. 小 ELF 可通过 debug bridge 成功写入主存
4. CPU 可在装载完成后被释放复位
5. UART 可稳定打印程序输出
6. 至少一个 LED 可作为状态指示正常工作

推荐演示顺序：

1. 上板后 LED 显示“待装载/复位保持”
2. 下载小 ELF
3. 释放 CPU
4. UART 输出 hello / test pass
5. LED 状态切换为运行成功

---

## 7. V1 风险与待确认项

### 7.1 板级资料仍需补全

当前最大不确定项：

- 正式原理图/用户手册中的：
  - 时钟真实频率
  - UART 实际连接
  - I/O Bank 电压
  - 是否存在外部 DDR/SDRAM 及其型号

### 7.2 BRAM 容量限制

V1 主存改为片上 RAM 后：

- 无法承载 Linux 镜像
- 程序规模必须显著小于 DDR 版
- 链接脚本和测试集都要收敛到小程序

### 7.3 工具链脚本兼容性

现有 `run.py` 及配套工具存在：

- Python2 依赖风险
- 串口路径/波特率兼容性风险

V1 中应尽早消除。

---

## 8. V2：Linux 支持版规划

V2 的目标不是在 V1 上简单扩大程序，而是重新引入真正的大内存后端。

### 8.1 V2 前置条件

在进入 V2 之前，必须明确：

1. 当前板是否有外部 DDR/SDRAM
2. 具体存储器型号、位宽、时钟、Bank 电压
3. 对应 FPGA 管脚分配
4. Vivado 上可生成并实现的 MIG/内存控制器方案

### 8.2 V2 技术路线

若当前板确认有外部 DDR/SDRAM，则：

1. 新建当前板专用内存 wrapper
2. 基于当前板器件/封装/引脚重建 MIG
3. 恢复双时钟或 UI clock 架构
4. 继续把主存基地址保持在 `0x8000_0000`
5. 恢复 Linux 所需镜像装载流程

### 8.3 V2 预期恢复的能力

1. 装载大体积 ELF / kernel image
2. 启动 Linux 镜像
3. 串口查看 boot log
4. 逐步恢复接近原 Arty 版本的使用方式

### 8.4 V2 与 V1 的关系

V1 不是废弃版，而是 V2 的稳定前置版本。

V1 保留的内容应尽量能直接被 V2 继承：

- `fpga_top` 结构
- `dbg_bridge`
- `riscv_soc`
- `reset_vector`
- 主存基地址 `0x8000_0000`
- 程序装载后释放 CPU 的流程

V2 主要替换的只是：

- 主存后端
- 时钟结构
- 板级顶层和约束的扩展部分

---

## 9. 推荐实施顺序

### 第一步：V1 最小可运行

1. 建 `fpga/xc7a35t/`
2. 写当前板最小 `xdc`
3. 写单时钟 `top.v`
4. 写 `axi_ram/bram wrapper`
5. 跑小 ELF
6. 打通 UART 输出

### 第二步：V1 稳定化

1. 加强状态 LED
2. 整理 Python3 下载脚本
3. 固化 bitstream 下载与串口运行流程
4. 写 bring-up 使用文档

### 第三步：V2 Linux 支持

1. 确认外部 DDR/SDRAM
2. 重建 MIG/内存控制器
3. 恢复大内存装载
4. 适配 Linux 镜像
5. 验证串口 boot log

---

## 10. 当前决策结论

当前版本明确采用以下路线：

1. **先不碰 DDR**
2. **先做单时钟 + BRAM/AXI RAM**
3. **主存仍映射到 `0x8000_0000`**
4. **只跑小 ELF 做 bring-up**
5. **下一版再支持 Linux 镜像**

这是当前板移植风险最低、推进最快、也最利于后续扩展到 Linux 的路线。
