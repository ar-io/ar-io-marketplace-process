# AO Localnet SDK Integration

## Overview

We've integrated the new `ao-localnet` TypeScript SDK to eliminate the need for `.env` configuration files. All localnet configuration is now accessed programmatically through SDK exports.

## What Changed

### ✅ Removed
- ❌ `.env` file - No longer needed!
- ❌ `dotenv` dependency usage in test files
- ❌ Hardcoded configuration values

### ✅ Added
- ✨ `ao-localnet` SDK imports in `tests/utils/constants.ts`
- ✨ SDK-based configuration exports
- ✨ `scripts/test-sdk-integration.ts` - SDK health check script
- ✨ Docker log access through SDK

## SDK Exports Available

### Configuration
```typescript
import { 
  getUrls,           // Get all service URLs
  getScheduler,      // Get scheduler wallet address  
  getAosModule,      // Get AOS module transaction ID
  getAuthority,      // Get authority (MU) wallet address
  getBootstrapInfo   // Get all bootstrap info at once
} from 'ao-localnet';
```

### AO Connect
```typescript
import { 
  getAoInstance,     // Pre-configured aoconnect instance
  createAoSigner     // Create data item signer for AO wallet
} from 'ao-localnet';
```

### Docker Management
```typescript
import {
  waitForAllServices,      // Wait for services to be healthy
  getHealthStatus,         // Get health status of all services
  getContainerLogs,        // Get container logs
  restartService,          // Restart a service
  isServiceReady           // Check if service is ready
} from 'ao-localnet';
```

## Updated Files

### `tests/utils/constants.ts`
Now exports SDK-based constants:
```typescript
export const ARLOCAL_URL = getUrls().gateway;
export const MU_URL = getUrls().mu;
export const CU_URL = getUrls().cu;
export const SCHEDULER = getScheduler();
export const MODULE_ID = getAosModule();
export const getAuthorityAddress = getAuthority;
export const AO_INSTANCE = getAoInstance();
```

### `tests/utils/process_manager.ts`
Updated to use SDK constants instead of `process.env`:
```typescript
// Before (with .env)
const moduleId = process.env.MODULE_ID;
const scheduler = process.env.SCHEDULER;
const authority = process.env.AUTHORITY;

// After (with SDK)
const moduleId = MODULE_ID;
const scheduler = SCHEDULER;
const authority = await getAuthorityAddress();
const ao = AO_INSTANCE;
```

## Usage in Tests

### Before (with .env)
```typescript
import { config } from 'dotenv';
config();

const ao = connect({
  MU_URL: process.env.MU_URL,
  CU_URL: process.env.CU_URL,
  // ...
});
```

### After (with SDK)
```typescript
import { AO_INSTANCE, SCHEDULER, MODULE_ID, getAuthorityAddress } from './constants.js';

const ao = AO_INSTANCE;
const scheduler = SCHEDULER;
const moduleId = MODULE_ID;
const authority = await getAuthorityAddress();
```

## Testing the SDK

Run the SDK integration test:
```bash
pnpm localnet:test-sdk
```

This will:
1. ✅ Check all services are healthy
2. 📦 Display bootstrap information (scheduler, module, authority)
3. 📡 Show service URLs
4. 📋 Display recent MU container logs

## Benefits

1. **No Configuration Files** - No need to manage `.env` files
2. **Type Safety** - Full TypeScript support with autocomplete
3. **Docker Integration** - Access container logs and health status
4. **Automatic Updates** - Bootstrap info automatically loaded from localnet
5. **Simpler Setup** - Just run `pnpm localnet:start` and `pnpm localnet:seed`

## Docker Log Access

You can now access Docker logs programmatically in tests:

```typescript
import { getContainerLogs } from 'ao-localnet';

// Get last 50 lines from MU
const muLogs = await getContainerLogs('mu', 50);
console.log(muLogs);

// Available services: arlocal, mu, su, cu, scar, bundler, lunar
```

## Service Health Checks

Wait for services before running tests:

```typescript
import { waitForAllServices, getHealthStatus } from 'ao-localnet';

before(async () => {
  const ready = await waitForAllServices(30000); // 30 second timeout
  
  if (!ready) {
    const health = await getHealthStatus();
    console.error('Unhealthy services:', 
      health.filter(h => !h.healthy)
    );
    throw new Error('Services not ready');
  }
});
```

## Migration Checklist

If you need to add SDK support to other test files:

1. ✅ Remove `import { config } from 'dotenv'` and `config()` calls
2. ✅ Import SDK functions from `'ao-localnet'` or use exports from `constants.ts`
3. ✅ Replace `process.env.X` with SDK equivalents
4. ✅ Use `getAuthority()` with `await` (it's async)
5. ✅ Remove `.env` file dependency from documentation

## Next Steps

The SDK provides many more features documented in the [ao-localnet README](../node_modules/ao-localnet/README.md):

- Service management (start/stop/restart)
- Detailed health status
- Service accessibility checks
- Bootstrap persistence
- And more!

---

**Note**: The `ao-localnet` package is linked globally for development. Any changes to it require rebuilding:
```bash
cd /path/to/ao-localnet-archive
pnpm run build
```

