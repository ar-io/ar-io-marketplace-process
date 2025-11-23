/**
 * Configuration validator for e2e tests
 */

import { existsSync } from 'fs';
import { resolve } from 'path';

export interface E2EConfig {
  walletPath: string;
  moduleId: string;
  scheduler: string;
  authority: string;
  cuUrl: string;
  muUrl: string;
  suUrl?: string;
  gatewayUrl: string;
  graphqlUrl: string;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  config?: E2EConfig;
}

/**
 * Validate that all required environment variables are present
 */
export function validateE2EConfig(): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  
  // Check required environment variables
  const walletPath = process.env.WALLET_PATH;
  const moduleId = process.env.MODULE_ID || process.env.AOS_MODULE;
  const scheduler = process.env.SCHEDULER;
  const authority = process.env.AUTHORITY;
  const cuUrl = process.env.CU_URL;
  const muUrl = process.env.MU_URL;
  const gatewayUrl = process.env.GATEWAY_URL;
  const graphqlUrl = process.env.GRAPHQL_URL;
  
  if (!walletPath) {
    errors.push('WALLET_PATH environment variable is not set');
  } else if (!existsSync(resolve(process.cwd(), walletPath))) {
    errors.push(`Wallet file not found at: ${walletPath}`);
  }
  
  if (!moduleId) {
    errors.push('MODULE_ID (or AOS_MODULE) environment variable is not set');
  } else if (moduleId.length !== 43) {
    warnings.push(`MODULE_ID length is ${moduleId.length}, expected 43 characters`);
  }
  
  if (!scheduler) {
    errors.push('SCHEDULER environment variable is not set');
  } else if (scheduler.length !== 43) {
    warnings.push(`SCHEDULER length is ${scheduler.length}, expected 43 characters`);
  }
  
  if (!authority) {
    errors.push('AUTHORITY environment variable is not set');
  } else if (authority.length !== 43) {
    warnings.push(`AUTHORITY length is ${authority.length}, expected 43 characters`);
  }
  
  if (!cuUrl) {
    errors.push('CU_URL environment variable is not set');
  } else if (!isValidUrl(cuUrl)) {
    errors.push(`CU_URL is not a valid URL: ${cuUrl}`);
  }
  
  if (!muUrl) {
    errors.push('MU_URL environment variable is not set');
  } else if (!isValidUrl(muUrl)) {
    errors.push(`MU_URL is not a valid URL: ${muUrl}`);
  }
  
  if (!gatewayUrl) {
    errors.push('GATEWAY_URL environment variable is not set');
  } else if (!isValidUrl(gatewayUrl)) {
    errors.push(`GATEWAY_URL is not a valid URL: ${gatewayUrl}`);
  }
  
  if (!graphqlUrl) {
    errors.push('GRAPHQL_URL environment variable is not set');
  } else if (!isValidUrl(graphqlUrl)) {
    errors.push(`GRAPHQL_URL is not a valid URL: ${graphqlUrl}`);
  }
  
  // Check for additional recommended env vars
  if (!process.env.SU_URL) {
    warnings.push('SU_URL environment variable is not set (optional but recommended)');
  }
  
  const valid = errors.length === 0;
  
  if (valid) {
    return {
      valid: true,
      errors: [],
      warnings,
      config: {
        walletPath: walletPath!,
        moduleId: moduleId!,
        scheduler: scheduler!,
        authority: authority!,
        cuUrl: cuUrl!,
        muUrl: muUrl!,
        suUrl: process.env.SU_URL,
        gatewayUrl: gatewayUrl!,
        graphqlUrl: graphqlUrl!,
      },
    };
  }
  
  return {
    valid: false,
    errors,
    warnings,
  };
}

/**
 * Check if a string is a valid URL
 */
function isValidUrl(str: string): boolean {
  try {
    new URL(str);
    return true;
  } catch {
    return false;
  }
}

/**
 * Print validation results
 */
export function printValidationResults(result: ValidationResult): void {
  console.log('📋 E2E Configuration Validation\n');
  
  if (result.errors.length > 0) {
    console.log('❌ Errors:');
    for (const error of result.errors) {
      console.log(`   • ${error}`);
    }
    console.log('');
  }
  
  if (result.warnings.length > 0) {
    console.log('⚠️  Warnings:');
    for (const warning of result.warnings) {
      console.log(`   • ${warning}`);
    }
    console.log('');
  }
  
  if (result.valid) {
    console.log('✅ Configuration is valid!\n');
    
    if (result.config) {
      console.log('Configuration:');
      console.log(`   Wallet:    ${result.config.walletPath}`);
      console.log(`   Module:    ${result.config.moduleId}`);
      console.log(`   Scheduler: ${result.config.scheduler}`);
      console.log(`   Authority: ${result.config.authority}`);
      console.log(`   CU URL:    ${result.config.cuUrl}`);
      console.log(`   MU URL:    ${result.config.muUrl}`);
      console.log(`   Gateway:   ${result.config.gatewayUrl}`);
      console.log(`   GraphQL:   ${result.config.graphqlUrl}`);
      console.log('');
    }
  } else {
    console.log('❌ Configuration is invalid!\n');
  }
}

/**
 * Validate and throw if invalid
 */
export function requireValidConfig(): E2EConfig {
  const result = validateE2EConfig();
  printValidationResults(result);
  
  if (!result.valid) {
    throw new Error('E2E configuration is invalid. Please check your .env file.');
  }
  
  return result.config!;
}

