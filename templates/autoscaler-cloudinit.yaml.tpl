#cloud-config

debug: True

write_files:

${cloudinit_write_files_common}

- content: ${base64encode(k3s_config)}
  encoding: base64
  path: /tmp/config.yaml

- content: ${base64encode(install_k3s_agent_script)}
  encoding: base64
  path: /var/pre_install/install-k3s-agent.sh

# Apply DNS config
%{ if has_dns_servers ~}
manage_resolv_conf: true
resolv_conf:
  nameservers:
%{ for dns_server in dns_servers ~}
    - ${dns_server}
%{ endfor ~}
%{ endif ~}

# Add ssh authorized keys
ssh_authorized_keys:
%{ for key in sshAuthorizedKeys ~}
  - ${key}
%{ endfor ~}

# Resize /var, not /, as that's the last partition in MicroOS image.
growpart:
    devices: ["/var"]

# Make sure the hostname is set correctly
hostname: ${hostname}
preserve_hostname: true

runcmd:

${cloudinit_runcmd_common}

# Configure default routes based on public ip availability
%{if private_network_only~}
# Private-only setup: eth0 is the private interface
- [ip, route, add, default, via, '10.0.0.1', dev, 'eth0', metric, '100']
%{else~}
# Standard setup: eth0 is public, configure both IPv4 and IPv6
- [ip, route, add, default, via, '172.31.1.1', dev, 'eth0', metric, '100']
- [ip, -6, route, add, default, via, 'fe80::1', dev, 'eth0', metric, '100']
%{endif~}

# Custom networking setup for autoscaled nodes
%{ if custom_networking_autoscaler_enabled ~}
- |
  echo "Setting up custom networking for autoscaled node..."
  # Create the k3s config drop-in directory
  mkdir -p /etc/rancher/k3s/config.yaml.d

  # Create and execute the custom networking script
  cat <<'CUSTOM_NETWORKING_EOF' > /root/run-custom-networking-autoscaler.sh
  #!/bin/bash
  set -euxo pipefail

  # Export environment variables for the script
  export CLUSTER_NAME="${cluster_name}"
  export NODE_NAME="$(hostname)"
  export NETWORK_REGION="${network_region}"
  export ORIGINAL_NETWORK_CIDR="${original_network_cidr}"
  export CLUSTER_IPV4_CIDR="${cluster_ipv4_cidr}"
  export SERVICE_IPV4_CIDR="${service_ipv4_cidr}"
  export OUTPUT_FILE="${custom_networking_autoscaler_output_file}"

  # --- START OF USER SCRIPT ---
  ${custom_networking_autoscaler_script}
  # --- END OF USER SCRIPT ---

  # --- WRAPPER LOGIC ---
  if [ ! -f "$OUTPUT_FILE" ]; then
      echo "ERROR: Custom networking script did not produce output file at $OUTPUT_FILE" >&2
      exit 1
  fi

  # Parse the JSON output using python
  NODE_IP=$(python3 -c "import json; print(json.load(open('$OUTPUT_FILE')).get('node_ip', ''))")

  if [ -z "$NODE_IP" ]; then
      echo "ERROR: 'node_ip' not found or is empty in $OUTPUT_FILE" >&2
      exit 1
  fi

  echo "Successfully retrieved node_ip: $NODE_IP"
  echo "node-ip: $NODE_IP" > /etc/rancher/k3s/config.yaml.d/99-custom-ip.yaml
  CUSTOM_NETWORKING_EOF

  chmod +x /root/run-custom-networking-autoscaler.sh
  /root/run-custom-networking-autoscaler.sh
%{ endif ~}

# Start the install-k3s-agent service
- ['/bin/bash', '/var/pre_install/install-k3s-agent.sh']
