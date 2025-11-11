!/bin/bash
# Example Configuration Files Generator
# This script creates example firewall rules and configurations

# Create examples directory
mkdir -p examples

# Example 1: Web Server Firewall Rules
cat > examples/web_server_rules.json <<'EOF'
{
  "subnet": "10.0.1.0/24",
  "description": "Web server security group - allows HTTP/HTTPS, blocks SSH",
  "ingress": [
    {
      "port": 80,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Allow HTTP traffic"
    },
    {
      "port": 443,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Allow HTTPS traffic"
    },
    {
      "port": 22,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block SSH from external"
    },
    {
      "port": 3306,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block MySQL access"
    }
  ]
}
EOF

# Example 2: Database Server Rules
cat > examples/database_rules.json <<'EOF'
{
  "subnet": "10.0.2.0/24",
  "description": "Database server security group - only MySQL from web tier",
  "ingress": [
    {
      "port": 3306,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Allow MySQL from application tier"
    },
    {
      "port": 22,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block SSH"
    },
    {
      "port": 80,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block HTTP"
    }
  ]
}
EOF

# Example 3: Application Server Rules
cat > examples/app_server_rules.json <<'EOF'
{
  "subnet": "10.0.3.0/24",
  "description": "Application server security group",
  "ingress": [
    {
      "port": 8080,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Allow application traffic"
    },
    {
      "port": 8443,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Allow secure application traffic"
    },
    {
      "port": 22,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Allow SSH for management"
    }
  ]
}
EOF

# Example 4: Development Environment Rules (more permissive)
cat > examples/dev_rules.json <<'EOF'
{
  "subnet": "10.0.10.0/24",
  "description": "Development environment - permissive rules",
  "ingress": [
    {
      "port": 22,
      "protocol": "tcp",
      "action": "allow",
      "comment": "SSH access"
    },
    {
      "port": 80,
      "protocol": "tcp",
      "action": "allow",
      "comment": "HTTP"
    },
    {
      "port": 443,
      "protocol": "tcp",
      "action": "allow",
      "comment": "HTTPS"
    },
    {
      "port": 3000,
      "protocol": "tcp",
      "action": "allow",
      "comment": "React dev server"
    },
    {
      "port": 5000,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Flask/FastAPI dev"
    },
    {
      "port": 8000,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Django dev"
    }
  ]
}
EOF

# Example 5: Production Lockdown Rules
cat > examples/prod_lockdown_rules.json <<'EOF'
{
  "subnet": "10.0.100.0/24",
  "description": "Production environment - strict rules",
  "ingress": [
    {
      "port": 443,
      "protocol": "tcp",
      "action": "allow",
      "comment": "HTTPS only"
    },
    {
      "port": 80,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block HTTP - use HTTPS"
    },
    {
      "port": 22,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block SSH - use bastion"
    },
    {
      "port": 3389,
      "protocol": "tcp",
      "action": "deny",
      "comment": "Block RDP"
    }
  ]
}
EOF

# Create comprehensive cleanup script
cat > cleanup.sh <<'CLEANUP_EOF'
#!/bin/bash
# Comprehensive VPC Cleanup Script
# Removes all VPC resources safely

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}VPC Cleanup Script${NC}"
echo "===================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run with sudo${NC}"
    exit 1
fi

# Ask for confirmation
read -p "This will delete ALL VPC resources. Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Step 1: Using vpcctl cleanup${NC}"
if [ -f "./vpcctl.py" ]; then
    python3 vpcctl.py cleanup 2>/dev/null || echo "vpcctl cleanup completed with warnings"
else
    echo "vpcctl.py not found, proceeding with manual cleanup..."
fi

echo ""
echo -e "${YELLOW}Step 2: Removing network namespaces${NC}"
# List and delete all namespaces
for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
    echo "Deleting namespace: $ns"
    ip netns delete $ns 2>/dev/null || true
done

echo ""
echo -e "${YELLOW}Step 3: Removing bridges${NC}"
# Find and delete all VPC bridges
for bridge in $(ip link show type bridge 2>/dev/null | grep -o 'vpc[^:]*' || true); do
    echo "Deleting bridge: $bridge"
    ip link set $bridge down 2>/dev/null || true
    ip link delete $bridge 2>/dev/null || true
done

echo ""
echo -e "${YELLOW}Step 4: Cleaning up veth pairs${NC}"
# Remove any orphaned veth interfaces
for veth in $(ip link show type veth 2>/dev/null | grep -o 'veth[^:@]*' || true); do
    echo "Deleting veth: $veth"
    ip link delete $veth 2>/dev/null || true
done

echo ""
echo -e "${YELLOW}Step 5: Flushing iptables rules${NC}"
# Flush NAT rules
iptables -t nat -F 2>/dev/null || true
echo "NAT table flushed"

# Flush filter rules (careful with this in production!)
read -p "Flush ALL iptables filter rules? This may affect other services (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    iptables -F 2>/dev/null || true
    echo "Filter table flushed"
else
    echo "Skipping filter table flush"
fi

echo ""
echo -e "${YELLOW}Step 6: Cleaning up state files${NC}"
rm -f /tmp/vpcctl_state.json
rm -f /tmp/vpcctl.log
rm -f /tmp/vpc_test.log
rm -rf /tmp/*_web 2>/dev/null || true
rm -f /tmp/*_server.log 2>/dev/null || true
echo "State files removed"

echo ""
echo -e "${YELLOW}Step 7: Verification${NC}"
echo "Remaining namespaces:"
ip netns list 2>/dev/null || echo "  None"

echo ""
echo "Remaining bridges:"
ip link show type bridge 2>/dev/null | grep vpc || echo "  None"

echo ""
echo "Remaining veth pairs:"
ip link show type veth 2>/dev/null | grep veth || echo "  None"

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
echo ""
echo "Note: If you see any remaining resources, they may be from other applications."
echo "To completely reset networking, consider rebooting the system."
CLEANUP_EOF

chmod +x cleanup.sh

# Create quick setup script
cat > quick_setup.sh <<'SETUP_EOF'
#!/bin/bash
# Quick Setup Script - Creates a demo VPC environment

set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Quick VPC Setup${NC}"
echo "==============="
echo ""

# Clean up first
echo "Cleaning up any existing VPCs..."
sudo python3 vpcctl.py cleanup 2>/dev/null || true
sleep 1

# Create VPC
echo ""
echo "Creating VPC: demo-vpc (10.0.0.0/16)"
sudo python3 vpcctl.py create-vpc demo-vpc 10.0.0.0/16

# Add public subnet
echo ""
echo "Adding public subnet (10.0.1.0/24)"
sudo python3 vpcctl.py add-subnet demo-vpc public 10.0.1.0/24 --type public

# Add private subnet
echo ""
echo "Adding private subnet (10.0.2.0/24)"
sudo python3 vpcctl.py add-subnet demo-vpc private 10.0.2.0/24 --type private

# Deploy apps
echo ""
echo "Deploying web server in public subnet..."
sudo python3 vpcctl.py deploy-app demo-vpc public --port 8000

echo ""
echo "Deploying service in private subnet..."
sudo python3 vpcctl.py deploy-app demo-vpc private --port 8001

sleep 2

# Get IPs
PUBLIC_IP=$(sudo ip netns exec demo-vpc-public ip addr show veth-ns-public | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
PRIVATE_IP=$(sudo ip netns exec demo-vpc-private ip addr show veth-ns-private | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

echo ""
echo -e "${GREEN}Setup Complete!${NC}"
echo "================"
echo ""
echo "VPC Information:"
echo "  VPC Name: demo-vpc"
echo "  VPC CIDR: 10.0.0.0/16"
echo ""
echo "Public Subnet:"
echo "  IP: $PUBLIC_IP"
echo "  Web Server: http://$PUBLIC_IP:8000"
echo "  Internet Access: Yes"
echo ""
echo "Private Subnet:"
echo "  IP: $PRIVATE_IP"
echo "  Service: http://$PRIVATE_IP:8001"
echo "  Internet Access: No"
echo ""
echo "Quick Tests:"
echo "  1. Access public web server:"
echo "     curl http://$PUBLIC_IP:8000"
echo ""
echo "  2. Test internet from public subnet:"
echo "     sudo ip netns exec demo-vpc-public ping -c 3 8.8.8.8"
echo ""
echo "  3. Test inter-subnet connectivity:"
echo "     sudo ip netns exec demo-vpc-public curl http://$PRIVATE_IP:8001"
echo ""
echo "  4. List all VPCs:"
echo "     sudo python3 vpcctl.py list"
echo ""
echo "To cleanup: sudo python3 vpcctl.py cleanup"
SETUP_EOF

chmod +x quick_setup.sh

# Create README for examples
cat > examples/README.md <<'EOF'
# Firewall Rules Examples

This directory contains example firewall rule configurations for different use cases.

## Files

- `web_server_rules.json` - Rules for a public-facing web server
- `database_rules.json` - Strict rules for a database server
- `app_server_rules.json` - Rules for an application server
- `dev_rules.json` - Permissive rules for development
- `prod_lockdown_rules.json` - Strict production rules

## Usage

```bash
# Apply rules to a subnet
sudo ./vpcctl.py apply-firewall <vpc-name> <subnet-name> examples/<rules-file>.json

# Example:
sudo ./vpcctl.py apply-firewall my-vpc web-subnet examples/web_server_rules.json
```

## Rule Format

```json
{
  "subnet": "CIDR block",
  "description": "Description of rules",
  "ingress": [
    {
      "port": 80,
      "protocol": "tcp",
      "action": "allow",
      "comment": "Description"
    }
  ]
}
```

## Actions

- `allow` - Allow traffic on this port
- `deny` - Block traffic on this port

## Protocols

- `tcp` - TCP protocol
- `udp` - UDP protocol
- `icmp` - ICMP protocol

## Best Practices

1. **Principle of Least Privilege**: Only allow necessary ports
2. **Default Deny**: Block everything, then allow specific traffic
3. **Layer Security**: Use multiple layers of defense
4. **Regular Audits**: Review and update rules regularly
5. **Document Changes**: Keep comments explaining each rule

## Security Tips

- Always block port 22 (SSH) from external networks
- Use HTTPS (443) instead of HTTP (80) in production
- Restrict database ports (3306, 5432) to application tier only
- Consider using a bastion host for SSH access
- Enable logging for security events
EOF

echo "Example configuration files created in examples/"
echo ""
echo "Files created:"
echo "  - examples/web_server_rules.json"
echo "  - examples/database_rules.json"
echo "  - examples/app_server_rules.json"
echo "  - examples/dev_rules.json"
echo "  - examples/prod_lockdown_rules.json"
echo "  - examples/README.md"
echo "  - cleanup.sh"
echo "  - quick_setup.sh"
