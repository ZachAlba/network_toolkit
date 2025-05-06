#!/bin/bash

# =============================
# Network Diagnostic Toolkit - CLI Launcher
# Author: Zachary Albanese
# =============================

show_menu() {
    echo "==============================="
    echo " Network Diagnostic Toolkit"
    echo "==============================="
    echo "1) Run manual diagnostics"
    echo "2) Run auto mode (batch scan from config.ini)"
    echo "3) View recent logs"
    echo "4) Set config.ini values"
    echo "5) Exit"
    echo
    read -p "Enter your choice [1-4]: " CHOICE
}

handle_args() {
    # Headless usage: --tool diagnostics --host google.com --output all
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --tool)
            TOOL="$2"
            shift
            ;;
        --host)
            HOST="$2"
            shift
            ;;
        --output)
            OUTPUT="$2"
            shift
            ;;
        *)
            echo "Unknown flag: $1"
            exit 1
            ;;
        esac
        shift
    done

    case "$TOOL" in
    diagnostics)
        bash tools/diagnostics.sh "$HOST" "--$OUTPUT"
        ;;
    auto)
        bash tools/auto_runner.sh
        ;;
    *)
        echo "Invalid --tool value: $TOOL"
        exit 1
        ;;
    esac
    exit 0
}

interactive_flow() {
    while true; do
        show_menu
        case "$CHOICE" in
        1)
            read -p "Enter host to scan: " HOST
            echo "Output types:"
            echo " 1) txt"
            echo " 2) json"
            echo " 3) csv"
            echo " 4) all"
            read -p "Select output format [1-4]: " OUTFMT
            case "$OUTFMT" in
            1) FLAG="--txt" ;;
            2) FLAG="--json" ;;
            3) FLAG="--csv" ;;
            4) FLAG="--all" ;;
            *)
                echo "Invalid option"
                continue
                ;;
            esac
            bash tools/diagnostics.sh "$HOST" "$FLAG"
            ;;
        2)
            bash tools/auto_runner.sh
            ;;
        3)
            echo "Showing recent logs..."
            find logs -type f | tail -n 10
            ;;
        4)
            echo "Goodbye."
            exit 0
            ;;
        *)
            echo "Invalid selection. Try again."
            ;;
        esac
        echo
    done
}

# Detect CLI or flag-based run
if [[ "$1" == "--tool" ]]; then
    handle_args "$@"
else
    interactive_flow
fi
