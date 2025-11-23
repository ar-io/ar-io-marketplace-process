/**
 * Health check utilities for AO localnet services
 */

export interface ServiceHealth {
  name: string;
  url: string;
  healthy: boolean;
  responseTime?: number;
  error?: string;
}

export interface LocalnetHealth {
  overall: 'healthy' | 'degraded' | 'unhealthy';
  services: ServiceHealth[];
  timestamp: string;
}

/**
 * Check if a service is responding
 */
async function checkService(
  name: string,
  url: string,
  timeout: number = 5000,
): Promise<ServiceHealth> {
  const startTime = Date.now();
  
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);
    
    const response = await fetch(url, {
      signal: controller.signal,
      method: 'GET',
    });
    
    clearTimeout(timeoutId);
    const responseTime = Date.now() - startTime;
    
    return {
      name,
      url,
      healthy: response.ok,
      responseTime,
      error: response.ok ? undefined : `HTTP ${response.status}`,
    };
  } catch (error) {
    const responseTime = Date.now() - startTime;
    return {
      name,
      url,
      healthy: false,
      responseTime,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Check health of all localnet services
 */
export async function checkLocalnetHealth(): Promise<LocalnetHealth> {
  console.log('🔍 Checking localnet health...\n');
  
  const services = [
    { name: 'ArLocal (Gateway)', url: process.env.GATEWAY_URL || 'http://localhost:4000' },
    { name: 'MU (Messenger Unit)', url: process.env.MU_URL || 'http://localhost:4002' },
    { name: 'SU (Scheduler Unit)', url: process.env.SU_URL || 'http://localhost:4003' },
    { name: 'CU (Compute Unit)', url: process.env.CU_URL || 'http://localhost:4004' },
    { name: 'ScAR (Block Explorer)', url: 'http://localhost:4006' },
    { name: 'Bundler', url: 'http://localhost:4007' },
  ];
  
  const healthChecks = await Promise.all(
    services.map(({ name, url }) => checkService(name, url))
  );
  
  // Determine overall health
  const criticalServices = ['ArLocal (Gateway)', 'MU (Messenger Unit)', 'CU (Compute Unit)'];
  const criticalHealthy = healthChecks
    .filter(h => criticalServices.includes(h.name))
    .every(h => h.healthy);
  
  const allHealthy = healthChecks.every(h => h.healthy);
  
  let overall: 'healthy' | 'degraded' | 'unhealthy';
  if (allHealthy) {
    overall = 'healthy';
  } else if (criticalHealthy) {
    overall = 'degraded';
  } else {
    overall = 'unhealthy';
  }
  
  // Print results
  console.log('Service Status:');
  for (const check of healthChecks) {
    const status = check.healthy ? '✅' : '❌';
    const time = check.responseTime ? `(${check.responseTime}ms)` : '';
    const error = check.error ? `- ${check.error}` : '';
    console.log(`  ${status} ${check.name.padEnd(25)} ${time} ${error}`);
  }
  
  console.log(`\nOverall Health: ${overall.toUpperCase()}`);
  
  return {
    overall,
    services: healthChecks,
    timestamp: new Date().toISOString(),
  };
}

/**
 * Wait for localnet to become healthy
 */
export async function waitForHealthy(
  maxAttempts: number = 30,
  interval: number = 2000,
): Promise<void> {
  console.log('\n⏳ Waiting for localnet to become healthy...\n');
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const health = await checkLocalnetHealth();
    
    if (health.overall === 'healthy') {
      console.log('\n✅ Localnet is healthy!\n');
      return;
    }
    
    if (attempt < maxAttempts) {
      console.log(`\nAttempt ${attempt}/${maxAttempts} - Retrying in ${interval / 1000}s...\n`);
      await new Promise(resolve => setTimeout(resolve, interval));
    }
  }
  
  throw new Error('Localnet failed to become healthy within the timeout period');
}

/**
 * Check if GraphQL endpoint is accessible and responsive
 */
export async function checkGraphQLHealth(): Promise<ServiceHealth> {
  const url = process.env.GRAPHQL_URL || 'http://localhost:4000/graphql';
  
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        query: '{ transactions(first: 1) { edges { node { id } } } }',
      }),
    });
    
    const result = await response.json();
    const healthy = response.ok && !result.errors;
    
    return {
      name: 'GraphQL',
      url,
      healthy,
      error: result.errors ? result.errors[0]?.message : undefined,
    };
  } catch (error) {
    return {
      name: 'GraphQL',
      url,
      healthy: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

