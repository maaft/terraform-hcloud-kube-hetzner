# Custom Networking Guide

This guide covers how to use Kube-Hetzner's custom networking feature to replace Hetzner's default private networking with your own overlay network solutions like WireGuard, Tailscale, Nebula, and others.

## Overview

Custom networking allows you to:

- Replace Hetzner's private network with any VPN solution
- Create secure mesh networks spanning multiple cloud providers
- Integrate with existing corporate VPN infrastructure
- Implement zero-trust networking principles
- Use advanced VPN features like traffic shaping and access controls

When enabled, Kubernetes cluster communication will use the custom overlay network IPs instead of Hetzner's private network IPs.

## Architecture

The custom networking feature uses a dual-script architecture:

1. **Static Nodes Script**: Configures overlay networking for control plane nodes and regular agent pools
2. **Autoscaler Nodes Script**: Configures overlay networking for autoscaler-created nodes (optional)

Each script runs during node initialization and must output the assigned overlay IP address in JSON format.

## Configuration

### Basic Configuration

Add the `custom_networking` block to your `kube.tf`:

```hcl
custom_networking = {
  enabled = true

  static_nodes = {
    script_content = <<-EOT
      #!/bin/bash
      # Your VPN setup script here
      # Must output JSON with the assigned IP
      echo '{"ipv4_address": "100.64.0.1"}' > "${OUTPUT_FILE}"
    EOT
  }
}
```

### Full Configuration

```hcl
custom_networking = {
  enabled = true

  # Configuration for static nodes (control planes, agent pools)
  static_nodes = {
    script_content      = file("./scripts/setup-overlay.sh")
    interpreter         = "/bin/bash"           # Default: "/bin/bash"
    timeout_seconds     = 300                   # Default: 300
    max_retries         = 3                     # Default: 3
    retry_delay_seconds = 30                    # Default: 30
    output_file         = "/tmp/custom-net.json" # Default: "/tmp/custom-networking.json"
  }

  # Configuration for autoscaler nodes (optional)
  autoscaler_nodes = {
    enabled             = true                  # Default: false
    script_content      = file("./scripts/setup-overlay-autoscaler.sh")
    interpreter         = "/bin/bash"           # Inherits from static_nodes
    timeout_seconds     = 180                   # Inherits from static_nodes
    max_retries         = 2                     # Inherits from static_nodes
    retry_delay_seconds = 15                    # Inherits from static_nodes
    output_file         = "/tmp/autoscaler-net.json" # Default: "/tmp/custom-networking-autoscaler.json"
  }
}
```

## Environment Variables

Your scripts have access to these environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `CLUSTER_NAME` | Kubernetes cluster name | `"k3s"` |
| `NODE_NAME` | Node hostname | `"k3s-control-plane-fsn1"` |
| `NODE_INDEX` | Node index in nodepool | `"0"`, `"1"`, `"2"` |
| `NODEPOOL_NAME` | Nodepool name | `"control-plane-fsn1"` |
| `NODE_ROLE` | Node role | `"control-plane"` or `"agent"` |
| `HCLOUD_TOKEN` | Hetzner Cloud API token | Your API token |
| `NETWORK_REGION` | Hetzner network region | `"eu-central"` |
| `LOCATION` | Hetzner datacenter | `"fsn1"` |
| `SERVER_TYPE` | Hetzner server type | `"cx22"` |
| `ORIGINAL_NETWORK_CIDR` | Hetzner private network CIDR | `"10.0.0.0/8"` |
| `CLUSTER_IPV4_CIDR` | Kubernetes cluster CIDR | `"10.42.0.0/16"` |
| `SERVICE_IPV4_CIDR` | Kubernetes service CIDR | `"10.43.0.0/16"` |
| `OUTPUT_FILE` | Where to write JSON output | `"/tmp/custom-networking.json"` |
| `SCRIPT_TIMEOUT` | Script timeout in seconds | `"300"` |

## Script Requirements

### Output Format

Your script **must** write a JSON file to `$OUTPUT_FILE` with the assigned overlay network IP:

```json
{
  "ipv4_address": "100.64.0.1"
}
```

### Exit Codes

- Exit `0` for success
- Exit non-zero for failure (will trigger retries)

### Error Handling

The wrapper script handles:
- Timeouts (configurable)
- Retries with exponential backoff
- Logging to system journal
- Fallback to Hetzner private networking on failure

## VPN Solution Examples

### Tailscale

```bash
#!/bin/bash
set -euo pipefail

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Configure and start
tailscale up --authkey="${TAILSCALE_AUTHKEY}" \
  --hostname="${NODE_NAME}" \
  --accept-routes \
  --accept-dns=false

# Wait for IP assignment
for i in {1..30}; do
  OVERLAY_IP=$(tailscale ip -4 2>/dev/null || echo "")
  if [[ -n "$OVERLAY_IP" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$OVERLAY_IP" ]]; then
  echo "Failed to get Tailscale IP" >&2
  exit 1
fi

# Output IP
echo "{\"ipv4_address\": \"$OVERLAY_IP\"}" > "${OUTPUT_FILE}"
```

### WireGuard

```bash
#!/bin/bash
set -euo pipefail

# Install WireGuard
zypper install -y wireguard-tools

# Generate keys
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# Get IP from your WireGuard coordinator
# (This is implementation-specific)
OVERLAY_IP=$(curl -s "https://your-coordinator.com/register" \
  -d "node=${NODE_NAME}" \
  -d "public_key=${PUBLIC_KEY}" | jq -r '.ip')

# Configure WireGuard
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${OVERLAY_IP}/24
ListenPort = 51820

[Peer]
PublicKey = YOUR_SERVER_PUBLIC_KEY
Endpoint = your-server.com:51820
AllowedIPs = 10.0.0.0/8
PersistentKeepalive = 25
EOF

# Start WireGuard
systemctl enable --now wg-quick@wg0

# Output IP
echo "{\"ipv4_address\": \"$OVERLAY_IP\"}" > "${OUTPUT_FILE}"
```

### Nebula

```bash
#!/bin/bash
set -euo pipefail

# Install Nebula
curl -L https://github.com/slackhq/nebula/releases/latest/download/nebula-linux-amd64.tar.gz | tar -xz -C /usr/local/bin/

# Download certificates from your certificate authority
# (Implementation-specific)
mkdir -p /etc/nebula
curl -s "https://your-ca.com/cert/${NODE_NAME}" > /etc/nebula/host.crt
curl -s "https://your-ca.com/key/${NODE_NAME}" > /etc/nebula/host.key
curl -s "https://your-ca.com/ca.crt" > /etc/nebula/ca.crt

# Get assigned IP from certificate
OVERLAY_IP=$(nebula-cert print -path /etc/nebula/host.crt | grep -oP 'ip: \K[0-9.]+')

# Configure Nebula
cat > /etc/nebula/config.yml <<EOF
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/host.crt
  key: /etc/nebula/host.key

static_host_map:
  "192.168.100.1": ["your-lighthouse.com:4242"]

lighthouse:
  am_lighthouse: false
  interval: 60
  hosts:
    - "192.168.100.1"

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true

tun:
  disabled: false
  dev: nebula1
  drop_local_broadcast: false
  drop_multicast: false
  tx_queue: 500
  mtu: 1300

logging:
  level: info
  format: text

firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any
EOF

# Start Nebula
systemctl enable --now nebula

# Output IP
echo "{\"ipv4_address\": \"$OVERLAY_IP\"}" > "${OUTPUT_FILE}"
```

## Troubleshooting

### Check Script Execution

View logs from the custom networking setup:

```bash
# On any node
journalctl -u custom-networking-setup --no-pager
```

### Verify Overlay Network

Check if the overlay network is working:

```bash
# Test connectivity between nodes
ping <overlay-ip-of-another-node>

# Check VPN status (example for Tailscale)
tailscale status

# Verify Kubernetes is using overlay IPs
kubectl get nodes -o wide
```

### Common Issues

1. **Script timeout**: Increase `timeout_seconds` in configuration
2. **Network connectivity**: Ensure nodes can reach your VPN coordinator/lighthouse
3. **Authentication**: Check VPN credentials and tokens
4. **Firewall**: Ensure VPN ports are open in Hetzner firewall rules

### Debugging Scripts

Add debugging to your scripts:

```bash
#!/bin/bash
set -euxo pipefail  # Add -x for verbose output

# Log to journal
logger -t custom-networking "Starting setup for ${NODE_NAME}"

# Your setup logic here...

logger -t custom-networking "Setup complete, IP: ${OVERLAY_IP}"
```

## Best Practices

### Security

1. **Rotate credentials**: Regularly rotate VPN authentication keys
2. **Least privilege**: Give nodes only necessary VPN permissions
3. **Network segmentation**: Use VPN ACLs to restrict node-to-node communication
4. **Monitor traffic**: Set up logging and monitoring for VPN connections

### Reliability

1. **Health checks**: Implement connectivity monitoring in your scripts
2. **Graceful degradation**: Handle partial VPN failures gracefully
3. **Backup connectivity**: Consider dual-VPN setups for critical deployments
4. **Resource limits**: Monitor VPN daemon resource usage

### Performance

1. **Choose appropriate MTU**: Set MTU to avoid fragmentation
2. **Optimize encryption**: Use hardware-accelerated crypto when available
3. **Monitor latency**: Track overlay network performance
4. **Tune keepalives**: Optimize connection persistence settings

## Migration Guide

### From Hetzner Private Networking

1. **Test in staging**: Always test custom networking in a non-production environment first
2. **Plan maintenance**: Switching networking requires cluster recreation
3. **Backup data**: Ensure all persistent data is backed up
4. **Update monitoring**: Adjust monitoring to use new IP ranges

### Script Updates

When updating your networking scripts:

1. **Version scripts**: Keep versioned copies of working scripts
2. **Test changes**: Validate script changes on test nodes first
3. **Rolling updates**: Consider gradual rollout strategies
4. **Rollback plan**: Always have a rollback plan ready

## Advanced Configurations

### Multi-Region Mesh

For clusters spanning multiple regions:

```hcl
custom_networking = {
  enabled = true

  static_nodes = {
    script_content = <<-EOT
      # Determine region-specific configuration
      case "${LOCATION}" in
        fsn1|nbg1|hel1)
          REGION="eu-central"
          LIGHTHOUSE="eu-lighthouse.example.com"
          ;;
        ash)
          REGION="us-east"
          LIGHTHOUSE="us-lighthouse.example.com"
          ;;
      esac

      # Configure region-specific overlay
      setup_overlay_for_region "$REGION" "$LIGHTHOUSE"
    EOT
  }
}
```

### High Availability VPN

For redundant VPN connections:

```bash
#!/bin/bash
# Setup primary and backup VPN connections
setup_primary_vpn() {
  # Primary VPN setup
}

setup_backup_vpn() {
  # Backup VPN setup
}

# Try primary, fallback to backup
if ! setup_primary_vpn; then
  setup_backup_vpn
fi
```

---

For more examples and community-contributed scripts, see the [examples directory](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/tree/master/examples) in the main repository.