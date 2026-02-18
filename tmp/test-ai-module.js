// Quick test to see if AI module can be imported and called
// Run with: docker exec resumelm-app-dev node /app/tmp/test-ai-module.js

console.log('Starting AI module test...');

async function testAIModule() {
  try {
    console.log('1. Attempting to import AI module...');
    const { tailorResumeToJob } = await import('../src/utils/actions/jobs/ai.ts');
    console.log('✅ AI module imported successfully');
    console.log('   Function type:', typeof tailorResumeToJob);

    // Test minimal data
    const mockResume = {
      id: 'test-id',
      user_id: 'test-user',
      is_base_resume: true,
      name: 'Test Resume',
      first_name: 'John',
      last_name: 'Doe',
      summary: 'Software engineer',
      work_experience: [],
      education: [],
      skills: []
    };

    const mockJob = {
      id: 'test-job',
      user_id: 'test-user',
      company_name: 'TestCo',
      position_title: 'Engineer',
      description: 'Build things'
    };

    const mockUserId = 'test-user';
    const mockUserPlan = 'free';

    console.log('2. Attempting to call tailorResumeToJob...');
    console.log('   This will likely fail with API errors, but we want to see what kind of error');

    const result = await tailorResumeToJob(
      mockResume,
      mockJob,
      undefined, // config
      mockUserId,
      mockUserPlan
    );

    console.log('✅ Tailor function completed (unexpected!)');
    console.log('   Result type:', typeof result);

  } catch (error) {
    console.error('❌ Error during test:');
    console.error('   Message:', error.message);
    console.error('   Name:', error.name);
    console.error('   Stack:', error.stack);

    if (error.cause) {
      console.error('   Cause:', error.cause);
    }
  }
}

testAIModule().then(() => {
  console.log('\nTest complete');
  process.exit(0);
}).catch(err => {
  console.error('\nFatal error:', err);
  process.exit(1);
});
