#!/bin/bash
set -euo pipefail

# Custom Networking Script Wrapper
# This script executes user-provided networking configuration

SCRIPT_NAME="custom-networking-wrapper"
OUTPUT_FILE="${output_file}"
MAX_RETRIES=${max_retries}
RETRY_DELAY=${retry_delay_seconds}
TIMEOUT_SECONDS=${timeout_seconds}

# Environment variables for the user script
export CLUSTER_NAME="${cluster_name}"
export NODE_NAME="${node_name}"
export NODE_INDEX="${node_index}" 
export NODEPOOL_NAME="${nodepool_name}"
export NODE_ROLE="${node_role}"
export HCLOUD_TOKEN="${hcloud_token}"
export NETWORK_REGION="${network_region}"
export LOCATION="${location}"
export SERVER_TYPE="${server_type}"
export ORIGINAL_NETWORK_CIDR="${original_network_cidr}"
export CLUSTER_IPV4_CIDR="${cluster_ipv4_cidr}"
export SERVICE_IPV4_CIDR="${service_ipv4_cidr}"
export OUTPUT_FILE="$OUTPUT_FILE"
export SCRIPT_TIMEOUT="$TIMEOUT_SECONDS"

# Custom user parameters
%{ for key, value in input_parameters ~}
export ${key}="${value}"
%{ endfor ~}

log() {
    echo "[$SCRIPT_NAME] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

validate_output() {
    local output_file="$1"
    
    if [ ! -f "$output_file" ]; then
        log "ERROR: Output file not found: $output_file"
        return 1
    fi
    
    if ! python3 -m json.tool "$output_file" >/dev/null 2>&1; then
        log "ERROR: Output file is not valid JSON"
        return 1
    fi
    
    # Check required fields
    %{ for field in required_outputs ~}
    if ! python3 -c "import json; data=json.load(open('$output_file')); exit(0 if '${field}' in data else 1)" 2>/dev/null; then
        log "ERROR: Required field '${field}' missing from output"
        return 1
    fi
    %{ endfor ~}
    
    # Check status field
    local status=$(python3 -c "import json; data=json.load(open('$output_file')); print(data.get('status', ''))" 2>/dev/null || echo "")
    if [ "$status" != "success" ]; then
        log "ERROR: Script reported status: $status"
        return 1
    fi
    
    return 0
}

execute_script() {
    local attempt="$1"
    log "Attempt $attempt: Executing custom networking script"
    
    # Remove previous output file
    rm -f "$OUTPUT_FILE"
    
    # Create temporary script file
    local temp_script=$(mktemp)
    cat > "$temp_script" <<'SCRIPT_EOF'
${script_content}
SCRIPT_EOF
    
    chmod +x "$temp_script"
    
    # Execute with timeout
    if timeout "$TIMEOUT_SECONDS" ${interpreter} "$temp_script"; then
        log "Script executed successfully"
        rm -f "$temp_script"
        
        # Validate output
        if validate_output "$OUTPUT_FILE"; then
            log "Output validation successful"
            return 0
        else
            log "Output validation failed"
            return 1
        fi
    else
        local exit_code=$?
        log "Script execution failed with exit code: $exit_code"
        rm -f "$temp_script"
        return $exit_code
    fi
}

# Main execution with retry logic
log "Starting custom networking configuration"

for attempt in $(seq 1 $MAX_RETRIES); do
    if execute_script "$attempt"; then
        log "Custom networking configuration completed successfully"
        
        # Display final configuration
        log "Final network configuration:"
        cat "$OUTPUT_FILE" >&2
        
        exit 0
    else
        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Attempt $attempt failed, retrying in $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
            # Exponential backoff
            RETRY_DELAY=$((RETRY_DELAY * 2))
        else
            log "All $MAX_RETRIES attempts failed"
            
            # Create error output if script didn't create one
            if [ ! -f "$OUTPUT_FILE" ]; then
                cat > "$OUTPUT_FILE" <<EOF
{
  "status": "error",
  "message": "Custom networking script failed after $MAX_RETRIES attempts",
  "error_code": "SCRIPT_EXECUTION_FAILED"
}
EOF
            fi
            
            exit 1
        fi
    fi
done