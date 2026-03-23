## XC7A35T FTG256 V1 minimal constraints
## Assumptions used in V1:
##   - clock pin uses D4 first, based on the local board manual table
##   - manual text also mentions T8, so schematic re-check is still required
##   - I/O standard uses LVCMOS25, matching the verified local LED sample

## clock / reset
set_property PACKAGE_PIN D4 [get_ports clk]
set_property PACKAGE_PIN C4 [get_ports rst_n]
set_property IOSTANDARD LVCMOS25 [get_ports {clk rst_n}]
create_clock -name clk -period 20.000 [get_ports clk]

## uart
set_property PACKAGE_PIN C7 [get_ports uart_rxd]
set_property PACKAGE_PIN E6 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS25 [get_ports {uart_rxd uart_txd}]

## leds (active low)
set_property PACKAGE_PIN K12 [get_ports {led[0]}]
set_property PACKAGE_PIN L14 [get_ports {led[1]}]
set_property PACKAGE_PIN L13 [get_ports {led[2]}]
set_property PACKAGE_PIN M14 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[0] led[1] led[2] led[3]}]

set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
