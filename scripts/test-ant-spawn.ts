import { ANT } from '@ar.io/sdk';
import { TEST_SIGNER } from '../tests/utils/constants.js';
import { getAoInstance, getScheduler } from '../tests/utils/constants.js';

async function testAntSpawn() {
  try {
    console.log('🧪 Testing ANT.spawn with SDK...');
    
    const ao = getAoInstance();
    const scheduler = getScheduler();
    
    console.log('✅ Got ao instance and scheduler');
    console.log('✅ Scheduler:', scheduler);
    console.log('✅ Signer type:', typeof TEST_SIGNER);
    
    console.log('\n🚀 Calling ANT.spawn...');
    const result = await ANT.spawn({
      ao,
      signer: TEST_SIGNER,
      scheduler,
    });
    
    console.log('✅ ANT spawned successfully!');
    console.log('   Process ID:', result.processId);
    
  } catch (err: any) {
    console.error('❌ Error:', err.message);
    console.error('Stack:', err.stack);
  }
}

testAntSpawn();

