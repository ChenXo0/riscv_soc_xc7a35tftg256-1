proc usage {} {
    puts "Usage: vivado -mode batch -source jtag_linux_headless.tcl -tclargs <csv_out> <mem0> <addr0> ?<mem1> <addr1> ...?"
}

if {$argc < 3 || (($argc - 1) % 2) != 0} {
    usage
    exit 2
}

set csv_out [lindex $argv 0]
set seg_argv [lrange $argv 1 end]

set CONTROL_ADDR 0xF0000000
set STATUS_ADDR  0xF0000004
set VERSION_ADDR 0xF0000008
set verify_writes [expr {[info exists ::env(VERIFY_WRITES)] ? [string is true -strict $::env(VERIFY_WRITES)] : 0}]
set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]
set jtag_freq_hz [string trim [expr {[info exists ::env(JTAG_FREQ_HZ)] ? $::env(JTAG_FREQ_HZ) : "1000000"}]]
set max_burst_words [expr {[info exists ::env(MAX_BURST_WORDS)] ? int($::env(MAX_BURST_WORDS)) : 64}]
if {$max_burst_words < 1} {
    set max_burst_words 1
}
set probes_file [string trim [expr {[info exists ::env(PROBES_FILE)] ? $::env(PROBES_FILE) : "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.ltx"}]]

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
    refresh_hw_device -update_hw_probes true [current_hw_device]
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
                error "Verify failed at address $verify_addr: wrote $verify_word, read $rdback"
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

puts "HW_SERVER_CMD=$hw_server_cmd"
puts "HW_SERVER_URL=$hw_url"
puts "VERIFY_WRITES=$verify_writes"
puts "JTAG_FREQ_HZ=$jtag_freq_hz"
puts "MAX_BURST_WORDS=$max_burst_words"
puts "PROBES_FILE=$probes_file"

catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server_auto
open_hw_target
apply_hw_target_frequency

set hw_dev [lindex [get_hw_devices] 0]
if {$hw_dev eq ""} {
    error "No hardware device found"
}

current_hw_device $hw_dev
if {$probes_file ne ""} {
    set_property PROBES.FILE $probes_file $hw_dev
    set_property FULL_PROBES.FILE $probes_file $hw_dev
}
refresh_hw_device -update_hw_probes true $hw_dev

set hw_ilas [get_hw_ilas -quiet -of_objects $hw_dev]
if {[llength $hw_ilas] < 1} {
    error "No ILA cores found in the programmed design"
}
set hw_ila [lindex $hw_ilas 0]

set hw_axi [get_hw_axi_handle]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi

puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "Holding CPU in reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000000

for {set i 0} {$i < [llength $seg_argv]} {incr i 2} {
    set mem_file [lindex $seg_argv $i]
    set base_addr [lindex $seg_argv [expr {$i + 1}]]
    load_mem_file $hw_axi $mem_file $base_addr
}

puts "Arming ILA..."
run_hw_ila $hw_ila
after 50

puts "Releasing CPU reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000001

wait_on_hw_ila $hw_ila
upload_hw_ila_data $hw_ila
set ila_data [lindex [get_hw_ila_data -quiet -of_objects $hw_ila] end]
if {$ila_data eq ""} {
    error "No ILA capture data available"
}
write_hw_ila_data -csv_file $csv_out $ila_data

for {set i 0} {$i < 16} {incr i} {
    puts [format {STATUS[%d]=%s} $i [run_axi_read $hw_axi $STATUS_ADDR]]
}

puts "ILA_CSV=$csv_out"
close_hw_manager
exit 0
