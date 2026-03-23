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

set CONTROL_ADDR     0xF0000000
set STATUS_ADDR      0xF0000004
set VERSION_ADDR     0xF0000008
set CONSOLE_ADDR     0xF000000C
set CONSOLE_RX_ADDR  0xF0000010
set UART_STATUS_ADDR 0x92000008

set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]

set jtag_freq_hz [string trim [expr {[info exists ::env(JTAG_FREQ_HZ)] ? $::env(JTAG_FREQ_HZ) : "1000000"}]]
set poll_ms [expr {[info exists ::env(POLL_MS)] ? int($::env(POLL_MS)) : 5}]
set max_idle_loops [expr {[info exists ::env(MAX_IDLE_LOOPS)] ? int($::env(MAX_IDLE_LOOPS)) : 3000}]
set max_drain_reads [expr {[info exists ::env(MAX_DRAIN_READS)] ? int($::env(MAX_DRAIN_READS)) : 2048}]
set clear_console_before_cmd [env_bool CLEAR_CONSOLE_BEFORE_CMD 1]
set clear_rx_overflow [env_bool CLEAR_RX_OVERFLOW 1]
set tx_wait_loops [expr {[info exists ::env(TX_WAIT_LOOPS)] ? int($::env(TX_WAIT_LOOPS)) : 4000}]
set tx_wait_ms [expr {[info exists ::env(TX_WAIT_MS)] ? int($::env(TX_WAIT_MS)) : 1}]

set txn_seq 0

proc emit_line {text} {
    puts $text
    flush stdout
}

proc connect_hw_server_auto {} {
    if {![catch {connect_hw_server -url $::hw_url}]} {
        return
    }

    catch {disconnect_hw_server}
    catch {exec taskkill /IM hw_server.exe /F}
    catch {exec taskkill /IM cs_server.exe /F}
    catch {exec $::hw_server_cmd -s tcp::${::hw_port} &}

    for {set attempt 0} {$attempt < 5} {incr attempt} {
        after 2000
        if {![catch {connect_hw_server -url $::hw_url}]} {
            return
        }
    }

    error "Unable to connect to hw_server at $::hw_url"
}

proc apply_hw_target_frequency {} {
    if {$::jtag_freq_hz eq ""} {
        return
    }

    set tgt [current_hw_target]
    if {$tgt eq ""} {
        return
    }

    catch {set_property PARAM.FREQUENCY $::jtag_freq_hz $tgt}
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

proc next_txn_name {prefix address} {
    incr ::txn_seq
    return [format "%s_%08X_%08X" $prefix $address $::txn_seq]
}

proc run_axi_write {hw_axi address data} {
    set txn_name [next_txn_name "wr" $address]
    create_hw_axi_txn $txn_name $hw_axi -type write -address $address -len 1 -data [list $data] -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
}

proc run_axi_read {hw_axi address} {
    set txn_name [next_txn_name "rd" $address]
    create_hw_axi_txn $txn_name $hw_axi -type read -address $address -len 1 -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    set data [string toupper [string trim [get_property DATA [get_hw_axi_txns $txn_name]] "{} "]]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
    return $data
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

proc byte_to_blob {byte} {
    if {$byte > 127} {
        set byte [expr {$byte - 256}]
    }
    return [binary format c $byte]
}

proc send_payload {hw_axi payload} {
    set tx_overflow_seen 0
    set payload_len [string length $payload]

    for {set idx 0} {$idx < $payload_len} {incr idx} {
        binary scan [string index $payload $idx] c signed_byte
        set tx_byte [expr {$signed_byte & 0xFF}]
        set sent 0

        for {set loop 0} {$loop < $::tx_wait_loops} {incr loop} {
            lassign [console_rx_decode [run_axi_read $hw_axi $::CONSOLE_RX_ADDR]] overflow pending ready last_ch
            if {$overflow} {
                set tx_overflow_seen 1
                if {$::clear_rx_overflow} {
                    run_axi_write $hw_axi $::CONSOLE_RX_ADDR 80000000
                }
            }

            if {!$pending || $ready} {
                run_axi_write $hw_axi $::CONSOLE_RX_ADDR [format %08X $tx_byte]
                set sent 1
                break
            }

            if {$::tx_wait_ms > 0} {
                after $::tx_wait_ms
            }
        }

        if {!$sent} {
            error "Timed out waiting for console RX slot at byte index $idx"
        }
    }

    return $tx_overflow_seen
}

proc drain_console {hw_axi} {
    set captured ""
    set total_chars 0
    set overflow_seen 0
    set idle_loops 0

    while {$::max_idle_loops < 0 || $idle_loops < $::max_idle_loops} {
        set console_raw [run_axi_read $hw_axi $::CONSOLE_ADDR]
        lassign [console_decode $console_raw] overflow valid level ch

        if {$overflow} {
            set overflow_seen 1
        }

        if {$valid} {
            append captured [byte_to_blob $ch]
            incr total_chars
            set idle_loops 0

            set extra_reads 0
            if {$level > 1} {
                set extra_reads [expr {$level - 1}]
                if {$extra_reads > ($::max_drain_reads - 1)} {
                    set extra_reads [expr {$::max_drain_reads - 1}]
                }
            }

            for {set j 0} {$j < $extra_reads} {incr j} {
                set console_raw [run_axi_read $hw_axi $::CONSOLE_ADDR]
                lassign [console_decode $console_raw] overflow2 valid2 level2 ch2
                if {$overflow2} {
                    set overflow_seen 1
                }
                if {!$valid2} {
                    break
                }
                append captured [byte_to_blob $ch2]
                incr total_chars
            }
        } else {
            incr idle_loops
            if {$::poll_ms > 0} {
                after $::poll_ms
            }
        }
    }

    return [list \
        $captured \
        $total_chars \
        $overflow_seen \
        [run_axi_read $hw_axi $::STATUS_ADDR] \
        [run_axi_read $hw_axi $::UART_STATUS_ADDR] \
        [run_axi_read $hw_axi $::CONSOLE_ADDR] \
        [run_axi_read $hw_axi $::CONSOLE_RX_ADDR]]
}

proc emit_hex_block {label payload} {
    binary scan $payload H* payload_hex
    emit_line "${label}_BEGIN"
    if {$payload_hex ne ""} {
        for {set idx 0} {$idx < [string length $payload_hex]} {incr idx 4096} {
            emit_line [string range $payload_hex $idx [expr {$idx + 4095}]]
        }
    }
    emit_line "${label}_END"
}

proc emit_exec_response_ok {captured total_chars overflow_seen tx_overflow_seen status_end uart_status_end console_end console_rx_end} {
    emit_line "__CODEX_JTAG_BEGIN__"
    emit_line "STATUS OK"
    emit_hex_block "RESULT_HEX" $captured
    emit_line "TOTAL_CHARS $total_chars"
    emit_line "OVERFLOW_SEEN $overflow_seen"
    emit_line "TX_OVERFLOW_SEEN $tx_overflow_seen"
    emit_line "STATUS_END $status_end"
    emit_line "UART_STATUS_END $uart_status_end"
    emit_line "CONSOLE_END $console_end"
    emit_line "CONSOLE_RX_END $console_rx_end"
    emit_line "__CODEX_JTAG_END__"
}

proc emit_exec_response_error {message} {
    emit_line "__CODEX_JTAG_BEGIN__"
    emit_line "STATUS ERROR"
    emit_hex_block "ERROR_HEX" $message
    emit_line "__CODEX_JTAG_END__"
}

proc exec_hex_command {hw_axi hex_payload} {
    if {$::clear_console_before_cmd} {
        run_axi_write $hw_axi $::CONSOLE_ADDR 80000000
    }
    set payload [binary format H* $hex_payload]
    set tx_overflow_seen [send_payload $hw_axi $payload]
    lassign [drain_console $hw_axi] captured total_chars overflow_seen status_end uart_status_end console_end console_rx_end
    emit_exec_response_ok $captured $total_chars $overflow_seen $tx_overflow_seen $status_end $uart_status_end $console_end $console_rx_end
}

proc cleanup_and_exit {{rc 0}} {
    catch {close_hw_manager}
    exit $rc
}

catch {set_msg_config -id {Labtoolstcl 44-481} -suppress}
catch {set_msg_config -id {Labtools 27-1347} -suppress}
catch {set_msg_config -id {Labtools 27-1974} -suppress}

set startup_rc [catch {
    open_hw_manager
    connect_hw_server_auto
    open_hw_target
    apply_hw_target_frequency

    set hw_axi [get_hw_axi_handle]
    refresh_hw_axi $hw_axi
    reset_hw_axi $hw_axi
} startup_err]

if {$startup_rc} {
    emit_line "__CODEX_JTAG_FATAL__"
    emit_hex_block "ERROR_HEX" $startup_err
    cleanup_and_exit 1
}

emit_line "__CODEX_JTAG_READY__ VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"

while {[gets stdin line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} {
        continue
    }

    if {[string match "EXEC_HEX *" $line]} {
        set hex_payload [string trim [string range $line 9 end]]
        if {![regexp {^[0-9A-Fa-f]+$} $hex_payload]} {
            emit_exec_response_error "Malformed EXEC_HEX payload"
            continue
        }
        set rc [catch {exec_hex_command $hw_axi $hex_payload} err]
        if {$rc} {
            emit_exec_response_error $err
        }
        continue
    }

    if {$line eq "PING"} {
        emit_line "__CODEX_JTAG_PONG__"
        continue
    }

    if {$line eq "QUIT"} {
        emit_line "__CODEX_JTAG_BYE__"
        cleanup_and_exit 0
    }

    binary scan $line H* line_hex
    emit_line "__CODEX_JTAG_WARN__ $line_hex"
}

cleanup_and_exit 0
