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

# Get IPs from the state file or namespace
PUBLIC_IP=$(sudo python3 -c "import json; state = json.load(open('/tmp/vpcctl_state.json')); print(state['vpcs']['demo-vpc']['subnets']['public']['ip'])" 2>/dev/null || echo "10.0.1.1")
PRIVATE_IP=$(sudo python3 -c "import json; state = json.load(open('/tmp/vpcctl_state.json')); print(state['vpcs']['demo-vpc']['subnets']['private']['ip'])" 2>/dev/null || echo "10.0.2.1")

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
