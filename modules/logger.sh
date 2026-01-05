#!/bin/bash
# logger.sh
# Bash module for logging deployment activities

# Global variables
LOG_FILE=""
LOG_LEVEL="INFO"

# Initialize logger with directory and optional log level
# Usage: initialize_logger <log_directory> [log_level]
initialize_logger() {
    local log_directory="$1"
    local level="${2:-INFO}"
    
    # Create log directory if it doesn't exist
    mkdir -p "$log_directory"
    
    # Generate log file name with timestamp
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="$log_directory/vault_setup_${timestamp}.log"
    LOG_LEVEL="$level"
    
    log_message "INFO" "Logger initialized. Log file: $LOG_FILE"
}

# Write log message with level and timestamp
# Usage: log_message <level> <message>
log_message() {
    local level="$1"
    shift
    local message="$*"
    
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] [$level] $message"
    
    # Write to log file
    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
    
    # Write to console with colors
    local color_code=""
    case "$level" in
        DEBUG)
            color_code="\033[0;37m"  # Gray
            ;;
        INFO)
            color_code="\033[0;37m"  # White
            ;;
        WARN)
            color_code="\033[1;33m"  # Yellow
            ;;
        ERROR)
            color_code="\033[1;31m"  # Red
            ;;
        *)
            color_code="\033[0m"     # Default
            ;;
    esac
    
    echo -e "${color_code}${log_entry}\033[0m"
}

# Write section header for better log organization
# Usage: write_section_header <title>
write_section_header() {
    local title="$1"
    local separator="================================================================================"
    
    log_message "INFO" "$separator"
    log_message "INFO" "  $title"
    log_message "INFO" "$separator"
}

# Get current log file path
# Usage: get_log_file_path
get_log_file_path() {
    echo "$LOG_FILE"
}

# Export functions for use in other scripts
export -f initialize_logger
export -f log_message
export -f write_section_header
export -f get_log_file_path
