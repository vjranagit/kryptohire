import { NextRequest } from 'next/server';
import {
  getAuthenticatedServiceClient,
  apiResponse,
  validateRequest,
  hasValidationData,
} from '@/lib/api-utils';
import { handleAPIError, NotFoundError, ValidationError } from '@/lib/api-errors';
import { generateResumeScore } from '@/utils/actions/resumes/actions';
import { tailorResumeToJob } from '@/utils/actions/jobs/ai';
import { z } from 'zod';
import type { Resume } from '@/lib/types';

// Schema for POST request body
const tailorResumeSchema = z.object({
  base_resume_id: z.string().uuid('Invalid base resume ID'),
  job_id: z.string().uuid('Invalid job ID'),
  config: z
    .object({
      model: z.string().optional(),
      apiKeys: z.array(z.string()).optional(),
      customPrompts: z.any().optional(),
    })
    .optional(),
  generate_score: z.boolean().default(false),
});

/**
 * POST /api/v1/resumes/tailor
 * Create a tailored resume from a base resume for a specific job
 */
export async function POST(req: NextRequest) {
  console.log('[TAILOR API] Request received');
  try {
    // Authenticate request and get service role client
    const { user, supabase } = await getAuthenticatedServiceClient(req);
    console.log('[TAILOR API] User authenticated:', user.id);

    // Validate request body
    const validation = await validateRequest(req, tailorResumeSchema);
    if (!hasValidationData(validation)) {
      return validation.error;
    }

    const { base_resume_id, job_id, config, generate_score } = validation.data;

    // Get user's subscription info to pass to server actions (avoids cookies() call)
    const { data: subscription } = await supabase
      .from('subscriptions')
      .select('subscription_plan, subscription_status, current_period_end, trial_end')
      .eq('user_id', user.id)
      .maybeSingle();

    // Determine effective plan
    const userPlan = subscription?.subscription_plan || 'free';
    console.log('[TAILOR API] User plan:', userPlan);

    // Get base resume directly from DB
    // SECURITY: Filter by user_id to prevent unauthorized access
    const { data: baseResume, error: resumeError } = await supabase
      .from('resumes')
      .select('*')
      .eq('id', base_resume_id)
      .eq('user_id', user.id)
      .single();

    if (resumeError || !baseResume) {
      throw new NotFoundError('Base resume not found');
    }

    // Verify it's a base resume
    if (!baseResume.is_base_resume) {
      throw new ValidationError(
        'Only base resumes can be used as source for tailoring. Please select a base resume.'
      );
    }

    // Get job details directly from DB
    // SECURITY: Filter by user_id to prevent unauthorized access
    const { data: job, error: jobError } = await supabase
      .from('jobs')
      .select('*')
      .eq('id', job_id)
      .eq('user_id', user.id)
      .single();

    if (jobError || !job) {
      throw new NotFoundError('Job not found');
    }

    console.log('[TAILOR API] Starting AI tailoring...');
    // Tailor resume content using AI (pass userId and userPlan to avoid cookies() call)
    const tailoredContent = await tailorResumeToJob(
      baseResume as Resume,
      job as any, // eslint-disable-line @typescript-eslint/no-explicit-any
      config as any, // eslint-disable-line @typescript-eslint/no-explicit-any
      user.id,
      userPlan
    );
    console.log('[TAILOR API] AI tailoring completed');

    // Quota check is bypassed as per the server action
    // await assertResumeQuota(supabase, user.id, 'tailored');

    // Create the tailored resume in database directly
    // SECURITY: user_id is explicitly set to authenticated user
    const newResume = {
      ...tailoredContent,
      user_id: user.id,
      job_id: job_id,
      is_base_resume: false,
      first_name: baseResume.first_name,
      last_name: baseResume.last_name,
      email: baseResume.email,
      phone_number: baseResume.phone_number,
      location: baseResume.location,
      website: baseResume.website,
      linkedin_url: baseResume.linkedin_url,
      github_url: baseResume.github_url,
      document_settings: baseResume.document_settings,
      section_configs: baseResume.section_configs,
      section_order: baseResume.section_order,
      resume_title: `${job.position_title} at ${job.company_name}`,
      name: `${job.position_title} at ${job.company_name}`,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { data: tailoredResume, error: createError } = await supabase
      .from('resumes')
      .insert([newResume])
      .select()
      .single();

    if (createError) {
      console.error('[POST /api/v1/resumes/tailor] Error creating tailored resume:', createError);
      throw new Error('Failed to create tailored resume');
    }

    // Optionally generate score for the tailored resume
    let score = null;
    if (generate_score) {
      try {
        score = await generateResumeScore(
          tailoredResume as Resume,
          job as any, // eslint-disable-line @typescript-eslint/no-explicit-any
          config as any, // eslint-disable-line @typescript-eslint/no-explicit-any
          user.id,
          userPlan
        );
      } catch (scoreError) {
        console.error('Failed to generate score for tailored resume:', scoreError);
        // Don't fail the whole request if scoring fails
      }
    }

    return apiResponse(
      {
        resume: tailoredResume,
        ...(score && { score }),
      },
      201
    );
  } catch (error) {
    console.error('[TAILOR API] Error occurred:', error);
    console.error('[TAILOR API] Error stack:', error instanceof Error ? error.stack : 'No stack');
    console.error('[TAILOR API] Error details:', JSON.stringify(error, Object.getOwnPropertyNames(error)));

    return handleAPIError(error);
  }
}
