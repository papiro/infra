# Infrastructure Repository

A collection of reusable DevOps constructs, automation tools, and patterns for AWS-based deployments. This repository demonstrates infrastructure as code, configuration management, and deployment automation practices for developers building and managing their own infrastructure.

## The All-In-One (AIO) Architecture

This repository provides a complete solution for deploying multiple web applications on a single EC2 instance. The components work together to create an "All-In-One" server that is optimized for three key concerns:

**Cost Optimization**
- Single EC2 instance hosts multiple applications
- No NAT Gateway, API Gateway, or other expensive managed services
- ARM64 (Graviton) instance types for better price-performance
- Efficient resource utilization with Caddy as a lightweight reverse proxy

**Security**
- Only ports 80 and 443 are exposed to the internet for HTTPS traffic
- SSH access is dynamically granted via `allow-private-ssh.sh` script, which automatically updates security group rules to allow only your current IP address
- Encrypted EBS volumes by default
- Amazon Linux 2023 with regular security updates

**Maintainability**
- Amazon Linux 2023 provides long-term support and automatic security patches
- Infrastructure as Code (CDK) for reproducible deployments
- Ansible roles for consistent server configuration
- Caddy automatically handles HTTPS certificates via Let's Encrypt

The typical deployment flow:
1. **CDK** provisions the EC2 instance, VPC, security groups, and DNS records
2. **Ansible** configures the server with Caddy, CloudWatch monitoring, and application dependencies
3. **Scripts** provide operational tools for secure SSH access and deployment workflows
4. **Caddy** serves as a reverse proxy, routing traffic to multiple applications based on domain names

## Repository Structure

```
infra/
├── cdk/                    # AWS CDK constructs (TypeScript)
├── papiro/                 # Ansible collection for server configuration
├── scripts/                # Standalone automation scripts
└── templates/              # Project templates for database tooling
```

## AWS CDK Constructs

Custom AWS CDK constructs for deploying and managing EC2-based infrastructure with best practices built-in.

### AIOServer Construct

The `AIOServer` construct encapsulates the complete infrastructure needed for a single-instance application server. It provisions a VPC, EC2 instance, security groups, Elastic IP, and necessary IAM roles in a single reusable construct. The key feature is its opinionated design that includes only what's needed for the All-In-One pattern while remaining configurable through props.

**Example Usage:**

```typescript
import { Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { AIOServer } from '@papiro/cdk';
import { PolicyDocument, PolicyStatement, Effect } from 'aws-cdk-lib/aws-iam';

export class MyApplicationStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const server = new AIOServer(this, 'AppServer', {
      keyPairName: 'my-key-pair',
      instanceType: 't4g.small',
      userData: [
        'yum install -y docker',
        'systemctl start docker',
        'systemctl enable docker',
      ],
      inlinePolicies: {
        S3Access: new PolicyDocument({
          statements: [
            new PolicyStatement({
              effect: Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject'],
              resources: ['arn:aws:s3:::my-bucket/*'],
            }),
          ],
        }),
      },
    });

    // Allow custom traffic
    server.securityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(8080),
      'Application traffic'
    );
  }
}
```

### AIOServerRecord Construct

Automatically configures Route53 DNS records for an AIOServer instance, including both apex and www subdomain records.

**Example Usage:**

```typescript
import { AIOServer, AIOServerRecord } from '@papiro/cdk';

const server = new AIOServer(this, 'Server', {
  keyPairName: 'my-key-pair',
});

new AIOServerRecord(this, 'DNS', {
  aioserver: server,
  domain: 'api.example.com',
});
```

### Installation

```bash
npm install @papiro/cdk
```

## Ansible Collection: papiro.infra

A reusable Ansible collection providing roles for server configuration and application deployment. Published as `papiro.infra` following Ansible Galaxy standards.

### Available Roles

#### aio_server

Configures an Amazon Linux 2023 instance with essential web application infrastructure:
- Caddy web server with automatic HTTPS
- Amazon CloudWatch Agent for monitoring
- Standard development tools (git, vim, curl)

**Example Playbook:**

```yaml
---
- hosts: webservers
  become: true
  roles:
    - role: papiro.infra.aio_server
      vars:
        caddy_version: "2.10.2"
        caddy_caddyfile_block: |
          example.com {
            reverse_proxy localhost:3000
          }
```

#### caddy

Installs and configures Caddy server from official releases. Features:
- ARM64 optimized binary installation
- Systemd service configuration
- Automatic HTTPS with Let's Encrypt
- Custom Caddyfile templating

**Variables:**

```yaml
version: "2.10.2"              # Caddy version to install
caddyfile_block: |             # Custom Caddyfile configuration
  mysite.com {
    root * /var/www/html
    file_server
  }
```

#### deploy_github_repo

Securely clones and updates GitHub repositories using credential management.

**Variables:**

```yaml
repo_user: "github-username"
repo_url_path: "username/repository"
repo_path: "/opt/application"
repo_branch: "main"
fine_grained_pat: xxxxxxxxxxxxxxxxxxxx
```

**Example:**

```yaml
- hosts: appservers
  roles:
    - role: papiro.infra.deploy_github_repo
      vars:
        repo_user: "myorg"
        repo_url_path: "myorg/my-app"
        repo_path: "/var/www/app"
        repo_branch: "production"
        fine_grained_pat: xxxxxxxxxxxxxxxxxxxx
```

### Installation

```bash
ansible-galaxy collection install papiro.infra
```

## Standalone Scripts

Bash scripts for common operational tasks.

### allow-private-ssh.sh

Dynamically manages EC2 security group rules to allow SSH access from your current IP address. This script demonstrates advanced AWS CLI usage and security automation.

**Features:**
- Automatic public IP detection using Cloudflare DNS
- EC2 instance lookup by IP address
- Idempotent security group rule management
- Automatic cleanup of stale IP rules

**Usage:**

```bash
./scripts/allow-private-ssh.sh <server-ip-address>
```

**Example:**

```bash
# Allow SSH from current IP to server at 54.123.45.67
./scripts/allow-private-ssh.sh 54.123.45.67
```

**Technical Details:**

The script performs these operations:
1. Detects caller's IPv4 address using `dig` against Cloudflare DNS
2. Locates EC2 instance and associated security group via AWS CLI
3. Queries existing SSH ingress rules on TCP/22
4. Revokes outdated IP rules and authorizes the current IP as /32 CIDR
5. Adds descriptive rule labels for operational clarity

### connect.sh

Streamlined SSH connection wrapper that automatically enables access before connecting.

**Usage:**

```bash
./scripts/connect.sh user@ip-address /path/to/ssh-key.pem
```

**Example:**

```bash
./scripts/connect.sh ec2-user@54.123.45.67 ~/.ssh/my-key.pem
```

This script combines `allow-private-ssh.sh` functionality with SSH connection, providing a single command for secure remote access.

## Templates

The `templates/` directory contains configuration templates for database-related tooling that can be manually copied into projects.

### Database Templates

Located in `templates/database/`:

- **atlas.hcl** - Configuration for [Atlas](https://atlasgo.io/) schema migrations
- **sql-ts.config.json** - Configuration for [sql-ts](https://github.com/rmp135/sql-ts) TypeScript type generation
- **sql-ts.template.hbs** - Handlebars template for customizing TypeScript output

These templates were designed and tested on PostgreSQL and SQLite projects using declarative schema management.

## Prerequisites

### AWS CDK
- Node.js 18+ and npm
- AWS CLI configured with appropriate credentials
- AWS CDK CLI: `npm install -g aws-cdk`

### Ansible
- Python 3.8+
- Ansible 2.15+
- Required collections: `ansible-galaxy collection install community.general`

### Scripts
- Bash 4.0+
- AWS CLI v2
- `dig` command (typically from `bind-utils` or `dnsutils` package)
- SSH client

## Architecture Patterns

This repository demonstrates several infrastructure patterns useful for developers:

- **Infrastructure as Code**: All AWS resources defined declaratively using CDK
- **Immutable Infrastructure**: User data scripts for reproducible instance configuration
- **Configuration Management**: Ansible for idempotent server setup
- **Security Automation**: Dynamic security group rules based on operator IP
- **Single-Instance Deployment**: Cost-effective pattern for development and small applications

## License

MIT-0 (MIT No Attribution) for maximum reusability.

## Author

Pierre Pirault • [pierre.pirault@outlook.com](mailto:pierre.pirault@outlook.com)

