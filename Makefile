.PHONY: help setup demo test test-connectivity test-isolation test-nat test-peering clean clean-all

help:
	@echo "VPC on Linux - Makefile Commands"
	@echo "================================="
	@echo "make setup          - Set up prerequisites"
	@echo "make demo           - Run complete demo"
	@echo "make test           - Run all tests"
	@echo "make test-connectivity - Test intra-VPC communication"
	@echo "make test-isolation - Test VPC isolation"
	@echo "make test-nat       - Test NAT gateway"
	@echo "make test-peering   - Test VPC peering"
	@echo "make clean          - Clean up test resources"
	@echo "make clean-all      - Clean up all VPC resources"

setup:
	@echo "Checking prerequisites..."
	@which ip || (echo "Installing iproute2..." && sudo apt-get install -y iproute2)
	@which iptables || (echo "Installing iptables..." && sudo apt-get install -y iptables)
	@which python3 || (echo "Installing python3..." && sudo apt-get install -y python3)
	@echo "Making vpcctl.py executable..."
	@chmod +x vpcctl.py test_vpc.sh
	@echo "Setup complete!"

demo: clean-all
	@echo "Running complete VPC demo..."
	@echo "============================"
	@echo ""
	@echo "Step 1: Creating VPC 1..."
	sudo python3 vpcctl.py create-vpc vpc1 10.0.0.0/16
	@sleep 1
	
	@echo ""
	@echo "Step 2: Adding subnets to VPC 1..."
	sudo python3 vpcctl.py add-subnet vpc1 public-subnet 10.0.1.0/24 --type public
	sudo python3 vpcctl.py add-subnet vpc1 private-subnet 10.0.2.0/24 --type private
	@sleep 1
	
	@echo ""
	@echo "Step 3: Deploying applications..."
	sudo python3 vpcctl.py deploy-app vpc1 public-subnet --port 8000
	sudo python3 vpcctl.py deploy-app vpc1 private-subnet --port 8001
	@sleep 2
	
	@echo ""
	@echo "Step 4: Creating VPC 2..."
	sudo python3 vpcctl.py create-vpc vpc2 172.16.0.0/16
	sudo python3 vpcctl.py add-subnet vpc2 public-subnet 172.16.1.0/24 --type public
	sudo python3 vpcctl.py deploy-app vpc2 public-subnet --port 8002
	@sleep 2
	
	@echo ""
	@echo "Step 5: Testing VPC isolation..."
	@echo "VPC 1 public subnet trying to reach VPC 2..."
	@sudo ip netns exec vpc1-public-subnet ping -c 2 172.16.1.1 || echo "✓ VPCs are isolated (expected failure)"
	
	@echo ""
	@echo "Step 6: Creating VPC peering..."
	sudo python3 vpcctl.py peer-vpcs vpc1 vpc2
	@sleep 1
	
	@echo ""
	@echo "Step 7: Testing connectivity after peering..."
	@sudo ip netns exec vpc1-public-subnet ping -c 2 172.16.1.1 && echo "✓ VPCs can communicate after peering" || echo "✗ Peering failed"
	
	@echo ""
	@echo "Step 8: Listing all VPCs..."
	sudo python3 vpcctl.py list
	
	@echo ""
	@echo "Demo complete! Run 'make clean-all' to clean up."

test:
	@echo "Running all tests..."
	sudo ./test_vpc.sh

test-connectivity: clean-all
	@echo "Testing intra-VPC connectivity..."
	@echo "================================"
	sudo python3 vpcctl.py create-vpc test-vpc 192.168.0.0/16
	sudo python3 vpcctl.py add-subnet test-vpc subnet-a 192.168.1.0/24
	sudo python3 vpcctl.py add-subnet test-vpc subnet-b 192.168.2.0/24
	sudo python3 vpcctl.py deploy-app test-vpc subnet-a --port 8000
	sudo python3 vpcctl.py deploy-app test-vpc subnet-b --port 8001
	@sleep 2
	@echo "Testing subnet-a -> subnet-b..."
	@sudo ip netns exec test-vpc-subnet-a ping -c 3 192.168.2.1 && echo "✓ Connectivity test passed" || echo "✗ Connectivity test failed"
	@sudo python3 vpcctl.py cleanup

test-isolation: clean-all
	@echo "Testing VPC isolation..."
	@echo "======================="
	sudo python3 vpcctl.py create-vpc vpc-a 10.1.0.0/16
	sudo python3 vpcctl.py add-subnet vpc-a subnet-a 10.1.1.0/24
	sudo python3 vpcctl.py create-vpc vpc-b 10.2.0.0/16
	sudo python3 vpcctl.py add-subnet vpc-b subnet-b 10.2.1.0/24
	@sleep 1
	@echo "Testing vpc-a -> vpc-b (should fail)..."
	@sudo ip netns exec vpc-a-subnet-a ping -c 2 10.2.1.1 || echo "✓ VPC isolation working (expected failure)"
	@sudo python3 vpcctl.py cleanup

test-nat: clean-all
	@echo "Testing NAT gateway..."
	@echo "====================="
	sudo python3 vpcctl.py create-vpc nat-test 10.10.0.0/16
	sudo python3 vpcctl.py add-subnet nat-test public 10.10.1.0/24 --type public
	sudo python3 vpcctl.py add-subnet nat-test private 10.10.2.0/24 --type private
	@sleep 1
	@echo "Testing public subnet internet access..."
	@sudo ip netns exec nat-test-public ping -c 2 8.8.8.8 && echo "✓ Public subnet has internet" || echo "✗ Public subnet NAT failed (check internet connection)"
	@echo "Testing private subnet internet access (should fail)..."
	@sudo ip netns exec nat-test-private ping -c 2 8.8.8.8 || echo "✓ Private subnet correctly blocked"
	@sudo python3 vpcctl.py cleanup

test-peering: clean-all
	@echo "Testing VPC peering..."
	@echo "====================="
	sudo python3 vpcctl.py create-vpc peer-a 10.20.0.0/16
	sudo python3 vpcctl.py add-subnet peer-a subnet 10.20.1.0/24
	sudo python3 vpcctl.py create-vpc peer-b 10.30.0.0/16
	sudo python3 vpcctl.py add-subnet peer-b subnet 10.30.1.0/24
	@sleep 1
	@echo "Testing before peering (should fail)..."
	@sudo ip netns exec peer-a-subnet ping -c 2 10.30.1.1 || echo "✓ No connectivity before peering"
	@echo "Creating peering connection..."
	sudo python3 vpcctl.py peer-vpcs peer-a peer-b
	@sleep 1
	@echo "Testing after peering (should succeed)..."
	@sudo ip netns exec peer-a-subnet ping -c 2 10.30.1.1 && echo "✓ Peering works" || echo "✗ Peering failed"
	@sudo python3 vpcctl.py cleanup

clean:
	@echo "Cleaning up test resources..."
	@sudo python3 vpcctl.py delete-vpc test-vpc 2>/dev/null || true
	@sudo python3 vpcctl.py delete-vpc nat-test 2>/dev/null || true
	@sudo python3 vpcctl.py delete-vpc peer-a 2>/dev/null || true
	@sudo python3 vpcctl.py delete-vpc peer-b 2>/dev/null || true
	@sudo python3 vpcctl.py delete-vpc vpc-a 2>/dev/null || true
	@sudo python3 vpcctl.py delete-vpc vpc-b 2>/dev/null || true
	@echo "Cleanup complete!"
	# Remove temporary state and logs
	@sudo rm -f /tmp/vpcctl_state.json /tmp/vpcctl.log 2>/dev/null || true

clean-all:
	@echo "Cleaning up all VPC resources..."
	@sudo python3 vpcctl.py cleanup 2>/dev/null || true
	@echo "All resources cleaned up!"
	# Remove temporary state and logs
	@sudo rm -f /tmp/vpcctl_state.json /tmp/vpcctl.log 2>/dev/null || true

show-state:
	@echo "Current VPC State:"
	@echo "=================="
	@cat /tmp/vpcctl_state.json 2>/dev/null || echo "No VPCs found"

show-logs:
	@echo "VPC Control Logs:"
	@echo "================="
	@cat /tmp/vpcctl.log 2>/dev/null || echo "No logs found"

show-namespaces:
	@echo "Network Namespaces:"
	@echo "==================="
	@sudo ip netns list

show-bridges:
	@echo "Bridges:"
	@echo "========"
	@sudo ip link show type bridge | grep -E "^[0-9]+:|vpc"

show-nat:
	@echo "NAT Rules:"
	@echo "=========="
	@sudo iptables -t nat -L -n | grep -A 5 POSTROUTING
