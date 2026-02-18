#!/bin/bash

###############################################################################
# Integration Test for ResumeLM Tailor Endpoint
# Diagnoses why /api/v1/resumes/tailor is not responding
###############################################################################

set -o pipefail

# Configuration
API_URL="http://192.168.1.2:3021/api/v1"
CONTAINER_NAME="resumelm-app-dev"
TIMEOUT=60
LOG_FILE="/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/integration-test.log"
ERROR_LOG="/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/integration-test-errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize log files
echo "=== Integration Test Started: $(date) ===" > "$LOG_FILE"
echo "=== Integration Test Errors: $(date) ===" > "$ERROR_LOG"

# Helper functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

section() {
    echo "" | tee -a "$LOG_FILE"
    echo "============================================================" | tee -a "$LOG_FILE"
    echo "  $1" | tee -a "$LOG_FILE"
    echo "============================================================" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    if [ -n "$BASE_RESUME_ID" ]; then
        log "Cleaning up base resume: $BASE_RESUME_ID"
        curl -s -X DELETE "$API_URL/resumes/$BASE_RESUME_ID" \
            -H "Authorization: Bearer $ACCESS_TOKEN" >> "$LOG_FILE" 2>&1
    fi
    if [ -n "$JOB_ID" ]; then
        log "Cleaning up job: $JOB_ID"
        curl -s -X DELETE "$API_URL/jobs/$JOB_ID" \
            -H "Authorization: Bearer $ACCESS_TOKEN" >> "$LOG_FILE" 2>&1
    fi
    if [ -n "$TAILORED_RESUME_ID" ]; then
        log "Cleaning up tailored resume: $TAILORED_RESUME_ID"
        curl -s -X DELETE "$API_URL/resumes/$TAILORED_RESUME_ID" \
            -H "Authorization: Bearer $ACCESS_TOKEN" >> "$LOG_FILE" 2>&1
    fi
}

trap cleanup EXIT

###############################################################################
# STEP 1: Pre-flight checks
###############################################################################
section "STEP 1: Pre-flight Checks"

# Check if container is running
log "Checking if container $CONTAINER_NAME is running..."
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    success "Container $CONTAINER_NAME is running"

    # Show container status
    docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOG_FILE"
else
    error "Container $CONTAINER_NAME is not running"
    docker ps -a --filter "name=$CONTAINER_NAME" | tee -a "$LOG_FILE"
    exit 1
fi

# Check if API is reachable
log "Checking API connectivity..."
if curl -s --max-time 5 "$API_URL/health" > /dev/null 2>&1; then
    success "API is reachable at $API_URL"
else
    warn "Health endpoint not responding (may not exist)"
fi

# Check container logs for recent errors
log "Checking recent container logs..."
docker logs --tail 20 "$CONTAINER_NAME" 2>&1 | tee -a "$LOG_FILE"

###############################################################################
# STEP 2: Authentication
###############################################################################
section "STEP 2: Authentication"

log "Attempting login with admin credentials..."
LOGIN_START=$(date +%s%N)
LOGIN_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}" \
    -X POST "$API_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@admin.com","password":"Admin123"}')

LOGIN_END=$(date +%s%N)
LOGIN_DURATION=$(( (LOGIN_END - LOGIN_START) / 1000000 ))

echo "Login response:" >> "$LOG_FILE"
echo "$LOGIN_RESPONSE" >> "$LOG_FILE"

HTTP_STATUS=$(echo "$LOGIN_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
TIME_TOTAL=$(echo "$LOGIN_RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2)
BODY=$(echo "$LOGIN_RESPONSE" | grep -v "HTTP_STATUS:" | grep -v "TIME_TOTAL:")

log "Login HTTP Status: $HTTP_STATUS"
log "Login Time: ${TIME_TOTAL}s"

ACCESS_TOKEN=$(echo "$BODY" | jq -r '.data.access_token // empty' 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    error "Login failed - no access token received"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    exit 1
fi

success "Login successful - Token obtained (${#ACCESS_TOKEN} chars)"

# Verify token works
log "Verifying token with /auth/me endpoint..."
ME_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X GET "$API_URL/auth/me" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

ME_STATUS=$(echo "$ME_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
ME_BODY=$(echo "$ME_RESPONSE" | grep -v "HTTP_STATUS:")

if [ "$ME_STATUS" == "200" ]; then
    success "Token verified successfully"
    USER_EMAIL=$(echo "$ME_BODY" | jq -r '.data.user.email // empty')
    log "Authenticated as: $USER_EMAIL"
else
    error "Token verification failed (Status: $ME_STATUS)"
    echo "$ME_BODY" | jq '.' 2>/dev/null || echo "$ME_BODY"
fi

###############################################################################
# STEP 3: Create Test Base Resume
###############################################################################
section "STEP 3: Create Test Base Resume"

log "Creating test base resume..."
CREATE_RESUME_START=$(date +%s%N)

RESUME_PAYLOAD='{
  "name": "Integration Test Base Resume",
  "importOption": "fresh",
  "first_name": "John",
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone_number": "+1-555-0123",
  "location": "San Francisco, CA",
  "summary": "Experienced software engineer with 5+ years building scalable web applications.",
  "work_experience": [
    {
      "position": "Senior Software Engineer",
      "company": "Tech Corp",
      "location": "San Francisco, CA",
      "start_date": "2020-01",
      "end_date": "2024-01",
      "description": "Led development of microservices architecture",
      "responsibilities": [
        "Designed and implemented RESTful APIs",
        "Mentored junior developers",
        "Improved system performance by 40%"
      ]
    }
  ],
  "education": [
    {
      "degree": "Bachelor of Science in Computer Science",
      "institution": "Stanford University",
      "location": "Stanford, CA",
      "graduation_date": "2019-06"
    }
  ],
  "skills": [
    {
      "category": "Programming Languages",
      "skills": ["JavaScript", "TypeScript", "Python", "Go"]
    },
    {
      "category": "Frameworks",
      "skills": ["React", "Node.js", "Next.js", "Express"]
    }
  ]
}'

CREATE_RESUME_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}" \
    -X POST "$API_URL/resumes" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$RESUME_PAYLOAD")

CREATE_RESUME_END=$(date +%s%N)
CREATE_RESUME_DURATION=$(( (CREATE_RESUME_END - CREATE_RESUME_START) / 1000000 ))

echo "Create resume response:" >> "$LOG_FILE"
echo "$CREATE_RESUME_RESPONSE" >> "$LOG_FILE"

RESUME_STATUS=$(echo "$CREATE_RESUME_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
RESUME_TIME=$(echo "$CREATE_RESUME_RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2)
RESUME_BODY=$(echo "$CREATE_RESUME_RESPONSE" | grep -v "HTTP_STATUS:" | grep -v "TIME_TOTAL:")

log "Create Resume HTTP Status: $RESUME_STATUS"
log "Create Resume Time: ${RESUME_TIME}s"

BASE_RESUME_ID=$(echo "$RESUME_BODY" | jq -r '.data.resume.id // empty' 2>/dev/null)

if [ -z "$BASE_RESUME_ID" ] || [ "$BASE_RESUME_ID" == "null" ]; then
    error "Failed to create base resume"
    echo "$RESUME_BODY" | jq '.' 2>/dev/null || echo "$RESUME_BODY"
    exit 1
fi

success "Base resume created: $BASE_RESUME_ID"

###############################################################################
# STEP 4: Create Test Job
###############################################################################
section "STEP 4: Create Test Job"

log "Creating test job..."
CREATE_JOB_START=$(date +%s%N)

JOB_PAYLOAD='{
  "company_name": "Innovation Labs",
  "position_title": "Senior Full Stack Engineer",
  "description": "We are seeking a talented Senior Full Stack Engineer to join our growing team. The ideal candidate will have strong experience with React, Node.js, and cloud technologies. You will work on building scalable web applications and microservices. Strong problem-solving skills and ability to work in a fast-paced environment are essential.",
  "work_location": "remote",
  "employment_type": "full_time",
  "requirements": [
    "5+ years of software development experience",
    "Expert in JavaScript/TypeScript",
    "Experience with React and Node.js",
    "Knowledge of cloud platforms (AWS/GCP)",
    "Strong communication skills"
  ],
  "responsibilities": [
    "Design and develop new features",
    "Code review and mentoring",
    "Collaborate with product team",
    "Optimize application performance"
  ]
}'

CREATE_JOB_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}" \
    -X POST "$API_URL/jobs" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$JOB_PAYLOAD")

CREATE_JOB_END=$(date +%s%N)
CREATE_JOB_DURATION=$(( (CREATE_JOB_END - CREATE_JOB_START) / 1000000 ))

echo "Create job response:" >> "$LOG_FILE"
echo "$CREATE_JOB_RESPONSE" >> "$LOG_FILE"

JOB_STATUS=$(echo "$CREATE_JOB_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
JOB_TIME=$(echo "$CREATE_JOB_RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2)
JOB_BODY=$(echo "$CREATE_JOB_RESPONSE" | grep -v "HTTP_STATUS:" | grep -v "TIME_TOTAL:")

log "Create Job HTTP Status: $JOB_STATUS"
log "Create Job Time: ${JOB_TIME}s"

JOB_ID=$(echo "$JOB_BODY" | jq -r '.data.job.id // empty' 2>/dev/null)

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
    error "Failed to create job"
    echo "$JOB_BODY" | jq '.' 2>/dev/null || echo "$JOB_BODY"
    exit 1
fi

success "Job created: $JOB_ID"

###############################################################################
# STEP 5: Test Tailor Endpoint - THE MAIN TEST
###############################################################################
section "STEP 5: Test Tailor Endpoint"

log "Starting tailor endpoint test..."
log "Base Resume ID: $BASE_RESUME_ID"
log "Job ID: $JOB_ID"
log "Timeout: ${TIMEOUT}s"

# Start monitoring docker logs in background
DOCKER_LOG_FILE="/home/vjrana/work/projects/rts-rating/repos/resume-lm/tmp/docker-logs-during-tailor.log"
log "Starting docker log monitoring..."
docker logs -f "$CONTAINER_NAME" > "$DOCKER_LOG_FILE" 2>&1 &
DOCKER_LOG_PID=$!

sleep 1

log "Calling tailor endpoint..."
TAILOR_START=$(date +%s)

TAILOR_PAYLOAD="{
  \"base_resume_id\": \"$BASE_RESUME_ID\",
  \"job_id\": \"$JOB_ID\",
  \"generate_score\": false
}"

# Use timeout command to enforce timeout
TAILOR_RESPONSE=$(timeout ${TIMEOUT} curl -s -w "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}\nTIME_CONNECT:%{time_connect}\nTIME_STARTTRANSFER:%{time_starttransfer}" \
    -X POST "$API_URL/resumes/tailor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$TAILOR_PAYLOAD" 2>&1)

CURL_EXIT_CODE=$?
TAILOR_END=$(date +%s)
TAILOR_DURATION=$((TAILOR_END - TAILOR_START))

# Stop docker log monitoring
kill $DOCKER_LOG_PID 2>/dev/null || true
wait $DOCKER_LOG_PID 2>/dev/null || true

log "Tailor request completed (exit code: $CURL_EXIT_CODE)"
log "Total duration: ${TAILOR_DURATION}s"

echo "" | tee -a "$LOG_FILE"
echo "=== TAILOR RESPONSE ===" | tee -a "$LOG_FILE"
echo "$TAILOR_RESPONSE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check if timeout occurred
if [ $CURL_EXIT_CODE -eq 124 ]; then
    error "TIMEOUT: Tailor endpoint did not respond within ${TIMEOUT}s"
    warn "This indicates the API is likely stuck or processing is taking too long"
elif [ $CURL_EXIT_CODE -ne 0 ]; then
    error "CURL ERROR: Exit code $CURL_EXIT_CODE"
    case $CURL_EXIT_CODE in
        7) warn "Failed to connect to host" ;;
        28) warn "Operation timeout" ;;
        52) warn "Empty reply from server" ;;
        56) warn "Failure in receiving network data" ;;
        *) warn "Unknown curl error" ;;
    esac
else
    # Parse response
    HTTP_STATUS=$(echo "$TAILOR_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
    TIME_TOTAL=$(echo "$TAILOR_RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2)
    TIME_CONNECT=$(echo "$TAILOR_RESPONSE" | grep "TIME_CONNECT:" | cut -d: -f2)
    TIME_STARTTRANSFER=$(echo "$TAILOR_RESPONSE" | grep "TIME_STARTTRANSFER:" | cut -d: -f2)
    BODY=$(echo "$TAILOR_RESPONSE" | grep -v "HTTP_STATUS:" | grep -v "TIME_TOTAL:" | grep -v "TIME_CONNECT:" | grep -v "TIME_STARTTRANSFER:")

    log "HTTP Status: $HTTP_STATUS"
    log "Total Time: ${TIME_TOTAL}s"
    log "Connect Time: ${TIME_CONNECT}s"
    log "Time to First Byte: ${TIME_STARTTRANSFER}s"

    if [ "$HTTP_STATUS" == "201" ]; then
        success "TAILOR ENDPOINT SUCCESSFUL!"
        TAILORED_RESUME_ID=$(echo "$BODY" | jq -r '.data.resume.id // empty' 2>/dev/null)
        log "Tailored Resume ID: $TAILORED_RESUME_ID"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    elif [ "$HTTP_STATUS" == "200" ]; then
        warn "Got 200 instead of 201, but may still be successful"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    elif [ -z "$HTTP_STATUS" ]; then
        error "No HTTP status received - connection may have been closed"
        echo "Response body:"
        echo "$BODY"
    else
        error "TAILOR ENDPOINT FAILED with status $HTTP_STATUS"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    fi
fi

###############################################################################
# STEP 6: Analyze Docker Logs
###############################################################################
section "STEP 6: Docker Log Analysis"

log "Checking docker logs during tailor request..."

if [ -f "$DOCKER_LOG_FILE" ]; then
    LOG_SIZE=$(wc -l < "$DOCKER_LOG_FILE")
    log "Captured $LOG_SIZE lines of docker logs"

    # Check for errors
    ERROR_COUNT=$(grep -i "error" "$DOCKER_LOG_FILE" | wc -l)
    TAILOR_LOG_COUNT=$(grep -i "tailor" "$DOCKER_LOG_FILE" | wc -l)

    log "Found $ERROR_COUNT error lines"
    log "Found $TAILOR_LOG_COUNT tailor-related lines"

    if [ $ERROR_COUNT -gt 0 ]; then
        warn "Errors found in logs:"
        grep -i "error" "$DOCKER_LOG_FILE" | tail -10
    fi

    if [ $TAILOR_LOG_COUNT -gt 0 ]; then
        log "Tailor-related logs:"
        grep -i "tailor" "$DOCKER_LOG_FILE"
    fi

    # Show last 30 lines
    echo "" | tee -a "$LOG_FILE"
    echo "Last 30 lines of docker logs during tailor:" | tee -a "$LOG_FILE"
    tail -30 "$DOCKER_LOG_FILE" | tee -a "$LOG_FILE"
else
    warn "Docker log file not created"
fi

# Check for error log file in container
log "Checking container error log..."
docker exec "$CONTAINER_NAME" cat /app/tmp/tailor-errors.log 2>/dev/null | tee -a "$LOG_FILE" || \
    log "No error log file found in container"

###############################################################################
# STEP 7: Check Container Health
###############################################################################
section "STEP 7: Container Health Check"

log "Checking container resource usage..."
docker stats "$CONTAINER_NAME" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | tee -a "$LOG_FILE"

log "Checking container processes..."
docker exec "$CONTAINER_NAME" ps aux | head -20 | tee -a "$LOG_FILE"

###############################################################################
# STEP 8: Summary
###############################################################################
section "SUMMARY"

echo "Test Results:" | tee -a "$LOG_FILE"
echo "  Authentication: ✅ Success" | tee -a "$LOG_FILE"
echo "  Base Resume Creation: ✅ Success ($BASE_RESUME_ID)" | tee -a "$LOG_FILE"
echo "  Job Creation: ✅ Success ($JOB_ID)" | tee -a "$LOG_FILE"

if [ $CURL_EXIT_CODE -eq 124 ]; then
    echo "  Tailor Endpoint: ❌ TIMEOUT (${TIMEOUT}s)" | tee -a "$LOG_FILE"
elif [ $CURL_EXIT_CODE -eq 0 ] && [ "$HTTP_STATUS" == "201" ]; then
    echo "  Tailor Endpoint: ✅ SUCCESS (${TIME_TOTAL}s)" | tee -a "$LOG_FILE"
else
    echo "  Tailor Endpoint: ❌ FAILED (Status: ${HTTP_STATUS:-N/A}, Duration: ${TAILOR_DURATION}s)" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Log files:" | tee -a "$LOG_FILE"
echo "  Main log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "  Error log: $ERROR_LOG" | tee -a "$LOG_FILE"
echo "  Docker logs: $DOCKER_LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

success "Integration test completed at $(date)"
