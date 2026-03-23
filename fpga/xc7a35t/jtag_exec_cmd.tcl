proc usage {} {
    puts "Usage: vivado -mode batch -notrace -source jtag_exec_cmd.tcl -tclargs ?--hex HEX? ?--string TEXT? ?--no-leading-enter? ?--no-trailing-enter? ?-- COMMAND ...?"
    puts "       With no command: sends a single Enter to the running Linux console."
    puts ""
    puts "Environment overrides:"
    puts "  JTAG_LINUX_CMD_HEX     Pre-encoded bytes to inject, in hex."
    puts "  JTAG_LINUX_CMD_STRING  Plain-text bytes to inject."
    puts "  RESET_AND_LOAD         Defaults to 0 for attach-only command execution."
    puts "  CLEAR_CONSOLE          Defaults to 1 for cleaner per-command output."
    puts "  CLEAR_RX_OVERFLOW      Defaults to 1."
    puts "  JTAG_FREQ_HZ           Defaults to 1000000."
    puts "  POLL_MS                Defaults to 5."
    puts "  MAX_IDLE_LOOPS         Defaults to 3000."
    puts "  MAX_DRAIN_READS        Defaults to 2048."
    puts "  TX_AFTER_IDLE_LOOPS    Defaults to 1."
}

set inject_hex ""
set inject_string ""
set no_leading_enter 0
set no_trailing_enter 0
set cmd_parts {}
set passthrough 0

for {set i 0} {$i < $argc} {incr i} {
    set token [lindex $argv $i]

    if {$passthrough} {
        lappend cmd_parts $token
        continue
    }

    switch -- $token {
        "--" {
            set passthrough 1
        }
        "--hex" {
            incr i
            if {$i >= $argc} {
                usage
                error "--hex requires a value"
            }
            set inject_hex [lindex $argv $i]
        }
        "--string" {
            incr i
            if {$i >= $argc} {
                usage
                error "--string requires a value"
            }
            set inject_string [lindex $argv $i]
        }
        "--no-leading-enter" {
            set no_leading_enter 1
        }
        "--no-trailing-enter" {
            set no_trailing_enter 1
        }
        "--help" -
        "-h" {
            usage
            exit 0
        }
        default {
            lappend cmd_parts $token
        }
    }
}

if {[info exists ::env(JTAG_LINUX_CMD_HEX)] && [string trim $::env(JTAG_LINUX_CMD_HEX)] ne ""} {
    set inject_hex [string trim $::env(JTAG_LINUX_CMD_HEX)]
}

if {[info exists ::env(JTAG_LINUX_CMD_STRING)] && $inject_hex eq "" && [string trim $::env(JTAG_LINUX_CMD_STRING)] ne ""} {
    set inject_string $::env(JTAG_LINUX_CMD_STRING)
}

if {$inject_hex eq "" && $inject_string eq ""} {
    set command_text [join $cmd_parts " "]
    set prefix [expr {$no_leading_enter ? "" : "\r"}]
    set suffix [expr {$no_trailing_enter ? "" : "\r"}]
    if {$command_text eq "" && $prefix eq "" && $suffix eq ""} {
        set inject_string "\r"
    } else {
        set inject_string "${prefix}${command_text}${suffix}"
    }
}

if {![info exists ::env(RESET_AND_LOAD)]} {
    set ::env(RESET_AND_LOAD) 0
}
if {![info exists ::env(CLEAR_CONSOLE)]} {
    set ::env(CLEAR_CONSOLE) 1
}
if {![info exists ::env(CLEAR_RX_OVERFLOW)]} {
    set ::env(CLEAR_RX_OVERFLOW) 1
}
if {![info exists ::env(JTAG_FREQ_HZ)]} {
    set ::env(JTAG_FREQ_HZ) 1000000
}
if {![info exists ::env(POLL_MS)]} {
    set ::env(POLL_MS) 5
}
if {![info exists ::env(MAX_IDLE_LOOPS)]} {
    set ::env(MAX_IDLE_LOOPS) 3000
}
if {![info exists ::env(MAX_DRAIN_READS)]} {
    set ::env(MAX_DRAIN_READS) 2048
}
if {![info exists ::env(TX_AFTER_IDLE_LOOPS)]} {
    set ::env(TX_AFTER_IDLE_LOOPS) 1
}
if {![info exists ::env(TX_LOG_ENABLE)]} {
    set ::env(TX_LOG_ENABLE) 0
}

catch {unset ::env(TX_HEX)}
catch {unset ::env(TX_STRING)}

if {$inject_hex ne ""} {
    set clean_hex [string map {" " "" "\t" "" "\n" "" "\r" "" "," "" "_" "" ":" "" "0x" "" "0X" ""} $inject_hex]
    if {([string length $clean_hex] % 2) != 0} {
        error "JTAG_LINUX_CMD_HEX / --hex must contain an even number of hex digits"
    }
    set ::env(TX_HEX) $clean_hex
} else {
    set ::env(TX_STRING) $inject_string
}

# The sourced script consumes env/argv and exits Vivado for us.
set ::argv {}
set ::argc 0
source [file join [file dirname [info script]] jtag_console_v2.tcl]
