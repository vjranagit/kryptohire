#!/bin/bash

API_URL="http://192.168.1.2:3021/api/v1"

echo "Testing tailor endpoint..."

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
echo "Token: ${ACCESS_TOKEN:0:20}..."

# Get user's resumes
echo -e "\n2. Getting user's resumes..."
RESUMES=$(curl -s -X GET "$API_URL/resumes" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

BASE_RESUME_ID=$(echo "$RESUMES" | jq -r '.data[0].id // empty')
echo "Base resume ID: $BASE_RESUME_ID"

# Get user's jobs
echo -e "\n3. Getting user's jobs..."
JOBS=$(curl -s -X GET "$API_URL/jobs" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

JOB_ID=$(echo "$JOBS" | jq -r '.data[0].id // empty')
echo "Job ID: $JOB_ID"

if [ -z "$BASE_RESUME_ID" ] || [ "$BASE_RESUME_ID" == "null" ]; then
    echo "❌ No base resume found"
    exit 1
fi

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
    echo "❌ No job found"
    exit 1
fi

# Test tailor endpoint
echo -e "\n4. Testing tailor endpoint..."
TAILOR_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/resumes/tailor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "{\"base_resume_id\":\"$BASE_RESUME_ID\",\"job_id\":\"$JOB_ID\"}")

STATUS_CODE=$(echo "$TAILOR_RESPONSE" | tail -n1)
BODY=$(echo "$TAILOR_RESPONSE" | head -n-1)

echo "Status code: $STATUS_CODE"
echo "Response: $BODY" | jq '.' 2>/dev/null || echo "$BODY"

if [ "$STATUS_CODE" == "201" ]; then
    echo "✅ Tailor endpoint working!"
else
    echo "❌ Tailor endpoint failed"
fi
