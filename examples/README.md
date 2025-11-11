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
