#!/bin/bash

API_URL="http://192.168.1.2:3021/api/v1"

echo "1. Login..."
LOGIN_RESPONSE=$(curl -s -X POST "$API_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@admin.com","password":"Admin123"}')

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Login failed"
    exit 1
fi

echo "✅ Logged in"

echo -e "\n2. Create minimal resume..."
RESUME=$(curl -s -X POST "$API_URL/resumes" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
      "name": "Test Resume",
      "importOption": "fresh",
      "first_name": "John",
      "last_name": "Doe",
      "summary": "Software engineer with experience."
    }')

RESUME_ID=$(echo "$RESUME" | jq -r '.data.resume.id // empty')
echo "Resume ID: $RESUME_ID"

echo -e "\n3. Create minimal job..."
JOB=$(curl -s -X POST "$API_URL/jobs" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
      "company_name": "TestCo",
      "position_title": "Engineer",
      "description": "Build software"
    }')

JOB_ID=$(echo "$JOB" | jq -r '.data.job.id // empty')
echo "Job ID: $JOB_ID"

echo -e "\n4. Call tailor endpoint with verbose output..."

# Start following logs in background
echo "Starting log follow..."
docker logs -f resumelm-app-dev > /tmp/tailor-live-logs.txt 2>&1 &
LOG_PID=$!
sleep 1

# Call the endpoint
echo "Calling tailor..."
TAILOR_RESPONSE=$(curl -v -X POST "$API_URL/resumes/tailor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    --max-time 30 \
    -d "{\"base_resume_id\":\"$RESUME_ID\",\"job_id\":\"$JOB_ID\"}" 2>&1)

# Stop log following
sleep 2
kill $LOG_PID 2>/dev/null

echo -e "\n=== CURL VERBOSE OUTPUT ==="
echo "$TAILOR_RESPONSE"

echo -e "\n=== DOCKER LOGS DURING REQUEST ==="
tail -50 /tmp/tailor-live-logs.txt

echo -e "\n=== CHECKING FOR LOGS IN CONTAINER ==="
docker exec resumelm-app-dev ls -la /app/tmp/ 2>/dev/null || echo "No /app/tmp directory"
docker exec resumelm-app-dev cat /app/tmp/tailor-errors.log 2>/dev/null || echo "No error log file"

echo -e "\n=== CLEANUP ==="
curl -s -X DELETE "$API_URL/resumes/$RESUME_ID" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -s -X DELETE "$API_URL/jobs/$JOB_ID" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
echo "Done"
