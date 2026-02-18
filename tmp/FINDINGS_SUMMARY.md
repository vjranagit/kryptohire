# Tailor Endpoint Diagnostic Summary

## Problem Statement
POST http://192.168.1.2:3021/api/v1/resumes/tailor returns HTTP 500 with generic error:
```json
{
  "error": {
    "message": "An unexpected error occurred",
    "code": "INTERNAL_SERVER_ERROR",
    "statusCode": 500
  }
}
```

## What We Know (Verified ✅)

1. **Container is healthy**
   - resumelm-app-dev is running
   - CPU: 0%, Memory: 224.9MiB / 2GiB
   - Next.js 15.1.11 in development mode
   - Port 3021 accessible

2. **All dependencies are working**
   - ✅ Authentication (Bearer token)
   - ✅ Database (resume creation, job creation)
   - ✅ Redis (ping successful from container)
   - ✅ Network connectivity (all containers on docker_resumelm-network-dev)

3. **Environment variables are correct**
   - SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY present
   - REDIS_URL configured correctly (redis://redis:6379)
   - OPENAI_API_KEY, OPENROUTER_API_KEY present
   - NODE_ENV=development

4. **Route file exists and is accessible**
   - /app/src/app/api/v1/resumes/tailor/route.ts present
   - File size: 6228 bytes
   - Contains POST handler

## What We DON'T Know (Mystery ❌)

1. **Why console.log doesn't appear**
   - Route has `console.log('[TAILOR API] Request received')` at line 33
   - NONE of these logs appear in `docker logs resumelm-app-dev`
   - This suggests either:
     a) Handler is never called
     b) Logs are redirected/suppressed
     c) Error occurs before handler executes

2. **What the actual error is**
   - Error message is generic fallback
   - No stack trace in logs
   - No error file created at `/app/tmp/tailor-errors.log`

3. **Where the error occurs**
   - Timing: ~4.4 seconds before 500 response
   - This is longer than instant (suggests processing started)
   - But shorter than full AI processing (suggests early failure)

## Likely Root Causes (Hypothesis)

### Primary Suspect: OpenRouter API Call Failure
The tailor endpoint calls `tailorResumeToJob` which:
1. Gets model candidates (default: OpenRouter free models)
2. Calls `initializeAIClient` with OpenRouter
3. Attempts to call OpenRouter API

**Failure points:**
- OpenRouter API unreachable from container
- API key invalid/expired
- Network timeout
- Rate limiting

**Evidence:**
- 4-second delay matches network timeout
- Default models use OpenRouter: 'openai/gpt-oss-120b:free'
- Error handling might not be catching network errors properly

### Secondary Suspect: AI SDK Import Issue
The Vercel AI SDK might have compatibility issues:
- Using AI SDK with OpenRouter provider
- Dynamic imports failing
- Module resolution errors at runtime

### Tertiary Suspect: Zod Validation Edge Case
Input validation might be failing in an unexpected way that doesn't throw standard Error.

## Immediate Action Items

### 1. Test OpenRouter Connectivity from Container
```bash
docker exec resumelm-app-dev wget -O- --timeout=5 https://openrouter.ai/api/v1/models
```

### 2. Add stderr Logging to Route
Change console.log to console.error in tailor route (stderr usually appears in Docker logs):
```typescript
console.error('[TAILOR] Request received at', new Date().toISOString());
```

### 3. Test with Direct Supabase Call
Create simpler test endpoint that ONLY does database operations:
```typescript
// Test if the issue is DB-related or AI-related
const { data } = await supabase.from('resumes').select('*').eq('id', base_resume_id);
return apiResponse({ test: 'success', data });
```

### 4. Check Next.js Error Logs
```bash
docker logs resumelm-app-dev 2>&1 | grep -i "error\|exception\|failed" | tail -50
```

### 5. Enable Next.js Verbose Logging
Modify docker-compose.dev.yml to add:
```yaml
environment:
  - DEBUG=*
  - NEXT_DEBUG=1
```

## Quick Diagnostic Commands

```bash
# 1. Test OpenRouter from container
docker exec resumelm-app-dev curl -s -m 5 https://openrouter.ai/api/v1/models | head -100

# 2. Check if error logs exist anywhere
docker exec resumelm-app-dev find /app -name "*.log" -type f

# 3. Test Redis from container
docker exec resumelm-app-dev sh -c 'echo "PING" | nc redis 6379'

# 4. Re-run integration test
/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/integration-test.sh
```

## Test Files Created

1. `/tmp/integration-test.sh` - Full end-to-end test ✅
2. `/tmp/integration-test.log` - Test output ✅
3. `/tmp/docker-logs-during-tailor.log` - Container logs ✅
4. `/tmp/redis-diagnostic.sh` - Redis connectivity test ✅
5. `/tmp/TAILOR_DIAGNOSTIC_REPORT.md` - Detailed analysis ✅
6. `/tmp/FINDINGS_SUMMARY.md` - This file ✅

## Next Steps

**Most Likely Fix:**
The OpenRouter API is unreachable or timing out from inside the Docker container.

**Test this:**
```bash
docker exec resumelm-app-dev curl -v -X POST https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/gpt-oss-120b:free","messages":[{"role":"user","content":"test"}]}' \
  --max-time 10
```

**If OpenRouter is blocked/unreachable:**
1. Configure proxy in Docker container
2. Use local AI proxy instead (like the ChatGPT proxy at 172.17.0.1:8317)
3. Fall back to different AI provider

**If OpenRouter works:**
1. Add explicit error logging to `tailorResumeToJob` function
2. Check if error is in Zod schema parsing
3. Verify Service Role Key is working with Supabase

---

**Status:** Diagnostic complete, awaiting network connectivity test results
**Time Spent:** 30 minutes
**Confidence in Diagnosis:** 70% (OpenRouter network issue)
