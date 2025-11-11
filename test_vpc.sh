!/bin/bash
# Complete VPC Testing Script
# This script demonstrates all VPC functionality

set -e

VPCCTL="./vpcctl.py"
LOG_FILE="/tmp/vpc_test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[TEST]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${YELLOW}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Clear previous log
> "$LOG_FILE"

log "Starting VPC Testing Suite"
log "=========================================="

# Clean up any existing resources
log "Step 0: Cleaning up existing resources"
sudo python3 $VPCCTL cleanup 2>/dev/null || true
sleep 2

# Test 1: Create VPC 1
log "Step 1: Creating VPC 1 (10.0.0.0/16)"
sudo python3 $VPCCTL create-vpc vpc1 10.0.0.0/16 --interface eth0
sleep 1

# Test 2: Add subnets to VPC 1
log "Step 2: Adding public subnet to VPC 1"
sudo python3 $VPCCTL add-subnet vpc1 public-subnet 10.0.1.0/24 --type public
sleep 1

log "Step 3: Adding private subnet to VPC 1"
sudo python3 $VPCCTL add-subnet vpc1 private-subnet 10.0.2.0/24 --type private
sleep 1

# Test 3: Deploy applications
log "Step 4: Deploying web server in public subnet"
sudo python3 $VPCCTL deploy-app vpc1 public-subnet --port 8000
sleep 2

log "Step 5: Deploying web server in private subnet"
sudo python3 $VPCCTL deploy-app vpc1 private-subnet --port 8001
sleep 2

# Test 4: Test connectivity within VPC
log "Step 6: Testing connectivity within VPC 1"
info "Testing public subnet web server..."
PUBLIC_IP=$(sudo python3 -c "import json; state = json.load(open('/tmp/vpcctl_state.json')); print(state['vpcs']['vpc1']['subnets']['public-subnet']['ip'])" 2>/dev/null || echo "10.0.1.1")
PRIVATE_IP=$(sudo python3 -c "import json; state = json.load(open('/tmp/vpcctl_state.json')); print(state['vpcs']['vpc1']['subnets']['private-subnet']['ip'])" 2>/dev/null || echo "10.0.2.1")

echo "Public IP: $PUBLIC_IP"
echo "Private IP: $PRIVATE_IP"

# Test from host to public subnet
if curl -s --connect-timeout 5 http://$PUBLIC_IP:8000 > /dev/null; then
    log "✓ Host can reach public subnet web server"
else
    error "✗ Host cannot reach public subnet web server"
fi

# Test from host to private subnet
if curl -s --connect-timeout 5 http://$PRIVATE_IP:8001 > /dev/null; then
    log "✓ Host can reach private subnet web server"
else
    error "✗ Host cannot reach private subnet web server"
fi

# Test subnet-to-subnet communication
log "Step 7: Testing subnet-to-subnet communication"
if sudo ip netns exec vpc1-public-subnet ping -c 2 $PRIVATE_IP > /dev/null 2>&1; then
    log "✓ Public subnet can ping private subnet"
else
    error "✗ Public subnet cannot ping private subnet"
fi

# Test internet access from public subnet
log "Step 8: Testing internet access from public subnet"
if sudo ip netns exec vpc1-public-subnet ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    log "✓ Public subnet has internet access"
else
    error "✗ Public subnet does not have internet access (this might be expected in some environments)"
fi

# Test internet access from private subnet (should fail or be restricted)
log "Step 9: Testing internet access from private subnet"
if sudo ip netns exec vpc1-private-subnet ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    error "✗ Private subnet has internet access (should be blocked)"
else
    log "✓ Private subnet correctly has no internet access"
fi

# Test 5: Create second VPC for isolation testing
log "Step 10: Creating VPC 2 (172.16.0.0/16) for isolation testing"
sudo python3 $VPCCTL create-vpc vpc2 172.16.0.0/16 --interface eth0
sleep 1

log "Step 11: Adding subnet to VPC 2"
sudo python3 $VPCCTL add-subnet vpc2 public-subnet 172.16.1.0/24 --type public
sleep 1

log "Step 12: Deploying web server in VPC 2"
sudo python3 $VPCCTL deploy-app vpc2 public-subnet --port 8002
sleep 2

# Test VPC isolation
log "Step 13: Testing VPC isolation (vpc1 -> vpc2 should fail)"
VPC2_IP=$(sudo python3 -c "import json; state = json.load(open('/tmp/vpcctl_state.json')); print(state['vpcs']['vpc2']['subnets']['public-subnet']['ip'])" 2>/dev/null || echo "172.16.1.1")
echo "VPC2 IP: $VPC2_IP"

if sudo ip netns exec vpc1-public-subnet ping -c 2 $VPC2_IP > /dev/null 2>&1; then
    error "✗ VPC isolation broken - vpc1 can reach vpc2"
else
    log "✓ VPC isolation working - vpc1 cannot reach vpc2"
fi

# Test 6: VPC Peering
log "Step 14: Creating peering connection between VPC 1 and VPC 2"
sudo python3 $VPCCTL peer-vpcs vpc1 vpc2
sleep 2

log "Step 15: Testing connectivity after peering"
if sudo ip netns exec vpc1-public-subnet ping -c 2 $VPC2_IP > /dev/null 2>&1; then
    log "✓ After peering, vpc1 can reach vpc2"
else
    error "✗ After peering, vpc1 still cannot reach vpc2"
fi

# Test 7: Firewall rules
log "Step 16: Creating and applying firewall rules"
cat > /tmp/firewall_rules.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8000, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

sudo python3 $VPCCTL apply-firewall vpc1 public-subnet /tmp/firewall_rules.json
sleep 1

log "Step 17: Verifying firewall rules"
if sudo ip netns exec vpc1-public-subnet iptables -L -n | grep -q "tcp dpt:8000"; then
    log "✓ Firewall rules applied successfully"
else
    error "✗ Firewall rules not found"
fi

# Display VPC list
log "Step 18: Listing all VPCs"
sudo python3 $VPCCTL list

# Test 8: Resource inspection
log "Step 19: Inspecting network resources"
info "Network namespaces:"
sudo ip netns list

info "Bridges:"
sudo ip link show type bridge | grep -E "vpc|master"

info "VPC 1 routing table:"
sudo ip netns exec vpc1-public-subnet ip route

# Final summary
log "=========================================="
log "VPC Testing Complete!"
log "=========================================="
info "Summary of resources created:"
info "- 2 VPCs (vpc1: 10.0.0.0/16, vpc2: 172.16.0.0/16)"
info "- 3 Subnets (2 in vpc1, 1 in vpc2)"
info "- 3 Web servers deployed"
info "- VPC peering established"
info "- Firewall rules applied"
info ""
info "Log file: $LOG_FILE"
info "vpcctl log: /tmp/vpcctl.log"
info ""
info "To clean up, run: sudo python3 $VPCCTL cleanup"
