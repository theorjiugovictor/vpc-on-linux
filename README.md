# VPC on Linux - Virtual Private Cloud Implementation

A complete implementation of AWS-style Virtual Private Cloud (VPC) functionality using Linux networking primitives.

> NOTE: This repo includes both an automated demo driven by the Makefile (run `make demo` or `make test`) and a set of individual scripts/commands (`quick_setup.sh`, `test_vpc.sh`, `create_examples.sh` and `vpcctl.py`) so you can either run the full demo end-to-end or execute the steps manually for finer control. The project is intentionally structured this way to make it easy to reproduce the demo or dig into each operation step-by-step.

## 🏗️ Architecture

This project creates isolated virtual networks on a single Linux host using:

- **Network Namespaces**: Isolated network environments (subnets)
- **Linux Bridges**: Virtual switches connecting subnets
- **veth Pairs**: Virtual ethernet connections
- **iptables**: Firewall rules and NAT gateway
- **Routing Tables**: Inter-subnet and inter-VPC routing

```
Host System
├── VPC 1 (10.0.0.0/16)
│   ├── Bridge: vpc1-br0
│   ├── Public Subnet (10.0.1.0/24) [Namespace]
│   │   └── Web Server (NAT enabled)
│   └── Private Subnet (10.0.2.0/24) [Namespace]
│       └── Web Server (No internet)
│
└── VPC 2 (172.16.0.0/16)
    ├── Bridge: vpc2-br0
    └── Public Subnet (172.16.1.0/24) [Namespace]
        └── Web Server
```

## 📋 Prerequisites

- Linux system with root/sudo access
- Python 3.6+
- Standard Linux networking tools:
  - `iproute2` (ip command)
  - `iptables`
  - `bridge-utils`

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y iproute2 iptables bridge-utils python3

# RHEL/CentOS
sudo yum install -y iproute iptables bridge-utils python3
```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd vpc-on-linux
chmod +x vpcctl.py test_vpc.sh
```

### 2. Create Your First VPC

```bash
# Create VPC
sudo ./vpcctl.py create-vpc my-vpc 10.0.0.0/16

# Add public subnet with NAT
sudo ./vpcctl.py add-subnet my-vpc web-subnet 10.0.1.0/24 --type public

# Add private subnet
sudo ./vpcctl.py add-subnet my-vpc db-subnet 10.0.2.0/24 --type private

# Deploy web servers
sudo ./vpcctl.py deploy-app my-vpc web-subnet --port 8000
sudo ./vpcctl.py deploy-app my-vpc db-subnet --port 8001

# List all VPCs
sudo ./vpcctl.py list
```

### 3. Test Connectivity

```bash
# Get subnet IPs
WEB_IP=$(sudo ip netns exec my-vpc-web-subnet ip addr show veth-ns-web-subnet | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
DB_IP=$(sudo ip netns exec my-vpc-db-subnet ip addr show veth-ns-db-subnet | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

# Test from host
curl http://$WEB_IP:8000

# Test inter-subnet communication
sudo ip netns exec my-vpc-web-subnet curl http://$DB_IP:8001

# Test internet access from public subnet
sudo ip netns exec my-vpc-web-subnet ping -c 3 8.8.8.8

# Test internet access from private subnet (should fail)
sudo ip netns exec my-vpc-db-subnet ping -c 3 8.8.8.8
```

## 📚 CLI Usage

### Create VPC

```bash
sudo ./vpcctl.py create-vpc <vpc-name> <cidr-block> [--interface <interface>]

# Example
sudo ./vpcctl.py create-vpc production 10.0.0.0/16 --interface eth0
```

### Add Subnet

```bash
sudo ./vpcctl.py add-subnet <vpc-name> <subnet-name> <cidr> [--type public|private]

# Examples
sudo ./vpcctl.py add-subnet production public-web 10.0.1.0/24 --type public
sudo ./vpcctl.py add-subnet production private-db 10.0.2.0/24 --type private
```

### Deploy Application

```bash
sudo ./vpcctl.py deploy-app <vpc-name> <subnet-name> [--port <port>]

# Example
sudo ./vpcctl.py deploy-app production public-web --port 8080
```

### Apply Firewall Rules

Create a JSON file with rules:

```json
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
```

Apply rules:

```bash
sudo ./vpcctl.py apply-firewall <vpc-name> <subnet-name> <rules-file>

# Example
sudo ./vpcctl.py apply-firewall production public-web firewall_rules.json
```

### VPC Peering

```bash
sudo ./vpcctl.py peer-vpcs <vpc1-name> <vpc2-name>

# Example
sudo ./vpcctl.py peer-vpcs production staging
```

### List VPCs

```bash
sudo ./vpcctl.py list
```

### Delete VPC

```bash
sudo ./vpcctl.py delete-vpc <vpc-name>

# Example
sudo ./vpcctl.py delete-vpc production
```

### Cleanup All

```bash
sudo ./vpcctl.py cleanup
```

## 🧪 Running Tests

Run the complete test suite:

```bash
sudo ./test_vpc.sh
```

This script will:
1. Create two VPCs with multiple subnets
2. Deploy web servers in each subnet
3. Test intra-VPC connectivity
4. Verify VPC isolation
5. Create VPC peering
6. Apply and verify firewall rules
7. Test NAT gateway functionality
8. Display all resources

## 🔍 Validation Tests

### Test 1: Intra-VPC Communication

```bash
# Create VPC with two subnets
sudo ./vpcctl.py create-vpc test-vpc 192.168.0.0/16
sudo ./vpcctl.py add-subnet test-vpc subnet-a 192.168.1.0/24
sudo ./vpcctl.py add-subnet test-vpc subnet-b 192.168.2.0/24
sudo ./vpcctl.py deploy-app test-vpc subnet-a --port 8000
sudo ./vpcctl.py deploy-app test-vpc subnet-b --port 8001

# Test connectivity
IP_A=$(sudo ip netns exec test-vpc-subnet-a ip addr show veth-ns-subnet-a | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
IP_B=$(sudo ip netns exec test-vpc-subnet-b ip addr show veth-ns-subnet-b | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

# Subnet A -> Subnet B
sudo ip netns exec test-vpc-subnet-a ping -c 3 $IP_B
sudo ip netns exec test-vpc-subnet-a curl http://$IP_B:8001

# Expected: Success ✓
```

### Test 2: VPC Isolation

```bash
# Create two VPCs
sudo ./vpcctl.py create-vpc vpc-a 10.1.0.0/16
sudo ./vpcctl.py add-subnet vpc-a subnet-a 10.1.1.0/24 --type public
sudo ./vpcctl.py create-vpc vpc-b 10.2.0.0/16
sudo ./vpcctl.py add-subnet vpc-b subnet-b 10.2.1.0/24 --type public

# Try to ping across VPCs
IP_A=$(sudo ip netns exec vpc-a-subnet-a ip addr show veth-ns-subnet-a | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
IP_B=$(sudo ip netns exec vpc-b-subnet-b ip addr show veth-ns-subnet-b | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

sudo ip netns exec vpc-a-subnet-a ping -c 3 $IP_B

# Expected: Failure (timeout) ✓
```

### Test 3: NAT Gateway

```bash
# Public subnet should have internet access
sudo ip netns exec test-vpc-public-subnet ping -c 3 8.8.8.8
sudo ip netns exec test-vpc-public-subnet curl -I https://www.google.com

# Expected: Success ✓

# Private subnet should NOT have internet access
sudo ip netns exec test-vpc-private-subnet ping -c 3 8.8.8.8

# Expected: Failure ✓
```

### Test 4: Firewall Rules

```bash
# Create rule file
cat > /tmp/test_rules.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8000, "protocol": "tcp", "action": "allow"},
    {"port": 8080, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

sudo ./vpcctl.py apply-firewall test-vpc public-subnet /tmp/test_rules.json

# Verify rules are applied
sudo ip netns exec test-vpc-public-subnet iptables -L -n

# Expected: Rules visible in iptables ✓
```

### Test 5: VPC Peering

```bash
# Create peering
sudo ./vpcctl.py peer-vpcs vpc-a vpc-b

# Test connectivity after peering
sudo ip netns exec vpc-a-subnet-a ping -c 3 $IP_B

# Expected: Success ✓
```

## 📊 Verification Commands

```bash
# List all network namespaces
sudo ip netns list

# List all bridges
sudo ip link show type bridge

# Check routes in a namespace
sudo ip netns exec <namespace> ip route

# Check iptables rules in namespace
sudo ip netns exec <namespace> iptables -L -n

# Check NAT rules
sudo iptables -t nat -L -n

# Monitor traffic on bridge
sudo tcpdump -i vpc1-br0 -n

# Check active connections
sudo ss -tunap
```

## 🔧 Troubleshooting

### Issue: Cannot reach subnet from host

```bash
# Check bridge is up
sudo ip link show vpc1-br0

# Check veth pairs exist
sudo ip link | grep veth

# Check namespace has correct IP
sudo ip netns exec <namespace> ip addr
```

### Issue: No internet access from public subnet

```bash
# Check IP forwarding is enabled
sudo sysctl net.ipv4.ip_forward

# Check NAT rules exist
sudo iptables -t nat -L -n | grep MASQUERADE

# Check default route in namespace
sudo ip netns exec <namespace> ip route
```

### Issue: Cannot communicate between subnets

```bash
# Check bridge has correct IP
sudo ip addr show vpc1-br0

# Check routes in namespace
sudo ip netns exec <namespace> ip route

# Test connectivity to bridge
sudo ip netns exec <namespace> ping <bridge-ip>
```

## 🧹 Cleanup

### Clean up specific VPC

```bash
sudo ./vpcctl.py delete-vpc <vpc-name>
```

### Clean up all resources

```bash
sudo ./vpcctl.py cleanup

# Manual cleanup if needed
sudo ip -all netns delete
sudo ip link delete $(ip link show type bridge | grep vpc | awk '{print $2}' | tr -d ':')
sudo iptables -t nat -F
sudo iptables -F
```

## 📝 State Management

The tool maintains state in `/tmp/vpcctl_state.json`:

```json
{
  "vpcs": {
    "vpc1": {
      "cidr": "10.0.0.0/16",
      "bridge": "vpc1-br0",
      "bridge_ip": "10.0.0.1",
      "subnets": {
        "public-subnet": {
          "cidr": "10.0.1.0/24",
          "type": "public",
          "namespace": "vpc1-public-subnet",
          "ip": "10.0.1.1"
        }
      }
    }
  }
}
```

## 🔒 Security Considerations

- All operations require root/sudo privileges
- Firewall rules are enforced at the namespace level
- NAT provides isolation from external networks
- Private subnets have no internet access by default
- VPC isolation prevents unauthorized cross-VPC traffic

## 📖 How It Works

### Network Namespace (Subnet)

Each subnet is a network namespace - an isolated network environment with its own routing table, firewall rules, and network interfaces.

### Linux Bridge (VPC Router)

The bridge acts as a virtual switch, connecting all subnets within a VPC and handling packet forwarding between them.

### veth Pairs (Virtual Cables)

Virtual ethernet pairs connect namespaces to bridges. One end is in the namespace, the other is attached to the bridge.

### NAT Gateway

For public subnets, iptables MASQUERADE rules translate private IPs to the host's public IP for outbound traffic.

### VPC Peering

A veth pair connects two bridges, with static routes allowing traffic flow between VPC CIDR blocks.

## 🎯 Project Goals Checklist

- ✅ Create and manage VPCs with CIDR blocks
- ✅ Add public and private subnets
- ✅ Enable routing between subnets
- ✅ Implement NAT for public subnet internet access
- ✅ Demonstrate VPC isolation
- ✅ Implement VPC peering
- ✅ Apply firewall rules (Security Groups)
- ✅ Automate with CLI tool
- ✅ Clean resource teardown
- ✅ Comprehensive logging

## 📚 Additional Resources

- [Linux Network Namespaces](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [Linux Bridge Documentation](https://wiki.linuxfoundation.org/networking/bridge)
- [iptables Tutorial](https://www.netfilter.org/documentation/HOWTO/packet-filtering-HOWTO.html)
- [veth Pairs Explained](https://man7.org/linux/man-pages/man4/veth.4.html)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is for educational purposes as part of the DevOps Internship program.
