!/bin/bash
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
