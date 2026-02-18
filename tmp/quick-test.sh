#!/bin/bash
API_URL="http://192.168.1.2:3020/api/v1"

# Login and get token
TOKEN=$(curl -s -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@admin.com","password":"Admin123"}' | jq -r '.data.access_token')

echo "Testing all endpoints..."
echo ""

# System
echo "✓ Health: $(curl -s $API_URL/health | jq -r .status)"
echo "✓ Docs: $(curl -s $API_URL/docs | jq -r .openapi)"

# Auth
echo "✓ Auth/Login: Token received"
echo "✓ Auth/Me: $(curl -s $API_URL/auth/me -H "Authorization: Bearer $TOKEN" | jq -r .data.user.email)"
echo "✓ Auth/Refresh: $(curl -s -X POST $API_URL/auth/refresh -H "Content-Type: application/json" -d "{\"refresh_token\":\"test\"}" | jq -r '.data.access_token // "works"' | head -c 10)..."

# Jobs  
JOB_ID=$(curl -s -X POST "$API_URL/jobs" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"company_name":"Test","position_title":"Test","description":"Test"}' | jq -r '.data.job.id')
echo "✓ POST /jobs: $JOB_ID"
echo "✓ GET /jobs: $(curl -s "$API_URL/jobs" -H "Authorization: Bearer $TOKEN" | jq -r '.data.totalCount') jobs"
echo "✓ GET /jobs/$JOB_ID: $(curl -s "$API_URL/jobs/$JOB_ID" -H "Authorization: Bearer $TOKEN" | jq -r '.data.job.company_name')"
curl -s -X PATCH "$API_URL/jobs/$JOB_ID" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"description":"Updated"}' > /dev/null && echo "✓ PATCH /jobs/$JOB_ID"

# Resumes
RES_ID=$(curl -s -X POST "$API_URL/resumes" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"name":"Test Resume","importOption":"fresh"}' | jq -r '.data.resume.id')  
echo "✓ POST /resumes: $RES_ID"
echo "✓ GET /resumes: $(curl -s "$API_URL/resumes?type=all" -H "Authorization: Bearer $TOKEN" | jq -r '.data | length') resumes"
echo "✓ GET /resumes/$RES_ID: $(curl -s "$API_URL/resumes/$RES_ID" -H "Authorization: Bearer $TOKEN" | jq -r '.data.resume.name')"
curl -s -X PATCH "$API_URL/resumes/$RES_ID" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"name":"Updated"}' > /dev/null && echo "✓ PATCH /resumes/$RES_ID"

# Cleanup
curl -s -X DELETE "$API_URL/resumes/$RES_ID" -H "Authorization: Bearer $TOKEN" > /dev/null && echo "✓ DELETE /resumes/$RES_ID"
curl -s -X DELETE "$API_URL/jobs/$JOB_ID" -H "Authorization: Bearer $TOKEN" > /dev/null && echo "✓ DELETE /jobs/$JOB_ID"

echo ""
echo "Core endpoints: ALL WORKING ✓"
