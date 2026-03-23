#!/usr/bin/env bash
set -euo pipefail

SSH_HOST=${SSH_HOST:-Administrator@100.125.4.76}
REMOTE_DIR=${REMOTE_DIR:-'E:\fpga\repo\riscv_soc\fpga\xc7a35t'}
VIVADO_SETTINGS=${VIVADO_SETTINGS:-'E:\vivado\2025.1\Vivado\settings64.bat'}
HW_SERVER_CMD=${HW_SERVER_CMD:-'E:\vivado\2025.1\Vivado\bin\hw_server.bat'}
HW_HOST=${HW_HOST:-192.168.0.171}
HW_PORT=${HW_PORT:-51235}
REMOTE_TCL=${REMOTE_TCL:-jtag_vivado_session.tcl}
JTAG_FREQ_HZ=${JTAG_FREQ_HZ:-1000000}
POLL_MS=${POLL_MS:-5}
MAX_IDLE_LOOPS=${MAX_IDLE_LOOPS:-3000}
MAX_DRAIN_READS=${MAX_DRAIN_READS:-2048}
TX_WAIT_LOOPS=${TX_WAIT_LOOPS:-4000}
TX_WAIT_MS=${TX_WAIT_MS:-1}
STARTUP_TIMEOUT_SECS=${STARTUP_TIMEOUT_SECS:-90}
RESPONSE_TIMEOUT_SECS=${RESPONSE_TIMEOUT_SECS:-90}
VERBOSE=${VERBOSE:-0}

REMOTE_PID=""
REMOTE_IN=""
REMOTE_OUT=""
STARTED=0

usage() {
    cat <<'EOF'
Usage:
  jtag_linux_session.sh                 # interactive session
  jtag_linux_session.sh --cmd <cmd...>  # run one command and exit
  jtag_linux_session.sh <cmd...>        # same as --cmd

Interactive meta-commands:
  :quit      Exit the local session and stop remote Vivado
  :ping      Check the persistent Vivado/JTAG worker is alive
  :help      Show help

Notes:
  - This V2 flow keeps a single remote Vivado Tcl session alive for the whole
    lifetime of this script.
  - When this local script exits, it sends QUIT and the remote Vivado session
    is closed automatically.
EOF
}

startup_log=()

log_debug() {
    if [[ "${VERBOSE}" == "1" ]]; then
        printf '[debug] %s\n' "$*" >&2
    fi
}

hex_encode_stdin() {
    python3 -c 'import sys; sys.stdout.write(sys.stdin.buffer.read().hex().upper())'
}

decode_hex_file_to_stdout() {
    local file="$1"
    python3 - "$file" <<'PY'
import pathlib
import sys

hex_data = pathlib.Path(sys.argv[1]).read_text().strip()
if hex_data:
    sys.stdout.buffer.write(bytes.fromhex(hex_data))
PY
}

remote_command_string() {
    printf '%s' \
        "cmd /v /c \"cd /d ${REMOTE_DIR} && call ${VIVADO_SETTINGS} && set HW_HOST=${HW_HOST} && set HW_PORT=${HW_PORT} && set HW_SERVER_CMD=${HW_SERVER_CMD} && set JTAG_FREQ_HZ=${JTAG_FREQ_HZ} && set POLL_MS=${POLL_MS} && set MAX_IDLE_LOOPS=${MAX_IDLE_LOOPS} && set MAX_DRAIN_READS=${MAX_DRAIN_READS} && set TX_WAIT_LOOPS=${TX_WAIT_LOOPS} && set TX_WAIT_MS=${TX_WAIT_MS} && set CLEAR_CONSOLE_BEFORE_CMD=1 && set CLEAR_RX_OVERFLOW=1 && vivado -mode tcl -notrace -nolog -nojournal -source ${REMOTE_TCL}\""
}

start_remote_session() {
    local remote_cmd
    remote_cmd=$(remote_command_string)

    coproc JTAG_VIVADO {
        ssh -T -o StrictHostKeyChecking=no "${SSH_HOST}" "${remote_cmd}" 2>&1
    }

    REMOTE_OUT=${JTAG_VIVADO[0]}
    REMOTE_IN=${JTAG_VIVADO[1]}
    REMOTE_PID=${JTAG_VIVADO_PID}
    STARTED=1
    wait_for_ready
    warmup_console
}

wait_for_ready() {
    local line
    startup_log=()
    while IFS= read -r -t "${STARTUP_TIMEOUT_SECS}" -u "${REMOTE_OUT}" line; do
        line=${line%$'\r'}
        case "$line" in
            __CODEX_JTAG_READY__*)
                log_debug "$line"
                return 0
                ;;
            "")
                ;;
            *)
                startup_log+=("$line")
                if [[ ${#startup_log[@]} -gt 30 ]]; then
                    startup_log=("${startup_log[@]: -30}")
                fi
                log_debug "startup: $line"
                ;;
        esac
    done

    printf 'Failed to start remote Vivado session within %ss.\n' "${STARTUP_TIMEOUT_SECS}" >&2
    if [[ ${#startup_log[@]} -gt 0 ]]; then
        printf 'Last remote lines:\n' >&2
        printf '  %s\n' "${startup_log[@]}" >&2
    fi
    return 1
}

send_remote_line() {
    local line="$1"
    printf '%s\n' "$line" >&"${REMOTE_IN}"
}

read_response() {
    local line
    local status=""
    local tmp_hex
    local tmp_err_hex
    local mode=""

    tmp_hex=$(mktemp)
    tmp_err_hex=$(mktemp)

    while IFS= read -r -t "${RESPONSE_TIMEOUT_SECS}" -u "${REMOTE_OUT}" line; do
        line=${line%$'\r'}
        case "$line" in
            __CODEX_JTAG_BEGIN__)
                mode=""
                ;;
            STATUS\ *)
                status=${line#STATUS }
                ;;
            RESULT_HEX_BEGIN)
                mode="result"
                ;;
            RESULT_HEX_END)
                mode=""
                ;;
            ERROR_HEX_BEGIN)
                mode="error"
                ;;
            ERROR_HEX_END)
                mode=""
                ;;
            TOTAL_CHARS\ *|OVERFLOW_SEEN\ *|TX_OVERFLOW_SEEN\ *|STATUS_END\ *|UART_STATUS_END\ *|CONSOLE_END\ *|CONSOLE_RX_END\ *)
                log_debug "$line"
                ;;
            __CODEX_JTAG_END__)
                break
                ;;
            __CODEX_JTAG_WARN__*)
                log_debug "$line"
                ;;
            *)
                case "$mode" in
                    result)
                        printf '%s' "$line" >>"$tmp_hex"
                        ;;
                    error)
                        printf '%s' "$line" >>"$tmp_err_hex"
                        ;;
                    *)
                        log_debug "extra: $line"
                        ;;
                esac
                ;;
        esac
    done

    if [[ -z "${status}" ]]; then
        printf 'Timed out waiting for remote command response within %ss.\n' "${RESPONSE_TIMEOUT_SECS}" >&2
        rm -f "$tmp_hex" "$tmp_err_hex"
        return 1
    fi

    if [[ "${status}" == "OK" ]]; then
        decode_hex_file_to_stdout "$tmp_hex"
        rm -f "$tmp_hex" "$tmp_err_hex"
        return 0
    fi

    if [[ -s "$tmp_err_hex" ]]; then
        decode_hex_file_to_stdout "$tmp_err_hex" >&2
        printf '\n' >&2
    else
        printf 'Remote session returned an unknown error.\n' >&2
    fi
    rm -f "$tmp_hex" "$tmp_err_hex"
    return 1
}

run_command() {
    local command_text="$1"
    local payload_hex
    payload_hex=$(printf '%s\r' "$command_text" | hex_encode_stdin)
    send_remote_line "EXEC_HEX ${payload_hex}"
    read_response
}

warmup_console() {
    send_remote_line "EXEC_HEX 0D"
    read_response >/dev/null 2>/dev/null || true
}

ping_remote() {
    local line
    send_remote_line "PING"
    while IFS= read -r -u "${REMOTE_OUT}" line; do
        line=${line%$'\r'}
        case "$line" in
            __CODEX_JTAG_PONG__)
                printf 'PONG\n'
                return 0
                ;;
            *)
                log_debug "ping-extra: $line"
                ;;
        esac
    done
    return 1
}

cleanup() {
    local rc=$?

    if [[ "${STARTED}" == "1" ]]; then
        {
            printf 'QUIT\n' >&"${REMOTE_IN}"
        } 2>/dev/null || true

        if [[ -n "${REMOTE_IN}" && "${REMOTE_IN}" =~ ^[0-9]+$ ]]; then
            eval "exec ${REMOTE_IN}>&-"
        fi

        if [[ -n "${REMOTE_OUT}" && "${REMOTE_OUT}" =~ ^[0-9]+$ ]]; then
            local line
            while IFS= read -r -t 0.5 -u "${REMOTE_OUT}" line; do
                line=${line%$'\r'}
                [[ "$line" == "__CODEX_JTAG_BYE__" ]] && break
            done || true
            eval "exec ${REMOTE_OUT}<&-"
        fi

        if [[ -n "${REMOTE_PID}" ]]; then
            sleep 0.2
            kill -0 "${REMOTE_PID}" 2>/dev/null && kill "${REMOTE_PID}" 2>/dev/null || true
            wait "${REMOTE_PID}" 2>/dev/null || true
        fi
    fi

    exit "$rc"
}

interactive_loop() {
    local cmd
    while true; do
        if [[ -t 0 ]]; then
            read -e -r -p "jtag-linux> " cmd || {
                printf '\n'
                break
            }
        else
            printf 'jtag-linux> ' >&2
            read -r cmd || {
                printf '\n' >&2
                break
            }
        fi

        if [[ -z "${cmd:-}" ]]; then
            printf '\n'
            continue
        fi

        case "$cmd" in
            :quit|:q)
                break
                ;;
            :help)
                usage
                ;;
            :ping)
                ping_remote
                ;;
            *)
                run_command "$cmd"
                [[ "$cmd" != "" ]] && printf '\n'
                ;;
        esac
    done
}

trap cleanup EXIT INT TERM

if [[ $# -gt 0 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
    usage
    exit 0
fi

start_remote_session

if [[ $# -eq 0 ]]; then
    interactive_loop
    exit 0
fi

if [[ "$1" == "--cmd" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
        printf -- "--cmd requires a command\n" >&2
        exit 2
    fi
fi

run_command "$*"
