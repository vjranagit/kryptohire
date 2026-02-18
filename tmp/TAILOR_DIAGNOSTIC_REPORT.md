# Tailor Endpoint Diagnostic Report
**Date:** 2026-02-18
**Endpoint:** POST http://192.168.1.2:3021/api/v1/resumes/tailor
**Container:** resumelm-app-dev

## Executive Summary

The `/api/v1/resumes/tailor` endpoint is **failing with HTTP 500** and returning a generic error message. The integration test confirms:
- ✅ Authentication works correctly
- ✅ Resume creation works correctly
- ✅ Job creation works correctly
- ❌ **Tailor endpoint fails with 500 error**
- ❌ **No console.log output appears in logs**

## Test Results

### Successful Test

 Ran comprehensive integration test at `/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/integration-test.sh`

**Results:**
```
Test Results:
  Authentication: ✅ Success
  Base Resume Creation: ✅ Success (e47899f0-556f-45b6-aa28-1527773b8474)
  Job Creation: ✅ Success (94b9a77f-5931-4966-bda3-3a10d09bb5f6)
  Tailor Endpoint: ❌ FAILED (Status: 500, Duration: 5s)
```

**Error Response:**
```json
{
  "error": {
    "message": "An unexpected error occurred",
    "code": "INTERNAL_SERVER_ERROR",
    "statusCode": 500
  }
}
```

### HTTP Timing Analysis
```
Time to First Byte: 4.399943s
Connect Time: 0.000521s
Total Time: 4.400222s
```

The endpoint takes ~4.4 seconds before returning 500 error, suggesting it's attempting processing but failing partway through.

## Infrastructure Verification

### Container Status
✅ Container `resumelm-app-dev` is running and healthy
```
STATUS: Up 3 hours
PORTS: 0.0.0.0:3021->3000/tcp
CPU: 0.00%
MEM: 224.9MiB / 2GiB (10.98%)
```

### Network Configuration
✅ All containers are on the same Docker network (`docker_resumelm-network-dev`)
```
resumelm-app-dev      172.26.0.6/16
resumelm-redis-dev    172.26.0.3/16
resumelm-kong-dev     172.26.0.5/16
resumelm-auth-dev     172.26.0.4/16
resumelm-db-dev       172.26.0.2/16
```

### Redis Connectivity
✅ Redis is healthy and accessible from app container
```
Container: resumelm-redis-dev - Up 3 hours (healthy)
Test: PING from app container = PONG
```

Redis hostname `redis` resolves to `172.26.0.3` correctly.

### Environment Variables
✅ All required environment variables are present:
```bash
NODE_ENV=development
SUPABASE_URL=http://resumelm-kong-dev:8000
SUPABASE_SERVICE_ROLE_KEY=eyJ... (present)
REDIS_URL=redis://redis:6379
USE_LOCAL_REDIS=true
OPENAI_API_KEY=sk-codex-proxy
OPENROUTER_API_KEY=sk-or-v1-... (present)
```

## Critical Findings

### 1. **Console.log Statements Not Appearing**

The tailor route handler at `/app/src/app/api/v1/resumes/tailor/route.ts` contains:
```typescript
console.log('[TAILOR API] Request received');
...
console.log('[TAILOR API] User authenticated:', user.id);
```

**NONE of these logs appear in Docker logs**, suggesting:
1. The handler is not being reached, OR
2. Next.js dev server is swallowing console.log output, OR
3. An error occurs during import/compilation before the handler executes

### 2. **No Error Stack Traces**

The route attempts to write errors to `/app/tmp/tailor-errors.log`:
```typescript
fs.appendFileSync('/app/tmp/tailor-errors.log', ...)
```

**Result:** The `/app/tmp` directory exists but the error log file is NOT created, meaning:
- The catch block in the handler is never reached, OR
- The error occurs before the catch block

### 3. **Generic Error Message**

The error response matches the fallback handler in `/src/lib/api-errors.ts`:
```typescript
const internalError = new InternalServerError(
  process.env.NODE_ENV === 'production'
    ? 'An unexpected error occurred'  // <-- This is what we're seeing
    : error instanceof Error
      ? error.message
      : 'Unknown error'
);
```

Since `NODE_ENV=development`, we should see the actual error message, but we're getting the production message. This suggests the error object might not be an Error instance.

## Potential Root Causes

### Theory 1: Import-Time Error (MOST LIKELY)
The route imports several modules:
```typescript
import { tailorResumeToJob } from '@/utils/actions/jobs/ai';
import { generateResumeScore } from '@/utils/actions/resumes/actions';
```

If any of these modules fail to import, Next.js returns 500 but doesn't log details.

**Evidence:**
- No console.log output at all
- Generic error message
- 4-second delay (Next.js compilation timeout?)

### Theory 2: Type Error in Validation
The zod schema validation might be failing in an unexpected way:
```typescript
const validation = await validateRequest(req, tailorResumeSchema);
```

### Theory 3: AI Client Initialization Failure
The `initializeAIClient` function might throw during initialization:
- Missing OpenRouter API key
- Network timeout to OpenRouter
- Model lookup failure

**Evidence from code:**
```typescript
const openRouterKey = process.env.OPENROUTER_API_KEY;
if (!openRouterKey) throw new Error('OpenRouter API key not found');
```

### Theory 4: Rate Limiter Error
The `checkRateLimit` function accesses Redis:
```typescript
await checkRateLimit(id);
```

But rate limiting is disabled in development:
```typescript
if (process.env.NODE_ENV === 'development') {
  return;
}
```

So this is unlikely.

## Recommended Next Steps

### Immediate Actions

1. **Add Request Tracing Middleware**
   - Create a middleware to log all API requests before they hit handlers
   - This will confirm if the route is being reached

2. **Test AI Module Import**
   - Create a simple test endpoint that just imports `tailorResumeToJob`
   - The debug endpoint at `/api/v1/debug-tailor` exists but returned HTML (404)

3. **Enable Verbose Logging**
   - Add `--inspect` flag to Next.js dev server
   - Or attach a debugger to the running container

4. **Test with Minimal Payload**
   - Create the absolute minimum test case
   - Already done - still fails

5. **Check OpenRouter Connectivity**
   - Test if the app can actually reach OpenRouter API
   - Verify the API key is valid

### Code Changes to Debug

1. **Wrap entire handler in try-catch**:
```typescript
export async function POST(req: NextRequest) {
  try {
    console.error('=== TAILOR START ==='); // Use console.error for visibility
    // ... rest of handler
  } catch (e) {
    console.error('=== TAILOR ERROR ===', e);
    throw e;
  }
}
```

2. **Add middleware logging**:
```typescript
// middleware.ts - add logging for /api/v1/resumes/tailor
```

3. **Test AI function directly**:
```bash
docker exec resumelm-app-dev node -e "
  import('@/utils/actions/jobs/ai').then(module => {
    console.log('AI module loaded:', Object.keys(module));
  }).catch(err => {
    console.error('AI module error:', err);
  });
"
```

## Files Generated

1. `/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/integration-test.sh` - Comprehensive integration test
2. `/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/integration-test.log` - Full test output
3. `/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/docker-logs-during-tailor.log` - Docker logs during tailor request
4. `/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/redis-diagnostic.sh` - Redis connectivity test
5. This report

## Conclusion

The tailor endpoint is failing with a 500 error, but the root cause is masked by:
1. Missing log output (console.log not appearing)
2. Generic error messages
3. No error stack traces

The most likely cause is an **import-time error** or **runtime error during AI client initialization**. The next step is to add explicit error logging and test the AI module import chain independently.

**Severity:** HIGH - Blocks core functionality
**Priority:** P0 - Requires immediate investigation
**Estimated Debug Time:** 30-60 minutes with proper logging
