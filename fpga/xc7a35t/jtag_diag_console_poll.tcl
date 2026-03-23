proc usage {} {
    puts "Usage: vivado -mode batch -source jtag_diag_console_poll.tcl -tclargs <mem0> <addr0> ?<mem1> <addr1> ...?"
}

if {$argc < 2 || ($argc % 2) != 0} {
    usage
    exit 2
}

set CONTROL_ADDR     0xF0000000
set STATUS_ADDR      0xF0000004
set VERSION_ADDR     0xF0000008
set CONSOLE_ADDR     0xF000000C
set CONSOLE_RX_ADDR  0xF0000010
set UART_STATUS_ADDR 0x92000008
set GPIO_DIR_ADDR    0x94000000
set GPIO_OUT_ADDR    0x94000008
set MEM_RD0_ADDR     0x80000000
set MEM_RD1_ADDR     0x80000004
set MEM_RD2_ADDR     0x80000008
set MEM_RD3_ADDR     0x8000000C

set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]
set jtag_freq_hz [string trim [expr {[info exists ::env(JTAG_FREQ_HZ)] ? $::env(JTAG_FREQ_HZ) : "1000000"}]]
set max_burst_words [expr {[info exists ::env(MAX_BURST_WORDS)] ? int($::env(MAX_BURST_WORDS)) : 64}]
set poll_ms [expr {[info exists ::env(POLL_MS)] ? int($::env(POLL_MS)) : 10}]
set diag_loops [expr {[info exists ::env(DIAG_LOOPS)] ? int($::env(DIAG_LOOPS)) : 200}]
set verify_writes 0
if {[info exists ::env(VERIFY_WRITES)]} {
    set verify_token [string tolower [string trim $::env(VERIFY_WRITES)]]
    if {$verify_token in {"1" "true" "yes" "on"}} {
        set verify_writes 1
    }
}

if {$max_burst_words < 1} {
    set max_burst_words 1
}

proc connect_hw_server_auto {} {
    if {[info exists ::env(HW_SERVER_URL)] && [string trim $::env(HW_SERVER_URL)] ne ""} {
        connect_hw_server -url [string trim $::env(HW_SERVER_URL)]
    } else {
        connect_hw_server -url $::hw_url
    }
}

proc apply_hw_target_frequency {} {
    if {$::jtag_freq_hz eq ""} {
        return
    }

    set tgt [current_hw_target]
    if {$tgt eq ""} {
        return
    }

    puts "JTAG_FREQ_HZ=$::jtag_freq_hz"
    if {[catch {set_property PARAM.FREQUENCY $::jtag_freq_hz $tgt} freq_msg]} {
        puts "JTAG_FREQ_SET_WARN=$freq_msg"
        return
    }

    close_hw_target
    open_hw_target
}

proc get_hw_axi_handle {} {
    set devs [get_hw_devices]
    if {[llength $devs] < 1} {
        error "No hardware devices found"
    }

    current_hw_device [lindex $devs 0]
    refresh_hw_device -update_hw_probes false [current_hw_device]
    set axis [get_hw_axis -quiet -of_objects [current_hw_device]]
    if {[llength $axis] < 1} {
        error "No hw_axi instances found in the programmed design"
    }

    return [lindex $axis 0]
}

proc run_axi_write {hw_axi address data} {
    set txn_name [format "wr_%08X" $address]
    create_hw_axi_txn $txn_name $hw_axi -type write -address $address -len 1 -data [list $data] -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
}

proc run_axi_read {hw_axi address} {
    set txn_name [format "rd_%08X" $address]
    create_hw_axi_txn $txn_name $hw_axi -type read -address $address -len 1 -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    set data [string toupper [string trim [get_property DATA [get_hw_axi_txns $txn_name]] "{} "]]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
    return $data
}

proc flush_burst {hw_axi burst_base_name burst_words_name line_num_name} {
    upvar 1 $burst_base_name burst_base
    upvar 1 $burst_words_name burst_words
    upvar 1 $line_num_name line_num

    if {[llength $burst_words] == 0} {
        return
    }

    if {[llength $burst_words] == 1} {
        set wr_addr [format 0x%08X $burst_base]
        set wr_word [lindex $burst_words 0]
        run_axi_write $hw_axi $wr_addr $wr_word
        if {$::verify_writes} {
            set rdback [run_axi_read $hw_axi $wr_addr]
            if {[string toupper $rdback] ne [string toupper $wr_word]} {
                error "Verify failed at $wr_addr: wrote $wr_word read $rdback"
            }
        }
    } else {
        set txn_name [format "wr_%08X_len%d" $burst_base [llength $burst_words]]
        create_hw_axi_txn $txn_name $hw_axi -type write -address [format 0x%08X $burst_base] -len [llength $burst_words] -data $burst_words -force
        run_hw_axi [get_hw_axi_txns $txn_name]
        delete_hw_axi_txn [get_hw_axi_txns $txn_name]
        if {$::verify_writes} {
            for {set idx 0} {$idx < [llength $burst_words]} {incr idx} {
                set verify_addr [format 0x%08X [expr {$burst_base + ($idx * 4)}]]
                set verify_word [string toupper [lindex $burst_words $idx]]
                set rdback [run_axi_read $hw_axi $verify_addr]
                if {[string toupper $rdback] ne $verify_word} {
                    error "Verify failed at $verify_addr: wrote $verify_word read $rdback"
                }
            }
        }
    }

    incr line_num [llength $burst_words]
    set burst_words {}
}

proc load_mem_file {hw_axi mem_file base_addr} {
    if {![file exists $mem_file]} {
        error "Memory image not found: $mem_file"
    }

    puts "Loading $mem_file -> $base_addr"
    set fp [open $mem_file r]
    set line_num 0
    set burst_words {}
    set burst_base 0

    while {[gets $fp line] >= 0} {
        set word [string trim $line]
        if {$word eq ""} {
            continue
        }
        if {![regexp {^[0-9A-Fa-f]{8}$} $word]} {
            error "Invalid word at line [expr {$line_num + [llength $burst_words] + 1}] in $mem_file: '$word'"
        }
        if {[llength $burst_words] == 0} {
            set burst_base [expr {$base_addr + ($line_num * 4)}]
        }
        lappend burst_words [string toupper $word]
        if {[llength $burst_words] >= $::max_burst_words} {
            flush_burst $hw_axi burst_base burst_words line_num
        }
    }
    close $fp
    flush_burst $hw_axi burst_base burst_words line_num
    puts "Loaded words=$line_num from $mem_file"
}

proc console_decode {raw_hex} {
    scan $raw_hex %x value
    set overflow [expr {($value >> 31) & 1}]
    set valid    [expr {($value >> 30) & 1}]
    set level    [expr {($value >> 16) & 0x3FFF}]
    set ch       [expr {$value & 0xFF}]
    return [list $overflow $valid $level $ch]
}

catch {close_hw_manager}
catch {disconnect_hw_server}
catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server_auto
open_hw_target
apply_hw_target_frequency
puts "MAX_BURST_WORDS=$max_burst_words"
puts "VERIFY_WRITES=$verify_writes"
catch {set_msg_config -id {Labtoolstcl 44-481} -suppress}
catch {set_msg_config -id {Labtools 27-1347} -suppress}
catch {set_msg_config -id {Labtools 27-1974} -suppress}

set hw_axi [get_hw_axi_handle]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi

puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "Holding CPU in reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000000

for {set i 0} {$i < $argc} {incr i 2} {
    set mem_file [lindex $argv $i]
    set base_addr [lindex $argv [expr {$i + 1}]]
    load_mem_file $hw_axi $mem_file $base_addr
}

puts "READBACK_80000000=[run_axi_read $hw_axi $MEM_RD0_ADDR]"
puts "READBACK_80000004=[run_axi_read $hw_axi $MEM_RD1_ADDR]"
puts "READBACK_80000008=[run_axi_read $hw_axi $MEM_RD2_ADDR]"
puts "READBACK_8000000C=[run_axi_read $hw_axi $MEM_RD3_ADDR]"
puts "UART_STATUS_PRE=[run_axi_read $hw_axi $UART_STATUS_ADDR]"
puts "GPIO_DIR_PRE=[run_axi_read $hw_axi $GPIO_DIR_ADDR]"
puts "GPIO_OUT_PRE=[run_axi_read $hw_axi $GPIO_OUT_ADDR]"
puts "CONSOLE_PRE=[run_axi_read $hw_axi $CONSOLE_ADDR]"
puts "CONSOLE_RX_PRE=[run_axi_read $hw_axi $CONSOLE_RX_ADDR]"

run_axi_write $hw_axi $CONSOLE_ADDR 80000000
puts "Releasing CPU reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000001

set total_chars 0
set overflow_seen 0

for {set i 0} {$i < $diag_loops} {incr i} {
    set control_raw [run_axi_read $hw_axi $CONTROL_ADDR]
    set status_raw [run_axi_read $hw_axi $STATUS_ADDR]
    set uart_status_raw [run_axi_read $hw_axi $UART_STATUS_ADDR]
    set gpio_dir_raw [run_axi_read $hw_axi $GPIO_DIR_ADDR]
    set gpio_out_raw [run_axi_read $hw_axi $GPIO_OUT_ADDR]
    set console_raw [run_axi_read $hw_axi $CONSOLE_ADDR]
    lassign [console_decode $console_raw] overflow valid level ch

    if {$overflow} {
        set overflow_seen 1
    }

    puts [format "LOOP=%04d CONTROL=%s STATUS=%s UART_STATUS=%s GPIO_DIR=%s GPIO_OUT=%s CONSOLE=%s VALID=%d LEVEL=%d CH=%02X OVERFLOW=%d" \
        $i $control_raw $status_raw $uart_status_raw $gpio_dir_raw $gpio_out_raw $console_raw $valid $level $ch $overflow]

    if {$valid} {
        puts [format {CHAR[%04d]=%c} $i $ch]
        incr total_chars
    }

    after $poll_ms
}

puts "TOTAL_CHARS=$total_chars"
puts "OVERFLOW_SEEN=$overflow_seen"
puts "STATUS_END=[run_axi_read $hw_axi $STATUS_ADDR]"
puts "UART_STATUS_END=[run_axi_read $hw_axi $UART_STATUS_ADDR]"
puts "GPIO_DIR_END=[run_axi_read $hw_axi $GPIO_DIR_ADDR]"
puts "GPIO_OUT_END=[run_axi_read $hw_axi $GPIO_OUT_ADDR]"
puts "CONSOLE_END=[run_axi_read $hw_axi $CONSOLE_ADDR]"

close_hw_manager
exit 0
