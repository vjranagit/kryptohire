#!/bin/bash

API_URL="http://192.168.1.2:3021/api/v1"

echo "Testing tailor endpoint on DEV server (port 3021)..."

# Login
echo "1. Logging in..."
LOGIN_RESPONSE=$(curl -s -X POST "$API_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@admin.com","password":"Admin123"}')

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.access_token // empty')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    echo "❌ Login failed"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi

echo "✅ Login successful"

# Create a base resume
echo -e "\n2. Creating base resume..."
CREATE_RESUME=$(curl -s -X POST "$API_URL/resumes" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
      "name": "Test Base Resume",
      "importOption": "fresh"
    }')

BASE_RESUME_ID=$(echo "$CREATE_RESUME" | jq -r '.data.resume.id // empty')
echo "Base resume ID: $BASE_RESUME_ID"

if [ -z "$BASE_RESUME_ID" ] || [ "$BASE_RESUME_ID" == "null" ]; then
    echo "❌ Failed to create base resume"
    echo "Response: $CREATE_RESUME"
    exit 1
fi

# Create a job
echo -e "\n3. Creating job..."
CREATE_JOB=$(curl -s -X POST "$API_URL/jobs" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
      "company_name": "Test Company",
      "position_title": "Software Engineer",
      "description": "We are looking for a talented software engineer",
      "work_location": "remote",
      "employment_type": "full_time"
    }')

JOB_ID=$(echo "$CREATE_JOB" | jq -r '.data.job.id // empty')
echo "Job ID: $JOB_ID"

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
    echo "❌ Failed to create job"
    echo "Response: $CREATE_JOB"
    exit 1
fi

# Test tailor endpoint
echo -e "\n4. Testing tailor endpoint (this may take 30-60 seconds)..."
TAILOR_START=$(date +%s)
TAILOR_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/resumes/tailor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    --max-time 120 \
    -d "{\"base_resume_id\":\"$BASE_RESUME_ID\",\"job_id\":\"$JOB_ID\"}")

TAILOR_END=$(date +%s)
TAILOR_DURATION=$((TAILOR_END - TAILOR_START))

STATUS_CODE=$(echo "$TAILOR_RESPONSE" | tail -n1)
BODY=$(echo "$TAILOR_RESPONSE" | head -n-1)

echo "Duration: ${TAILOR_DURATION}s"
echo "Status code: $STATUS_CODE"
echo "Response: $BODY" | jq '.' 2>/dev/null || echo "$BODY"

if [ "$STATUS_CODE" == "201" ]; then
    echo -e "\n✅ SUCCESS! Tailor endpoint working!"
else
    echo -e "\n❌ FAILED! Tailor endpoint returned $STATUS_CODE"
fi

# Cleanup
echo -e "\n5. Cleaning up..."
curl -s -X DELETE "$API_URL/resumes/$BASE_RESUME_ID" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -s -X DELETE "$API_URL/jobs/$JOB_ID" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
echo "✅ Cleanup complete"
