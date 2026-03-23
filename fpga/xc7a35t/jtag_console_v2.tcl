proc usage {} {
    puts "Usage: vivado -mode batch -source jtag_console_v2.tcl -tclargs ?<mem0> <addr0> ...?"
    puts "       With no tclargs: attach to a running system and drain JTAG console only."
}

proc env_bool {name default_value} {
    if {![info exists ::env($name)]} {
        return $default_value
    }

    set token [string tolower [string trim $::env($name)]]
    if {$token in {"1" "true" "yes" "on"}} {
        return 1
    }
    if {$token in {"0" "false" "no" "off"}} {
        return 0
    }

    return $default_value
}

if {($argc % 2) != 0} {
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

set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]
set jtag_freq_hz [string trim [expr {[info exists ::env(JTAG_FREQ_HZ)] ? $::env(JTAG_FREQ_HZ) : "3000000"}]]
set max_burst_words [expr {[info exists ::env(MAX_BURST_WORDS)] ? int($::env(MAX_BURST_WORDS)) : 256}]
set poll_ms [expr {[info exists ::env(POLL_MS)] ? int($::env(POLL_MS)) : 0}]
set max_idle_loops [expr {[info exists ::env(MAX_IDLE_LOOPS)] ? int($::env(MAX_IDLE_LOOPS)) : 2000}]
set max_drain_reads [expr {[info exists ::env(MAX_DRAIN_READS)] ? int($::env(MAX_DRAIN_READS)) : 512}]
set verify_writes 0
if {[info exists ::env(VERIFY_WRITES)]} {
    set verify_token [string tolower [string trim $::env(VERIFY_WRITES)]]
    if {$verify_token in {"1" "true" "yes" "on"}} {
        set verify_writes 1
    }
}
set reset_and_load [env_bool RESET_AND_LOAD [expr {$argc > 0}]]
set clear_console [env_bool CLEAR_CONSOLE $reset_and_load]
set clear_rx_overflow [env_bool CLEAR_RX_OVERFLOW 0]
set tx_log_enable [env_bool TX_LOG_ENABLE 1]
set tx_string [expr {[info exists ::env(TX_STRING)] ? $::env(TX_STRING) : ""}]
set tx_hex_raw [expr {[info exists ::env(TX_HEX)] ? $::env(TX_HEX) : ""}]
set tx_after_idle_loops [expr {[info exists ::env(TX_AFTER_IDLE_LOOPS)] ? int($::env(TX_AFTER_IDLE_LOOPS)) : -1}]
set tx_after_chars [expr {[info exists ::env(TX_AFTER_CHARS)] ? int($::env(TX_AFTER_CHARS)) : -1}]
set status_every_chars [expr {[info exists ::env(STATUS_EVERY_CHARS)] ? int($::env(STATUS_EVERY_CHARS)) : 0}]
set log_file [expr {[info exists ::env(LOG_FILE)] ? [string trim $::env(LOG_FILE)] : ""}]

if {$tx_hex_raw ne ""} {
    set tx_hex_clean [string map {" " "" "," "" "_" "" ":" "" "0x" "" "0X" ""} $tx_hex_raw]
    if {([string length $tx_hex_clean] % 2) != 0} {
        error "TX_HEX must contain an even number of hex digits"
    }
    set tx_string [binary format H* $tx_hex_clean]
}

if {$max_burst_words < 1} {
    set max_burst_words 1
}
if {$max_drain_reads < 1} {
    set max_drain_reads 1
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

proc run_axi_write_burst {hw_axi address data_words} {
    set burst_len [llength $data_words]
    if {$burst_len < 1} {
        return
    }
    if {$burst_len == 1} {
        run_axi_write $hw_axi $address [lindex $data_words 0]
        return
    }

    set txn_name [format "wr_%08X_len%d" $address $burst_len]
    create_hw_axi_txn $txn_name $hw_axi -type write -address $address -len $burst_len -data $data_words -force
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

proc flush_burst {hw_axi burst_base_name burst_words_name line_num_name verify_writes} {
    upvar 1 $burst_base_name burst_base
    upvar 1 $burst_words_name burst_words
    upvar 1 $line_num_name line_num

    if {[llength $burst_words] == 0} {
        return
    }

    set addr_hex [format 0x%08X $burst_base]
    run_axi_write_burst $hw_axi $addr_hex $burst_words

    if {$verify_writes} {
        for {set idx 0} {$idx < [llength $burst_words]} {incr idx} {
            set verify_addr [format 0x%08X [expr {$burst_base + ($idx * 4)}]]
            set verify_word [string toupper [lindex $burst_words $idx]]
            set rdback [run_axi_read $hw_axi $verify_addr]
            if {[string toupper $rdback] ne $verify_word} {
                error "Verify failed at $verify_addr: wrote $verify_word, read $rdback"
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
            flush_burst $hw_axi burst_base burst_words line_num $::verify_writes
        }
    }
    close $fp
    flush_burst $hw_axi burst_base burst_words line_num $::verify_writes
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

proc console_rx_decode {raw_hex} {
    scan $raw_hex %x value
    set overflow [expr {($value >> 31) & 1}]
    set pending  [expr {($value >> 30) & 1}]
    set ready    [expr {($value >> 29) & 1}]
    set ch       [expr {$value & 0xFF}]
    return [list $overflow $pending $ready $ch]
}

proc emit_char {ch} {
    global log_fp
    set s [format %c $ch]
    puts -nonewline $s
    flush stdout
    if {[info exists log_fp] && $log_fp ne ""} {
        puts -nonewline $log_fp $s
        flush $log_fp
    }
}

proc maybe_emit_status {hw_axi total_chars} {
    if {$::status_every_chars <= 0} {
        return
    }
    if {$total_chars == 0} {
        return
    }
    if {($total_chars % $::status_every_chars) != 0} {
        return
    }
    puts [format "\nSTATUS_SNAPSHOT chars=%d STATUS=%s UART_STATUS=%s GPIO_DIR=%s GPIO_OUT=%s" \
        $total_chars \
        [run_axi_read $hw_axi $::STATUS_ADDR] \
        [run_axi_read $hw_axi $::UART_STATUS_ADDR] \
        [run_axi_read $hw_axi $::GPIO_DIR_ADDR] \
        [run_axi_read $hw_axi $::GPIO_OUT_ADDR]]
}

proc maybe_tx_inject {hw_axi total_chars idle_loops tx_index_name tx_sent_name tx_overflow_name} {
    upvar 1 $tx_index_name tx_index
    upvar 1 $tx_sent_name tx_sent
    upvar 1 $tx_overflow_name tx_overflow_seen

    if {$::tx_string eq ""} {
        return
    }
    if {$tx_index >= [string length $::tx_string]} {
        return
    }
    if {$::tx_after_chars >= 0 && $total_chars < $::tx_after_chars} {
        return
    }
    if {$::tx_after_idle_loops >= 0 && $idle_loops < $::tx_after_idle_loops} {
        return
    }

    lassign [console_rx_decode [run_axi_read $hw_axi $::CONSOLE_RX_ADDR]] overflow pending ready last_ch
    if {$overflow} {
        set tx_overflow_seen 1
        if {$::clear_rx_overflow} {
            run_axi_write $hw_axi $::CONSOLE_RX_ADDR 80000000
        }
    }

    if {$pending && !$ready} {
        return
    }

    binary scan [string index $::tx_string $tx_index] c tx_char_signed
    set tx_char [expr {$tx_char_signed & 0xFF}]
    run_axi_write $hw_axi $::CONSOLE_RX_ADDR [format %08X $tx_char]
    if {$::tx_log_enable} {
        if {$tx_char >= 32 && $tx_char <= 126} {
            puts [format {\nTX[%04d]=0x%02X '%c'} $tx_index $tx_char $tx_char]
        } else {
            puts [format {\nTX[%04d]=0x%02X} $tx_index $tx_char]
        }
    }
    incr tx_index
    incr tx_sent
}

set log_fp ""
if {$log_file ne ""} {
    set log_fp [open $log_file w]
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
catch {set_msg_config -id {Labtoolstcl 44-481} -suppress}
catch {set_msg_config -id {Labtools 27-1347} -suppress}
catch {set_msg_config -id {Labtools 27-1974} -suppress}

set hw_axi [get_hw_axi_handle]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi

puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "RESET_AND_LOAD=$reset_and_load"
puts "CLEAR_CONSOLE=$clear_console"
puts "VERIFY_WRITES=$verify_writes"
puts "MAX_DRAIN_READS=$max_drain_reads"
puts "TX_STRING_LEN=[string length $tx_string]"

if {$reset_and_load} {
    puts "Holding CPU in reset..."
    run_axi_write $hw_axi $CONTROL_ADDR 00000000

    for {set i 0} {$i < $argc} {incr i 2} {
        set mem_file [lindex $argv $i]
        set base_addr [lindex $argv [expr {$i + 1}]]
        load_mem_file $hw_axi $mem_file $base_addr
    }
}

if {$clear_console} {
    run_axi_write $hw_axi $CONSOLE_ADDR 80000000
}

if {$reset_and_load} {
    puts "Releasing CPU reset..."
    run_axi_write $hw_axi $CONTROL_ADDR 00000001
}

set idle_loops 0
set total_chars 0
set overflow_seen 0
set tx_overflow_seen 0
set tx_index 0
set tx_sent 0

while {$max_idle_loops < 0 || $idle_loops < $max_idle_loops} {
    set console_raw [run_axi_read $hw_axi $CONSOLE_ADDR]
    lassign [console_decode $console_raw] overflow valid level ch

    if {$overflow} {
        set overflow_seen 1
    }

    if {$valid} {
        emit_char $ch
        incr total_chars
        set idle_loops 0

        set extra_reads 0
        if {$level > 1} {
            set extra_reads [expr {$level - 1}]
            if {$extra_reads > ($max_drain_reads - 1)} {
                set extra_reads [expr {$max_drain_reads - 1}]
            }
        }

        for {set j 0} {$j < $extra_reads} {incr j} {
            set console_raw [run_axi_read $hw_axi $CONSOLE_ADDR]
            lassign [console_decode $console_raw] overflow2 valid2 level2 ch2
            if {$overflow2} {
                set overflow_seen 1
            }
            if {!$valid2} {
                break
            }
            emit_char $ch2
            incr total_chars
        }

        maybe_emit_status $hw_axi $total_chars
    } else {
        incr idle_loops
        if {$poll_ms > 0} {
            after $poll_ms
        }
    }

    maybe_tx_inject $hw_axi $total_chars $idle_loops tx_index tx_sent tx_overflow_seen
}

if {$total_chars > 0} {
    puts ""
}
puts "TOTAL_CHARS=$total_chars"
puts "OVERFLOW_SEEN=$overflow_seen"
puts "TX_SENT=$tx_sent"
puts "TX_OVERFLOW_SEEN=$tx_overflow_seen"
puts "STATUS_END=[run_axi_read $hw_axi $STATUS_ADDR]"
puts "UART_STATUS_END=[run_axi_read $hw_axi $UART_STATUS_ADDR]"
puts "GPIO_DIR_END=[run_axi_read $hw_axi $GPIO_DIR_ADDR]"
puts "GPIO_OUT_END=[run_axi_read $hw_axi $GPIO_OUT_ADDR]"
puts "CONSOLE_END=[run_axi_read $hw_axi $CONSOLE_ADDR]"
puts "CONSOLE_RX_END=[run_axi_read $hw_axi $CONSOLE_RX_ADDR]"

close_hw_manager
if {$log_fp ne ""} {
    close $log_fp
}
exit 0
