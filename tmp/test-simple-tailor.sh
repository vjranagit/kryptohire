#!/bin/bash

API_URL="http://192.168.1.2:3021/api/v1"

# Login
LOGIN=$(curl -s -X POST "$API_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@admin.com","password":"Admin123"}')
TOKEN=$(echo "$LOGIN" | jq -r '.data.access_token')

# Create resume
RESUME=$(curl -s -X POST "$API_URL/resumes" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"name":"Test","importOption":"fresh"}')
RESUME_ID=$(echo "$RESUME" | jq -r '.data.resume.id')

# Create job
JOB=$(curl -s -X POST "$API_URL/jobs" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"company_name":"Test","position_title":"Engineer","description":"Test job"}')
JOB_ID=$(echo "$JOB" | jq -r '.data.job.id')

echo "Resume: $RESUME_ID"
echo "Job: $JOB_ID"
echo ""
echo "Calling tailor with stderr capture..."

# Clear docker logs
docker exec resumelm-app-dev sh -c 'echo "=== TAILOR REQUEST START ===" >&2'

# Make request
RESPONSE=$(curl -s -X POST "$API_URL/resumes/tailor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    --max-time 30 \
    -d "{\"base_resume_id\":\"$RESUME_ID\",\"job_id\":\"$JOB_ID\"}" 2>&1)

docker exec resumelm-app-dev sh -c 'echo "=== TAILOR REQUEST END ===" >&2'

echo "Response:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"

echo ""
echo "Container logs between markers:"
docker logs resumelm-app-dev 2>&1 | sed -n '/=== TAILOR REQUEST START ===/,/=== TAILOR REQUEST END ===/p'

# Cleanup
curl -s -X DELETE "$API_URL/resumes/$RESUME_ID" -H "Authorization: Bearer $TOKEN" > /dev/null
curl -s -X DELETE "$API_URL/jobs/$JOB_ID" -H "Authorization: Bearer $TOKEN" > /dev/null
