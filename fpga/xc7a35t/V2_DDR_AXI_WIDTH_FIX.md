# XC7A35T V2 DDR AXI 宽度修复记录

更新时间：2026-03-22

## 现象

- DDR 校准成功，JTAG AXI 可访问。
- 但通过 JTAG 往 `0x8000_0000/04/08/0C` 连续写 4 个不同字后，
  最终读回 4 个地址都变成最后一个字。
- 这说明 DDR 写入路径存在 **16-byte 粒度地址/byte-lane 混叠**。

## 已确认的硬件证据

- `hello_first4.mem` 的 4 个字可稳定复现该问题。
- 问题不只是 burst 校验脚本假阳性；单字顺序写后再统一回读，仍会混叠。
- 已实现的 DCP 检查显示 MIG 侧存在明显的宽数据总线痕迹，当前直连 32-bit AXI 的实现高度可疑。

## 本次修复思路

在 `axi4_cdc` 与 `ddr3_ip` 之间恢复 Xilinx `axi_dwidth_converter`：

- `SI_DATA_WIDTH = 32`
- `MI_DATA_WIDTH = 128`
- 保持 AXI4、ID 宽度 4、地址宽度 32

这样让：

- SoC / JTAG / CDC 侧继续保持 32-bit AXI
- MIG 侧按 128-bit 宽度正确完成地址 lane 映射与 `AWSIZE/ARSIZE/WSTRB`

## 本地已修改文件

- `fpga/xc7a35t/build.tcl`
  - 恢复 `axi_mem_dwidth` IP 的创建与加入 `user_ips`
- `fpga/xc7a35t/xc7a35t_ddr_axi.v`
  - 在 `ddr3_ip` 前加入 `axi_mem_dwidth`
  - 32-bit AXI 进入 converter，128-bit AXI 输出到 MIG
  - 保留现有 reset / JTAG 相关修复

## 下一步上板验证

1. 远端 Vivado 重新综合/实现/生成 bit
2. 下载到板卡
3. 重新跑 `hello_first4.mem`
4. 确认以下读回应恢复为 4 个不同值：
   - `0x80000000`
   - `0x80000004`
   - `0x80000008`
   - `0x8000000C`
5. 再继续 `uart_hello_jtag.mem` 与 Linux/JTAG console 验证
