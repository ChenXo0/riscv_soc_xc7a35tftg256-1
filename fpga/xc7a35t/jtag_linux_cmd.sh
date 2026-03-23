#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SSH_HOST=${SSH_HOST:-Administrator@100.125.4.76}
REMOTE_DIR=${REMOTE_DIR:-'E:\fpga\repo\riscv_soc\fpga\xc7a35t'}
VIVADO_SETTINGS=${VIVADO_SETTINGS:-'E:\vivado\2025.1\Vivado\settings64.bat'}
CONTROL_PATH=${CONTROL_PATH:-"$HOME/.ssh/controlmasters/riscv_soc_xc7a35t"}

JTAG_FREQ_HZ=${JTAG_FREQ_HZ:-1000000}
POLL_MS=${POLL_MS:-5}
MAX_IDLE_LOOPS=${MAX_IDLE_LOOPS:-3000}
MAX_DRAIN_READS=${MAX_DRAIN_READS:-2048}
VIVADO_BIN=${VIVADO_BIN:-vivado}

usage() {
    cat <<'EOF'
Usage:
  jtag_linux_cmd.sh --start-master
  jtag_linux_cmd.sh --stop-master
  jtag_linux_cmd.sh --status-master
  jtag_linux_cmd.sh --attach
  jtag_linux_cmd.sh <linux command ...>

Examples:
  jtag_linux_cmd.sh --start-master
  jtag_linux_cmd.sh ls /
  jtag_linux_cmd.sh cat /proc/cpuinfo
  jtag_linux_cmd.sh 'uname -a'
  jtag_linux_cmd.sh --attach

Notes:
  - The SSH master connection is kept alive in the background to remove repeated
    SSH handshake cost, but each command still launches a fresh remote Vivado
    batch session in this V1 flow.
  - The target Linux system must already be loaded and running on the FPGA.
  - Override SSH_HOST/REMOTE_DIR/VIVADO_SETTINGS/JTAG_FREQ_HZ via environment
    variables if needed.
EOF
}

mkdir -p "$(dirname "$CONTROL_PATH")"

ssh_master_opts=(
  -o StrictHostKeyChecking=no
  -o ControlPath="$CONTROL_PATH"
)

ssh_cmd_opts=(
  -o StrictHostKeyChecking=no
  -o ControlMaster=auto
  -o ControlPath="$CONTROL_PATH"
)

master_running() {
    ssh "${ssh_master_opts[@]}" -O check "$SSH_HOST" >/dev/null 2>&1
}

start_master() {
    if master_running; then
        echo "SSH master already running for $SSH_HOST"
        return 0
    fi

    ssh -fN \
        -o StrictHostKeyChecking=no \
        -o ControlMaster=yes \
        -o ControlPersist=8h \
        -o ControlPath="$CONTROL_PATH" \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        "$SSH_HOST"

    echo "Started SSH master for $SSH_HOST"
}

stop_master() {
    if master_running; then
        ssh "${ssh_master_opts[@]}" -O exit "$SSH_HOST"
    else
        echo "SSH master is not running for $SSH_HOST" >&2
        return 1
    fi
}

status_master() {
    ssh "${ssh_master_opts[@]}" -O check "$SSH_HOST"
}

ensure_master() {
    if ! master_running; then
        start_master >/dev/null
    fi
}

hex_encode() {
    python3 - "$1" <<'PY'
import sys
payload = sys.argv[1].encode("utf-8")
print(payload.hex().upper())
PY
}

run_remote() {
    local remote_cmd="$1"
    ensure_master
    ssh "${ssh_cmd_opts[@]}" "$SSH_HOST" "$remote_cmd"
}

run_attach() {
    local remote_cmd
    printf -v remote_cmd '%s' \
        "cmd /v /c \"cd /d ${REMOTE_DIR} && call ${VIVADO_SETTINGS} && set RESET_AND_LOAD=0 && set CLEAR_CONSOLE=0 && set CLEAR_RX_OVERFLOW=1 && set TX_LOG_ENABLE=0 && set JTAG_FREQ_HZ=${JTAG_FREQ_HZ} && set POLL_MS=${POLL_MS} && set MAX_IDLE_LOOPS=-1 && set MAX_DRAIN_READS=${MAX_DRAIN_READS} && ${VIVADO_BIN} -mode batch -notrace -nolog -nojournal -source jtag_console_v2.tcl\""
    run_remote "$remote_cmd"
}

run_linux_command() {
    local command_text="$1"
    local payload_hex
    local remote_cmd

    payload_hex=$(hex_encode $'\r'"${command_text}"$'\r')

    printf -v remote_cmd '%s' \
        "cmd /v /c \"cd /d ${REMOTE_DIR} && call ${VIVADO_SETTINGS} && set RESET_AND_LOAD=0 && set CLEAR_CONSOLE=1 && set CLEAR_RX_OVERFLOW=1 && set TX_LOG_ENABLE=0 && set JTAG_FREQ_HZ=${JTAG_FREQ_HZ} && set POLL_MS=${POLL_MS} && set MAX_IDLE_LOOPS=${MAX_IDLE_LOOPS} && set MAX_DRAIN_READS=${MAX_DRAIN_READS} && set JTAG_LINUX_CMD_HEX=${payload_hex} && ${VIVADO_BIN} -mode batch -notrace -nolog -nojournal -source jtag_exec_cmd.tcl\""
    run_remote "$remote_cmd"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

case "${1:-}" in
    --help|-h)
        usage
        ;;
    --start-master)
        start_master
        ;;
    --stop-master)
        stop_master
        ;;
    --status-master)
        status_master
        ;;
    --attach)
        shift
        if [[ $# -ne 0 ]]; then
            echo "--attach does not take extra arguments" >&2
            exit 2
        fi
        run_attach
        ;;
    *)
        run_linux_command "$*"
        ;;
esac
