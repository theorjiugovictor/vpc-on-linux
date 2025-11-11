#!/usr/bin/env python3
"""
vpcctl - Virtual Private Cloud Management Tool
A CLI tool to create and manage VPCs using Linux networking primitives
"""

import subprocess
import json
import sys
import os
import argparse
from pathlib import Path
import ipaddress
import hashlib

# State file to track VPC configurations
STATE_FILE = "/tmp/vpcctl_state.json"
LOG_FILE = "/tmp/vpcctl.log"

def log(message):
    """Log messages to both console and log file"""
    print(f"[vpcctl] {message}")
    with open(LOG_FILE, "a") as f:
        f.write(f"[vpcctl] {message}\n")

def run_command(cmd, check=True, capture=True):
    """Execute shell command and return output"""
    log(f"Executing: {cmd}")
    try:
        if capture:
            result = subprocess.run(
                cmd, shell=True, check=check, 
                capture_output=True, text=True
            )
            return result.stdout.strip()
        else:
            subprocess.run(cmd, shell=True, check=check)
            return ""
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {e}")
        if check:
            raise
        return ""

def load_state():
    """Load VPC state from file"""
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    return {"vpcs": {}}

def save_state(state):
    """Save VPC state to file"""
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)

def create_vpc(vpc_name, cidr_block, internet_interface="eth0"):
    """Create a new VPC with specified CIDR block"""
    log(f"Creating VPC: {vpc_name} with CIDR: {cidr_block}")
    
    state = load_state()
    
    # Check if VPC already exists
    if vpc_name in state["vpcs"]:
        log(f"VPC {vpc_name} already exists!")
        return False
    
    # Validate CIDR
    try:
        network = ipaddress.ip_network(cidr_block)
    except ValueError as e:
        log(f"Invalid CIDR block: {e}")
        return False
    
    # Create bridge for the VPC
    bridge_name = f"{vpc_name}-br0"
    # Delete bridge if it already exists (from failed previous run)
    run_command(f"sudo ip link del {bridge_name}", check=False)
    run_command(f"sudo ip link add {bridge_name} type bridge")
    
    # Get the first IP in the network for the bridge
    bridge_ip = str(list(network.hosts())[0])
    run_command(f"sudo ip addr add {bridge_ip}/{network.prefixlen} dev {bridge_name}")
    run_command(f"sudo ip link set {bridge_name} up")
    
    # Enable IP forwarding
    run_command("sudo sysctl -w net.ipv4.ip_forward=1")
    
    # Store VPC configuration
    state["vpcs"][vpc_name] = {
        "cidr": cidr_block,
        "bridge": bridge_name,
        "bridge_ip": bridge_ip,
        "subnets": {},
        "internet_interface": internet_interface
    }
    save_state(state)
    
    log(f"VPC {vpc_name} created successfully with bridge {bridge_name}")
    return True

def add_subnet(vpc_name, subnet_name, subnet_cidr, subnet_type="private"):
    """Add a subnet to an existing VPC"""
    log(f"Adding subnet {subnet_name} ({subnet_cidr}) to VPC {vpc_name}")
    
    state = load_state()
    
    if vpc_name not in state["vpcs"]:
        log(f"VPC {vpc_name} does not exist!")
        return False
    
    vpc = state["vpcs"][vpc_name]
    
    # Check if subnet already exists
    if subnet_name in vpc["subnets"]:
        log(f"Subnet {subnet_name} already exists in VPC {vpc_name}!")
        return False
    
    # Validate subnet CIDR is within VPC CIDR
    vpc_network = ipaddress.ip_network(vpc["cidr"])
    subnet_network = ipaddress.ip_network(subnet_cidr)
    
    if not subnet_network.subnet_of(vpc_network):
        log(f"Subnet {subnet_cidr} is not within VPC CIDR {vpc['cidr']}")
        return False
    
    # Create network namespace for the subnet
    ns_name = f"{vpc_name}-{subnet_name}"
    # Delete namespace if it already exists (from failed previous run)
    run_command(f"sudo ip netns del {ns_name}", check=False)
    run_command(f"sudo ip netns add {ns_name}")
    
    # Create veth pair with short names (Linux interface name limit is 15 chars)
    # Use hash to create unique short names
    name_hash = hashlib.md5(f"{vpc_name}-{subnet_name}".encode()).hexdigest()[:6]
    veth_host = f"veth-h-{name_hash}"  # veth-h-<6chars> = 13 chars
    veth_ns = f"veth-n-{name_hash}"    # veth-n-<6chars> = 13 chars
    # Delete veth pair if it already exists (from failed previous run)
    run_command(f"sudo ip link del {veth_host}", check=False)
    run_command(f"sudo ip link add {veth_host} type veth peer name {veth_ns}")
    
    # Connect host end to bridge
    run_command(f"sudo ip link set {veth_host} master {vpc['bridge']}")
    run_command(f"sudo ip link set {veth_host} up")
    
    # Move namespace end into namespace
    run_command(f"sudo ip link set {veth_ns} netns {ns_name}")
    
    # Configure namespace interface
    subnet_ip = str(list(subnet_network.hosts())[0])
    run_command(f"sudo ip netns exec {ns_name} ip addr add {subnet_ip}/{subnet_network.prefixlen} dev {veth_ns}")
    run_command(f"sudo ip netns exec {ns_name} ip link set {veth_ns} up")
    run_command(f"sudo ip netns exec {ns_name} ip link set lo up")
    
    # Add default route through bridge
    run_command(f"sudo ip netns exec {ns_name} ip route add default via {vpc['bridge_ip']}")
    
    # Configure NAT for public subnets
    if subnet_type == "public":
        log(f"Configuring NAT for public subnet {subnet_name}")
        internet_iface = vpc["internet_interface"]
        
        # Add NAT rule
        run_command(f"sudo iptables -t nat -A POSTROUTING -s {subnet_cidr} -o {internet_iface} -j MASQUERADE", check=False)
        
        # Allow forwarding
        run_command(f"sudo iptables -A FORWARD -i {vpc['bridge']} -o {internet_iface} -j ACCEPT", check=False)
        run_command(f"sudo iptables -A FORWARD -i {internet_iface} -o {vpc['bridge']} -m state --state RELATED,ESTABLISHED -j ACCEPT", check=False)
    
    # Store subnet configuration
    vpc["subnets"][subnet_name] = {
        "cidr": subnet_cidr,
        "type": subnet_type,
        "namespace": ns_name,
        "veth_host": veth_host,
        "veth_ns": veth_ns,
        "ip": subnet_ip
    }
    save_state(state)
    
    log(f"Subnet {subnet_name} added successfully to VPC {vpc_name}")
    return True

def deploy_app(vpc_name, subnet_name, port=8000):
    """Deploy a simple web server in a subnet"""
    log(f"Deploying web server in {vpc_name}/{subnet_name} on port {port}")
    
    state = load_state()
    
    if vpc_name not in state["vpcs"]:
        log(f"VPC {vpc_name} does not exist!")
        return False
    
    vpc = state["vpcs"][vpc_name]
    
    if subnet_name not in vpc["subnets"]:
        log(f"Subnet {subnet_name} does not exist in VPC {vpc_name}!")
        return False
    
    subnet = vpc["subnets"][subnet_name]
    ns_name = subnet["namespace"]
    
    # Create a simple HTML file
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head><title>VPC Demo - {vpc_name}/{subnet_name}</title></head>
    <body>
        <h1>Welcome to {vpc_name}</h1>
        <h2>Subnet: {subnet_name}</h2>
        <p>Type: {subnet['type']}</p>
        <p>CIDR: {subnet['cidr']}</p>
        <p>IP: {subnet['ip']}</p>
    </body>
    </html>
    """
    
    # Create web root directory in namespace
    web_dir = f"/tmp/{ns_name}_web"
    os.makedirs(web_dir, exist_ok=True)
    
    with open(f"{web_dir}/index.html", "w") as f:
        f.write(html_content)
    
    # Start Python HTTP server in namespace (background)
    cmd = f"sudo ip netns exec {ns_name} python3 -m http.server {port} --directory {web_dir} > /tmp/{ns_name}_server.log 2>&1 &"
    run_command(cmd, check=False)
    
    log(f"Web server deployed in {subnet_name} at {subnet['ip']}:{port}")
    log(f"Test with: curl http://{subnet['ip']}:{port}")
    
    return True

def apply_firewall_rules(vpc_name, subnet_name, rules_file):
    """Apply firewall rules to a subnet"""
    log(f"Applying firewall rules to {vpc_name}/{subnet_name}")
    
    state = load_state()
    
    if vpc_name not in state["vpcs"]:
        log(f"VPC {vpc_name} does not exist!")
        return False
    
    vpc = state["vpcs"][vpc_name]
    
    if subnet_name not in vpc["subnets"]:
        log(f"Subnet {subnet_name} does not exist!")
        return False
    
    subnet = vpc["subnets"][subnet_name]
    ns_name = subnet["namespace"]
    
    # Load rules from JSON file
    with open(rules_file, 'r') as f:
        rules = json.load(f)
    
    # Apply ingress rules
    for rule in rules.get("ingress", []):
        port = rule["port"]
        protocol = rule["protocol"]
        action = rule["action"].upper()
        
        if action == "ALLOW":
            iptables_action = "ACCEPT"
        elif action == "DENY":
            iptables_action = "DROP"
        else:
            log(f"Unknown action: {action}")
            continue
        
        cmd = f"sudo ip netns exec {ns_name} iptables -A INPUT -p {protocol} --dport {port} -j {iptables_action}"
        run_command(cmd, check=False)
        log(f"Rule applied: {protocol}/{port} -> {action}")
    
    log(f"Firewall rules applied to {subnet_name}")
    return True

def peer_vpcs(vpc1_name, vpc2_name):
    """Create a peering connection between two VPCs"""
    log(f"Creating peering connection between {vpc1_name} and {vpc2_name}")
    
    state = load_state()
    
    if vpc1_name not in state["vpcs"] or vpc2_name not in state["vpcs"]:
        log("One or both VPCs do not exist!")
        return False
    
    vpc1 = state["vpcs"][vpc1_name]
    vpc2 = state["vpcs"][vpc2_name]
    
    # Create veth pair between bridges with short names (15 char limit)
    # Use hash to create unique short names
    peer_hash = hashlib.md5(f"{vpc1_name}-{vpc2_name}".encode()).hexdigest()[:6]
    veth1 = f"p1-{peer_hash}"  # p1-<6chars> = 9 chars
    veth2 = f"p2-{peer_hash}"  # p2-<6chars> = 9 chars
    
    # Delete veth pair if it already exists (from failed previous run)
    run_command(f"sudo ip link del {veth1}", check=False)
    run_command(f"sudo ip link add {veth1} type veth peer name {veth2}")
    
    # Attach to respective bridges
    run_command(f"sudo ip link set {veth1} master {vpc1['bridge']}")
    run_command(f"sudo ip link set {veth2} master {vpc2['bridge']}")
    
    run_command(f"sudo ip link set {veth1} up")
    run_command(f"sudo ip link set {veth2} up")
    
    # Add routes
    run_command(f"sudo ip route add {vpc2['cidr']} via {vpc2['bridge_ip']} dev {vpc1['bridge']}", check=False)
    run_command(f"sudo ip route add {vpc1['cidr']} via {vpc1['bridge_ip']} dev {vpc2['bridge']}", check=False)
    
    log(f"Peering established between {vpc1_name} and {vpc2_name}")
    return True

def list_vpcs():
    """List all VPCs and their subnets"""
    state = load_state()
    
    if not state["vpcs"]:
        log("No VPCs found")
        return
    
    for vpc_name, vpc in state["vpcs"].items():
        print(f"\n{'='*60}")
        print(f"VPC: {vpc_name}")
        print(f"  CIDR: {vpc['cidr']}")
        print(f"  Bridge: {vpc['bridge']} ({vpc['bridge_ip']})")
        print(f"  Subnets:")
        
        for subnet_name, subnet in vpc["subnets"].items():
            print(f"    - {subnet_name}:")
            print(f"        Type: {subnet['type']}")
            print(f"        CIDR: {subnet['cidr']}")
            print(f"        IP: {subnet['ip']}")
            print(f"        Namespace: {subnet['namespace']}")

def delete_vpc(vpc_name):
    """Delete a VPC and all its resources"""
    log(f"Deleting VPC: {vpc_name}")
    
    state = load_state()
    
    if vpc_name not in state["vpcs"]:
        log(f"VPC {vpc_name} does not exist!")
        return False
    
    vpc = state["vpcs"][vpc_name]
    
    # Delete all subnets
    for subnet_name, subnet in vpc["subnets"].items():
        log(f"Deleting subnet {subnet_name}")
        
        # Delete namespace
        run_command(f"sudo ip netns del {subnet['namespace']}", check=False)
        
        # Remove NAT rules if public subnet
        if subnet["type"] == "public":
            run_command(f"sudo iptables -t nat -D POSTROUTING -s {subnet['cidr']} -o {vpc['internet_interface']} -j MASQUERADE", check=False)
    
    # Delete bridge
    run_command(f"sudo ip link set {vpc['bridge']} down", check=False)
    run_command(f"sudo ip link del {vpc['bridge']}", check=False)
    
    # Remove VPC from state
    del state["vpcs"][vpc_name]
    save_state(state)
    
    log(f"VPC {vpc_name} deleted successfully")
    return True

def cleanup_all():
    """Clean up all VPCs and resources"""
    log("Cleaning up all VPCs...")
    
    state = load_state()
    
    for vpc_name in list(state["vpcs"].keys()):
        delete_vpc(vpc_name)
    
    # Clear state file
    save_state({"vpcs": {}})
    
    log("All VPCs cleaned up")

def main():
    parser = argparse.ArgumentParser(description="VPC Management CLI Tool")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Create VPC
    create_parser = subparsers.add_parser("create-vpc", help="Create a new VPC")
    create_parser.add_argument("name", help="VPC name")
    create_parser.add_argument("cidr", help="CIDR block (e.g., 10.0.0.0/16)")
    create_parser.add_argument("--interface", default="eth0", help="Internet interface")
    
    # Add subnet
    subnet_parser = subparsers.add_parser("add-subnet", help="Add subnet to VPC")
    subnet_parser.add_argument("vpc", help="VPC name")
    subnet_parser.add_argument("name", help="Subnet name")
    subnet_parser.add_argument("cidr", help="Subnet CIDR")
    subnet_parser.add_argument("--type", choices=["public", "private"], default="private")
    
    # Deploy app
    deploy_parser = subparsers.add_parser("deploy-app", help="Deploy web server in subnet")
    deploy_parser.add_argument("vpc", help="VPC name")
    deploy_parser.add_argument("subnet", help="Subnet name")
    deploy_parser.add_argument("--port", type=int, default=8000)
    
    # Apply firewall rules
    firewall_parser = subparsers.add_parser("apply-firewall", help="Apply firewall rules")
    firewall_parser.add_argument("vpc", help="VPC name")
    firewall_parser.add_argument("subnet", help="Subnet name")
    firewall_parser.add_argument("rules", help="Path to rules JSON file")
    
    # Peer VPCs
    peer_parser = subparsers.add_parser("peer-vpcs", help="Peer two VPCs")
    peer_parser.add_argument("vpc1", help="First VPC name")
    peer_parser.add_argument("vpc2", help="Second VPC name")
    
    # List VPCs
    subparsers.add_parser("list", help="List all VPCs")
    
    # Delete VPC
    delete_parser = subparsers.add_parser("delete-vpc", help="Delete a VPC")
    delete_parser.add_argument("name", help="VPC name")
    
    # Cleanup
    subparsers.add_parser("cleanup", help="Clean up all VPCs")
    
    args = parser.parse_args()
    
    # Initialize log file
    open(LOG_FILE, 'a').close()
    
    if args.command == "create-vpc":
        create_vpc(args.name, args.cidr, args.interface)
    elif args.command == "add-subnet":
        add_subnet(args.vpc, args.name, args.cidr, args.type)
    elif args.command == "deploy-app":
        deploy_app(args.vpc, args.subnet, args.port)
    elif args.command == "apply-firewall":
        apply_firewall_rules(args.vpc, args.subnet, args.rules)
    elif args.command == "peer-vpcs":
        peer_vpcs(args.vpc1, args.vpc2)
    elif args.command == "list":
        list_vpcs()
    elif args.command == "delete-vpc":
        delete_vpc(args.name)
    elif args.command == "cleanup":
        cleanup_all()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
