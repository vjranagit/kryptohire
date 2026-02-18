import { NextRequest, NextResponse } from 'next/server';

export async function GET(req: NextRequest) {
  try {
    // Test if we can import the modules
    const { tailorResumeToJob } = await import('@/utils/actions/jobs/ai');
    const { generateResumeScore } = await import('@/utils/actions/resumes/actions');
    
    return NextResponse.json({
      success: true,
      message: 'Modules loaded successfully',
      functions: {
        tailorResumeToJob: typeof tailorResumeToJob,
        generateResumeScore: typeof generateResumeScore
      }
    });
  } catch (error) {
    return NextResponse.json({
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : null
    }, { status: 500 });
  }
}
