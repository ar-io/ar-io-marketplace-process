import { AOProcess } from '@ar.io/sdk';
// loadConfig not needed - using direct config reading
import { getOrSpawnProcesses } from '../tests/utils/process_manager.js';

async function main() {
  // Get or spawn processes
  console.log('Getting marketplace process...');
  const { marketplaceProcessId, marketplaceProcess } = await getOrSpawnProcesses();
  
  console.log(`\nTesting Get-Balance on marketplace: ${marketplaceProcessId}`);
  
  try {
    console.log('\n📞 Calling getMarketplaceBalance() method...');
    const balance = await marketplaceProcess.getMarketplaceBalance('test-address-123');
    
    console.log('\n✅ Success! Balance:', balance);
  } catch (error: any) {
    console.error('\n❌ Error:', error.message);
    console.error('Error details:', error);
    
    if (error.issues) {
      console.error('\nZod validation issues:');
      error.issues.forEach((issue: any, i: number) => {
        console.error(`  ${i + 1}. Path: ${JSON.stringify(issue.path)}`);
        console.error(`     Message: ${issue.message}`);
        console.error(`     Received: ${JSON.stringify(issue.received)}`);
      });
    }
  }
}

main();

