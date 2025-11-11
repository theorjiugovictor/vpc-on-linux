# Building Your Own Virtual Private Cloud (VPC) on Linux from Scratch

## Introduction

Ever wondered how cloud providers like AWS create isolated networks for their customers? In this comprehensive guide, we'll build a fully functional Virtual Private Cloud (VPC) using only Linux networking primitives. No Docker, no Kubernetes – just pure Linux magic! 🐧

By the end of this tutorial, you'll have:
- ✅ Created isolated virtual networks (VPCs)
- ✅ Implemented subnets with public and private access
- ✅ Built a NAT gateway for internet access
- ✅ Enforced firewall rules (Security Groups)
- ✅ Enabled VPC peering for cross-VPC communication
- ✅ Automated everything with a custom CLI tool

## What We're Building

Imagine AWS VPC, but running entirely on your Linux machine. We'll use:

- **Network Namespaces**: Isolated network environments (think containers, but lighter)
- **Linux Bridges**: Virtual switches connecting our subnets
- **veth Pairs**: Virtual ethernet cables
- **iptables**: Firewall and NAT functionality
- **Routing Tables**: Traffic management between networks

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                       Your Linux Host                        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │             VPC 1 (10.0.0.0/16)                    │    │
│  │                                                     │    │
│  │      ┌─────────────────────────────┐              │    │
│  │      │  Bridge: vpc1-br0            │              │    │
│  │      │  (Virtual Router)            │              │    │
│  │      │  IP: 10.0.0.1                │              │    │
│  │      └──────┬──────────────┬────────┘              │    │
│  │             │              │                        │    │
│  │    ┌────────┴─────┐  ┌────┴────────┐              │    │
│  │    │Public Subnet │  │Private      │              │    │
│  │    │10.0.1.0/24   │  │Subnet       │              │    │
│  │    │[Namespace]   │  │10.0.2.0/24  │              │    │
│  │    │              │  │[Namespace]  │              │    │
│  │    │NAT Gateway✓  │  │No Internet✗ │              │    │
│  │    │Web Server:80 │  │Database:3306│              │    │
│  │    └──────────────┘  └─────────────┘              │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│         ↕ (VPC Peering)                                     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │             VPC 2 (172.16.0.0/16)                  │    │
│  │      Similar isolated structure...                  │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before we dive in, ensure you have:

```bash
# Check if tools are installed
which ip iptables python3

# Install if missing (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y iproute2 iptables bridge-utils python3

# For RHEL/CentOS
sudo yum install -y iproute iptables bridge-utils python3
```

You'll also need:
- Root/sudo access
- Basic understanding of networking (IP addresses, subnets)
- A Linux system (Ubuntu 20.04+ recommended)

## Part 1: Understanding the Building Blocks

### Network Namespaces: Your Virtual Subnets

Think of a network namespace as a completely isolated network environment. It's like having multiple computers, but virtually!

```bash
# Create a namespace
sudo ip netns add my-namespace

# List namespaces
sudo ip netns list

# Execute commands inside namespace
sudo ip netns exec my-namespace ip addr
```

### Linux Bridge: Your Virtual Switch

A bridge connects multiple network interfaces, just like a physical switch in your office.

```bash
# Create a bridge
sudo ip link add my-bridge type bridge

# Bring it up
sudo ip link set my-bridge up

# Assign an IP
sudo ip addr add 10.0.0.1/24 dev my-bridge
```

### veth Pairs: Virtual Ethernet Cables

veth (virtual ethernet) pairs are like virtual cables with two ends. One end goes in a namespace, the other connects to our bridge.

```bash
# Create veth pair
sudo ip link add veth0 type veth peer name veth1

# Move one end to namespace
sudo ip link set veth1 netns my-namespace

# Connect other end to bridge
sudo ip link set veth0 master my-bridge
sudo ip link set veth0 up
```

## Part 2: Building the vpcctl CLI Tool

Now let's automate everything with a Python CLI tool. I'll explain key sections:

### Core Structure

Our tool will have these main functions:
1. `create_vpc()` - Creates a VPC with a bridge
2. `add_subnet()` - Adds a subnet (namespace) to a VPC
3. `deploy_app()` - Deploys a web server in a subnet
4. `apply_firewall_rules()` - Applies security rules
5. `peer_vpcs()` - Connects two VPCs
6. `delete_vpc()` - Cleans up resources

### Creating a VPC

Here's what happens when you create a VPC:

```python
def create_vpc(vpc_name, cidr_block, internet_interface="eth0"):
    """
    1. Validate CIDR block (e.g., 10.0.0.0/16)
    2. Create a Linux bridge (vpc-name-br0)
    3. Assign first IP in range to bridge
    4. Enable IP forwarding
    5. Save state to JSON file
    """
    
    # Create bridge
    bridge_name = f"{vpc_name}-br0"
    run_command(f"sudo ip link add {bridge_name} type bridge")
    
    # Assign IP and bring up
    bridge_ip = "10.0.0.1"  # First IP in CIDR
    run_command(f"sudo ip addr add {bridge_ip}/16 dev {bridge_name}")
    run_command(f"sudo ip link set {bridge_name} up")
    
    # Enable IP forwarding (required for routing)
    run_command("sudo sysctl -w net.ipv4.ip_forward=1")
```

### Adding a Subnet

When adding a subnet:

```python
def add_subnet(vpc_name, subnet_name, subnet_cidr, subnet_type="private"):
    """
    1. Create network namespace (isolated environment)
    2. Create veth pair (virtual cable)
    3. Connect one end to bridge, other to namespace
    4. Configure IP and routing
    5. Setup NAT for public subnets
    """
    
    # Create namespace
    ns_name = f"{vpc_name}-{subnet_name}"
    run_command(f"sudo ip netns add {ns_name}")
    
    # Create veth pair
    veth_host = f"veth-{ns_name}"
    veth_ns = f"veth-ns-{subnet_name}"
    run_command(f"sudo ip link add {veth_host} type veth peer name {veth_ns}")
    
    # Connect to bridge
    run_command(f"sudo ip link set {veth_host} master {vpc['bridge']}")
    run_command(f"sudo ip link set {veth_host} up")
    
    # Move to namespace and configure
    run_command(f"sudo ip link set {veth_ns} netns {ns_name}")
    run_command(f"sudo ip netns exec {ns_name} ip addr add {subnet_ip}/24 dev {veth_ns}")
    run_command(f"sudo ip netns exec {ns_name} ip link set {veth_ns} up")
    
    # Add default route through bridge
    run_command(f"sudo ip netns exec {ns_name} ip route add default via {bridge_ip}")
```

### NAT Gateway for Public Subnets

For subnets that need internet access:

```python
if subnet_type == "public":
    # Enable NAT (Network Address Translation)
    run_command(f"sudo iptables -t nat -A POSTROUTING -s {subnet_cidr} -o {internet_iface} -j MASQUERADE")
    
    # Allow forwarding
    run_command(f"sudo iptables -A FORWARD -i {bridge} -o {internet_iface} -j ACCEPT")
    run_command(f"sudo iptables -A FORWARD -i {internet_iface} -o {bridge} -m state --state RELATED,ESTABLISHED -j ACCEPT")
```

## Part 3: Step-by-Step Usage Guide

### Step 1: Create Your First VPC

```bash
# Download and setup
git clone <your-repo>
cd vpc-on-linux
chmod +x vpcctl.py

# Create VPC with 10.0.0.0/16 CIDR block
sudo ./vpcctl.py create-vpc my-vpc 10.0.0.0/16
```

**What just happened?**
- Created a bridge named `my-vpc-br0`
- Assigned IP 10.0.0.1 to the bridge
- Enabled IP forwarding on your system

### Step 2: Add Public Subnet

```bash
# Add public subnet (with internet access)
sudo ./vpcctl.py add-subnet my-vpc web-subnet 10.0.1.0/24 --type public
```

**What just happened?**
- Created namespace `my-vpc-web-subnet`
- Created veth pair connecting namespace to bridge
- Configured IP 10.0.1.1 in the subnet
- Setup NAT rules for internet access

### Step 3: Add Private Subnet

```bash
# Add private subnet (no internet access)
sudo ./vpcctl.py add-subnet my-vpc db-subnet 10.0.2.0/24 --type private
```

**What just happened?**
- Created isolated namespace `my-vpc-db-subnet`
- Assigned IP 10.0.2.1
- NO NAT rules (no internet access)

### Step 4: Deploy Applications

```bash
# Deploy web server in public subnet
sudo ./vpcctl.py deploy-app my-vpc web-subnet --port 8000

# Deploy database in private subnet
sudo ./vpcctl.py deploy-app my-vpc db-subnet --port 8001
```

**What just happened?**
- Started Python HTTP servers in each namespace
- They're now accessible within the VPC

### Step 5: Test Connectivity

```bash
# Get subnet IPs
WEB_IP=$(sudo ip netns exec my-vpc-web-subnet ip addr show veth-ns-web-subnet | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
DB_IP=$(sudo ip netns exec my-vpc-db-subnet ip addr show veth-ns-db-subnet | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

echo "Web Server IP: $WEB_IP"
echo "Database IP: $DB_IP"

# Test from host to web server
curl http://$WEB_IP:8000

# Test from web server to database (inter-subnet)
sudo ip netns exec my-vpc-web-subnet curl http://$DB_IP:8001

# Test internet access from public subnet
sudo ip netns exec my-vpc-web-subnet ping -c 3 8.8.8.8

# Test internet access from private subnet (should fail)
sudo ip netns exec my-vpc-db-subnet ping -c 3 8.8.8.8
```

## Part 4: Advanced Features

### Firewall Rules (Security Groups)

Create a JSON file with your rules:

```json
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"},
    {"port": 3306, "protocol": "tcp", "action": "deny"}
  ]
}
```

Apply the rules:

```bash
# Save rules to file
cat > firewall_rules.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8000, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

# Apply rules
sudo ./vpcctl.py apply-firewall my-vpc web-subnet firewall_rules.json

# Verify rules
sudo ip netns exec my-vpc-web-subnet iptables -L -n
```

### VPC Peering

Connect two isolated VPCs:

```bash
# Create second VPC
sudo ./vpcctl.py create-vpc staging-vpc 172.16.0.0/16
sudo ./vpcctl.py add-subnet staging-vpc app-subnet 172.16.1.0/24 --type public

# Test isolation (should fail)
sudo ip netns exec my-vpc-web-subnet ping -c 2 172.16.1.1

# Create peering
sudo ./vpcctl.py peer-vpcs my-vpc staging-vpc

# Test again (should succeed)
sudo ip netns exec my-vpc-web-subnet ping -c 2 172.16.1.1
```

### List All VPCs

```bash
sudo ./vpcctl.py list
```

Output:
```
============================================================
VPC: my-vpc
  CIDR: 10.0.0.0/16
  Bridge: my-vpc-br0 (10.0.0.1)
  Subnets:
    - web-subnet:
        Type: public
        CIDR: 10.0.1.0/24
        IP: 10.0.1.1
        Namespace: my-vpc-web-subnet
    - db-subnet:
        Type: private
        CIDR: 10.0.2.0/24
        IP: 10.0.2.1
        Namespace: my-vpc-db-subnet
```

## Part 5: Testing and Validation

### Test 1: Intra-VPC Communication ✅

```bash
# Subnets within same VPC should communicate
sudo ip netns exec my-vpc-web-subnet ping -c 3 $DB_IP
# Expected: Success ✓
```

### Test 2: VPC Isolation ✅

```bash
# Different VPCs should be isolated
sudo ip netns exec my-vpc-web-subnet ping -c 3 172.16.1.1
# Expected: Failure (timeout) ✓
```

### Test 3: NAT Gateway ✅

```bash
# Public subnet has internet
sudo ip netns exec my-vpc-web-subnet ping -c 3 8.8.8.8
# Expected: Success ✓

# Private subnet blocked
sudo ip netns exec my-vpc-db-subnet ping -c 3 8.8.8.8
# Expected: Failure ✓
```

### Test 4: VPC Peering ✅

```bash
# After peering, VPCs can communicate
sudo ./vpcctl.py peer-vpcs my-vpc staging-vpc
sudo ip netns exec my-vpc-web-subnet ping -c 3 172.16.1.1
# Expected: Success ✓
```

### Test 5: Firewall Rules ✅

```bash
# Rules block/allow specific ports
# (Test by trying to connect to blocked ports)
```

## Part 6: Troubleshooting Guide

### Issue: Can't reach subnet from host

**Check:**
```bash
# Is bridge up?
sudo ip link show my-vpc-br0

# Do veth pairs exist?
sudo ip link | grep veth

# Is namespace configured?
sudo ip netns exec my-vpc-web-subnet ip addr
```

### Issue: No internet from public subnet

**Check:**
```bash
# Is IP forwarding enabled?
sudo sysctl net.ipv4.ip_forward
# Should show: net.ipv4.ip_forward = 1

# Do NAT rules exist?
sudo iptables -t nat -L -n | grep MASQUERADE

# Is default route set?
sudo ip netns exec my-vpc-web-subnet ip route
```

### Issue: Subnets can't communicate

**Check:**
```bash
# Can subnet reach bridge?
sudo ip netns exec my-vpc-web-subnet ping 10.0.0.1

# Check routing table
sudo ip netns exec my-vpc-web-subnet ip route

# Trace path
sudo ip netns exec my-vpc-web-subnet traceroute $DB_IP
```

## Part 7: Cleanup

### Clean specific VPC

```bash
sudo ./vpcctl.py delete-vpc my-vpc
```

### Clean everything

```bash
sudo ./vpcctl.py cleanup
```

### Manual cleanup (if needed)

```bash
# Delete all namespaces
sudo ip -all netns delete

# Delete all VPC bridges
sudo ip link show type bridge | grep vpc | while read line; do
    bridge=$(echo $line | awk '{print $2}' | tr -d ':')
    sudo ip link delete $bridge
done

# Flush iptables
sudo iptables -t nat -F
sudo iptables -F
```

## Part 8: Understanding the Magic

### How Does It All Work?

**1. Network Namespaces Create Isolation**
Each subnet is a namespace with its own network stack. It's like having multiple virtual machines, but much lighter.

**2. Bridges Route Traffic**
The bridge acts as a virtual switch, forwarding packets between connected veth interfaces based on MAC addresses.

**3. Routing Tables Direct Packets**
Each namespace has a routing table that says "send everything to the bridge" (default route).

**4. NAT Provides Internet Access**
iptables MASQUERADE rewrites packet source IPs from private (10.0.x.x) to public (your host's IP) for outbound traffic.

**5. iptables Enforces Security**
Rules in each namespace control what traffic is allowed in/out.

### Packet Flow Example

Let's trace a packet from public subnet to the internet:

```
1. App in namespace generates packet
   Source: 10.0.1.1
   Destination: 8.8.8.8

2. Packet sent to default gateway (bridge)
   via veth pair

3. Bridge forwards to host network stack

4. iptables NAT rule rewrites source IP
   Source: 10.0.1.1 → your-host-public-ip
   
5. Packet routed to internet

6. Response comes back
   Destination: your-host-public-ip
   
7. iptables NAT tracks connection and rewrites
   Destination: your-host-public-ip → 10.0.1.1
   
8. Packet forwarded back through bridge
   
9. Arrives at namespace via veth pair
```

## Conclusion

Congratulations! 🎉 You've built a production-grade VPC implementation using only Linux primitives. You now understand:

- How cloud providers create isolated networks
- Linux networking internals (namespaces, bridges, veth)
- NAT and routing mechanics
- Firewall rule enforcement
- Network virtualization concepts

### What's Next?

- Add DNS resolution within VPCs
- Implement load balancing across subnets
- Create VPN tunnels between VPCs
- Build a web UI for VPC management
- Integrate with container orchestration

### Key Takeaways

1. **Network namespaces** provide complete isolation
2. **Bridges** connect namespaces like physical switches
3. **veth pairs** are the "cables" connecting everything
4. **iptables** provides firewall and NAT functionality
5. **Routing tables** control traffic flow

## Resources

- Full code: [GitHub Repository]
- [Linux Network Namespaces Documentation](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [Linux Bridge Documentation](https://wiki.linuxfoundation.org/networking/bridge)
- [iptables Tutorial](https://www.netfilter.org/documentation/)

## Questions?

Feel free to reach out or open an issue on GitHub!

---

**Author**: Your Name  
**Date**: November 2025  
**Tags**: Linux, Networking, DevOps, VPC, Cloud Computing

Happy networking! 🚀
