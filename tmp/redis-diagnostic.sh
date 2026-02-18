#!/bin/bash

echo "========================================="
echo "Redis Connectivity Diagnostic"
echo "========================================="
echo ""

echo "1. Environment Variables:"
echo "   REDIS_URL from container:"
docker exec resumelm-app-dev env | grep REDIS_URL
echo "   USE_LOCAL_REDIS from container:"
docker exec resumelm-app-dev env | grep USE_LOCAL_REDIS
echo ""

echo "2. Container Network Configuration:"
echo "   App container network:"
docker inspect resumelm-app-dev | jq '.[0].NetworkSettings.Networks | keys'
echo ""

echo "3. Redis container status:"
docker ps --filter "name=resumelm-redis-dev" --format "{{.Names}}: {{.Status}}"
echo ""

echo "4. Testing connection from app to Redis:"
echo "   Testing: redis://redis:6379 (current REDIS_URL)"
docker exec resumelm-app-dev sh -c 'timeout 2 sh -c "</dev/tcp/redis/6379" 2>&1' && echo "   ✅ Connected" || echo "   ❌ FAILED - Cannot connect to 'redis' hostname"
echo ""

echo "   Testing: redis://resumelm-redis-dev:6379 (correct hostname)"
docker exec resumelm-app-dev sh -c 'timeout 2 sh -c "</dev/tcp/resumelm-redis-dev/6379" 2>&1' && echo "   ✅ Connected" || echo "   ❌ FAILED"
echo ""

echo "5. DNS Resolution:"
echo "   Can app container resolve 'redis'?"
docker exec resumelm-app-dev sh -c 'getent hosts redis 2>&1' || echo "   ❌ Cannot resolve 'redis'"
echo ""
echo "   Can app container resolve 'resumelm-redis-dev'?"
docker exec resumelm-app-dev sh -c 'getent hosts resumelm-redis-dev 2>&1' || echo "   ❌ Cannot resolve 'resumelm-redis-dev'"
echo ""

echo "========================================="
echo "DIAGNOSIS:"
echo "========================================="
echo "The REDIS_URL in .env.dev is set to 'redis://redis:6379'"
echo "But the actual container name is 'resumelm-redis-dev'"
echo ""
echo "FIX: Update .env.dev REDIS_URL to:"
echo "  REDIS_URL=redis://resumelm-redis-dev:6379"
echo "========================================="
