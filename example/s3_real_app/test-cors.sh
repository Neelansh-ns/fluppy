#!/bin/bash

# Test CORS configuration for S3 bucket
# Usage: ./test-cors.sh YOUR_BUCKET_NAME YOUR_REGION

BUCKET_NAME="${1:-your-bucket-name}"
REGION="${2:-us-east-1}"
TEST_FILE="test.txt"

echo "Testing CORS configuration for bucket: $BUCKET_NAME in region: $REGION"
echo "============================================================="
echo ""

# Test 1: OPTIONS preflight for PUT
echo "Test 1: OPTIONS preflight for PUT request"
echo "-----------------------------------------"
curl -v -X OPTIONS \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: PUT" \
  -H "Access-Control-Request-Headers: Content-Type" \
  "https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${TEST_FILE}" \
  2>&1 | grep -i "access-control"

echo ""
echo ""

# Test 2: OPTIONS preflight for POST
echo "Test 2: OPTIONS preflight for POST request"
echo "------------------------------------------"
curl -v -X OPTIONS \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type" \
  "https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${TEST_FILE}" \
  2>&1 | grep -i "access-control"

echo ""
echo ""

# Test 3: Verify exposed headers
echo "Test 3: Check for exposed headers (ETag, Location)"
echo "---------------------------------------------------"
curl -v -X OPTIONS \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: PUT" \
  "https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${TEST_FILE}" \
  2>&1 | grep -i "access-control-expose-headers"

echo ""
echo ""
echo "============================================================="
echo "CORS test complete!"
echo ""
echo "✅ If you see 'Access-Control-Allow-Origin' headers above, CORS is working!"
echo "❌ If no CORS headers appear, check your bucket CORS configuration."
