# E2E Tests with Localnet - Quick Start

This is the fastest way to run e2e tests using the local AO network.

## Prerequisites

- Docker installed and running
- `pnpm` installed

## Quick Start (5 steps, ~2 minutes)

### 1. Install dependencies (if not done)

```bash
pnpm install
```

### 2. Start localnet

```bash
pnpm localnet:start
```

This starts all AO services (MU, CU, SU, ArLocal, etc.) in Docker.

### 3. Bootstrap the localnet

```bash
pnpm localnet:bootstrap
```

This:
- Seeds scheduler and AOS module
- Mints 100 AR to your test wallet
- Tracks all transaction IDs

### 4. Get configuration

```bash
pnpm localnet:config
```

Copy the output to your `.env` file. It should look like:

```bash
GRAPHQL_URL=http://localhost:4000/graphql
GATEWAY_URL=http://localhost:4000
CU_URL=http://localhost:4004
MU_URL=http://localhost:4002
SU_URL=http://localhost:4003
SCHEDULER=<scheduler-id-from-output>
MODULE_ID=<module-id-from-output>
```

### 5. Run e2e tests!

```bash
pnpm test:e2e
```

## Why Localnet?

### Speed 🚀
- **Instant message processing** (no network delays)
- **No waiting for block confirmations**
- Tests run **10-100x faster** than testnet

### No Costs 💰
- **Unlimited testing** without AR
- **No rate limits**
- **Offline development**

### Better Debugging 🐛
- **All transaction IDs tracked**
- **Full access to service logs**
- **Inspect state at any time**

## Resetting

If you need to start fresh:

```bash
pnpm localnet:reset      # Clear all data
pnpm localnet:bootstrap  # Fresh bootstrap
pnpm localnet:config     # Get new config
# Update .env with new values
pnpm test:e2e            # Run tests
```

## Troubleshooting

### "Services not running"

```bash
pnpm localnet:start
```

### "Invalid SCHEDULER or MODULE_ID"

```bash
pnpm localnet:config
# Copy new values to .env
```

### "Port already in use"

Stop existing localnet:
```bash
pnpm localnet:stop
# or
docker compose down
```

Then restart:
```bash
pnpm localnet:start
```

### "Docker not running"

Start Docker Desktop, then:
```bash
pnpm localnet:start
```

## What's Different from Testnet?

With localnet, you **don't need**:
- ❌ Force cranking messages
- ❌ Waiting for network propagation
- ❌ GraphQL polling with long timeouts
- ❌ Worrying about AR balance

Everything is **instant** and **local**! ⚡

## Full Documentation

See `LOCALNET_SETUP.md` for complete documentation and advanced configuration.

## Status Check

To see your localnet status:

```bash
# Check services
docker ps

# Check transactions
pnpm localnet:config

# Check marketplace
pnpm intents:list
```

## Example Workflow

```bash
# Day 1: Setup
pnpm localnet:start
pnpm localnet:bootstrap
pnpm localnet:config > .env.local
cp .env.local .env
pnpm test:e2e

# Day 2+: Just run tests
pnpm test:e2e

# Reset if needed
pnpm localnet:reset
pnpm localnet:bootstrap
pnpm localnet:config  # Update .env
pnpm test:e2e
```

That's it! Happy testing! 🎉

