# AO Localnet Setup Guide

This guide explains how to set up and use the local AO network for development and testing.

## Installation

The AO localnet is installed from GitHub:

```json
{
  "dependencies": {
    "ao-localnet": "github:atticusofsparta/ao-localnet-archive"
  }
}
```

This includes our fix for docker-compose YAML version quoting. The package is already installed if you've run `pnpm install`.

## Quick Start

### 1. Start the Localnet

```bash
pnpm localnet:start
```

This will:
- Apply the configuration
- Start Docker containers for ArLocal, MU, CU, SU, and other services

### 2. Bootstrap the Localnet

```bash
pnpm localnet:bootstrap
```

This will:
- Run the standard AO seeding (scheduler, module)
- Mint 100 AR to your test wallet
- Track all transaction IDs in `.ao-localnet.config.json`
- Save bootstrap data for reference

**Alternatively**, you can use the standard seed:
```bash
pnpm localnet:seed  # Standard AO seed (no test wallet minting)
```

### 3. Get the Configuration

After seeding, extract the configuration:

```bash
pnpm localnet:config
```

This will display the scheduler and module IDs published to your localnet.

### 4. Configure Your Environment

Copy the output from `localnet:config` to your `.env` file. Example:

```bash
# AO Localnet URLs
GRAPHQL_URL=http://localhost:4000/graphql
GATEWAY_URL=http://localhost:4000
CU_URL=http://localhost:4004
MU_URL=http://localhost:4002
SU_URL=http://localhost:4003

# Scheduler (from your localnet)
SCHEDULER=PtGrbqY8zhURTfKSvhTSDJ95LXMO6oR2Wk-y1u3ogMs

# AOS Module (from your localnet)
MODULE_ID=Xp8_KWaMewjwvWDZLihmlJwkfKtSHyHUXXe54ilRwWE
```

**Important:** The SCHEDULER and MODULE_ID values are specific to your localnet instance. Always run `pnpm localnet:config` after reseeding to get the correct values.

### 5. Run Tests

```bash
# Integration tests (fast, use LocalAO)
pnpm test:integration

# E2E tests (using the localnet)
pnpm test:e2e
```

## Services and Ports

The localnet exposes the following services:

- **ArLocal** (Arweave Gateway): http://localhost:4000
- **GraphQL**: http://localhost:4000/graphql
- **MU** (Messenger Unit): http://localhost:4002
- **SU** (Scheduler Unit): http://localhost:4003
- **CU** (Compute Unit): http://localhost:4004
- **ScAR** (Block Explorer): http://localhost:4006
- **Bundler**: http://localhost:4007
- **Lunar** (Web UI): http://localhost:4008

## Available Commands

### Lifecycle

- `pnpm localnet:configure` - Generate wallets and download AOS module
- `pnpm localnet:start` - Start the localnet (runs `config:apply` first)
- `pnpm localnet:stop` - Stop the localnet (preserves data)
- `pnpm localnet:seed` - Seed initial data (AR tokens, AOS module)
- `pnpm localnet:bootstrap` - **Recommended**: Seed + mint to test wallet + track TxIDs

### Development

- `pnpm localnet:reset` - Delete all data in the localnet
- `pnpm localnet:reseed` - Reset and re-seed the localnet
- `pnpm localnet:bootstrap` - Custom bootstrap with test wallet minting
- `pnpm localnet:config` - Display config and save to `.localnet-state.json`
- `pnpm localnet:spawn <name>` - Spawn an AOS process
- `pnpm localnet:aos <name>` - Connect to an AOS process

### Transaction Tracking

All seeded transaction IDs are tracked in two places:
1. **`.ao-localnet.config.json`** (in `ao-localnet-archive/`) - Bootstrap section with:
   - Scheduler and Module transaction IDs
   - Test wallet address
   - Minting transaction IDs
   - Last bootstrap timestamp

2. **`.localnet-state.json`** (in your project) - Detailed state with:
   - All transaction IDs categorized by type
   - Current block height
   - Full configuration snapshot

## Benefits of Using Localnet

1. **Fast Development**: No waiting for network propagation or block confirmations
2. **No Testnet Costs**: Unlimited testing without depleting testnet AR
3. **Predictable State**: Full control over the blockchain state
4. **Offline Development**: Work without internet connection
5. **Easy Debugging**: Full access to all service logs

## Troubleshooting

### Services Not Starting

Check if Docker is running:
```bash
docker ps
```

View logs:
```bash
docker compose logs -f
```

### Port Conflicts

If you have port conflicts, you can customize the ports in `.ao-localnet.config.json` (in the ao-localnet-archive directory).

### Data Corruption

Reset the localnet:
```bash
pnpm localnet:reset
pnpm localnet:seed
```

## Switching Between Testnet and Localnet

To switch between testnet and localnet, update the URLs in your `.env` file:

**Testnet:**
```bash
GRAPHQL_URL=https://arweave.net/graphql
GATEWAY_URL=https://arweave.net
CU_URL=https://cu.ardrive.io
MU_URL=https://mu201.ao-testnet.xyz
```

**Localnet:**
```bash
GRAPHQL_URL=http://localhost:4000/graphql
GATEWAY_URL=http://localhost:4000
CU_URL=http://localhost:4004
MU_URL=http://localhost:4002
```

## Advanced: Custom Configuration

See the [ao-localnet CONFIG.md](../ao-localnet-archive/CONFIG.md) for advanced configuration options including:
- Custom ports
- Data storage locations
- Wallet paths
- Service enabling/disabling

