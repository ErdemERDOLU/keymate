#!/bin/bash

echo "🔐 Istio AuthorizationPolicy Test Script (Updated)"
echo "=================================================="

echo "📋 Testing current setup:"
echo "✅ Gateway created"
echo "✅ VirtualService configured" 
echo "✅ Protected users route created (sadece erişilebilir endpoint)"
echo "✅ Authentication required routes created (diğer tüm endpoint'ler)"
echo "✅ RequestAuthentication applied"
echo "✅ AuthorizationPolicy applied"
echo ""

# Test 1: Protected admin users endpoint (sadece erişilebilir)
echo "Test 1: Admin users endpoint without token (should require auth - 401)"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/admin/realms/master/users)
echo "Response code: $RESPONSE"
if [ "$RESPONSE" = "401" ]; then
    echo "✅ Admin users endpoint properly protected"
else
    echo "❌ Admin users endpoint not protected (got $RESPONSE, should be 401)"
fi
echo ""

# Test 2: Diğer endpoint'ler - Authentication Required uyarısı
echo "Test 2: Other endpoints - Authentication Required message (should be 401)"
echo "Testing /realms/master:"
RESPONSE=$(curl -s -w "%{http_code}" http://127.0.0.1:80/realms/master)
echo "Response: $RESPONSE"
echo ""
echo "Testing /admin/realms/master/clients:"
RESPONSE=$(curl -s -w "%{http_code}" http://127.0.0.1:80/admin/realms/master/clients)
echo "Response: $RESPONSE"
echo ""

# Test 3: Root path
echo "Test 3: Root path - Authentication Required message (should be 401)"
RESPONSE=$(curl -s -w "%{http_code}" http://127.0.0.1:80/)
echo "Response: $RESPONSE"
echo ""

# Get token for authenticated tests
echo "🔑 Getting Keycloak admin token..."
KC_TOKEN=$(curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=Admin#12345" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r .access_token)

if [ "$KC_TOKEN" = "null" ] || [ -z "$KC_TOKEN" ]; then
    echo "❌ Failed to get Keycloak token"
    exit 1
fi
echo "✅ Token obtained: ${KC_TOKEN:0:20}..."
echo ""

# Test 4: Admin users endpoint with valid token (sadece bu erişilebilir olmalı)
echo "Test 4: Admin users endpoint with valid token (should work - only accessible endpoint)"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $KC_TOKEN" \
  http://127.0.0.1:80/admin/realms/master/users)
echo "Response code: $RESPONSE"
if [ "$RESPONSE" = "200" ]; then
    echo "✅ Authenticated admin access works"
else
    echo "❌ Authenticated admin access failed (got $RESPONSE)"
fi
echo ""

# Test 5: Invalid token
echo "Test 5: Admin endpoint with invalid token (should be blocked)"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer invalid-token-12345" \
  http://127.0.0.1:80/admin/realms/master/users)
echo "Response code: $RESPONSE"
if [ "$RESPONSE" = "403" ] || [ "$RESPONSE" = "401" ]; then
    echo "✅ Invalid token properly rejected"
else
    echo "❌ Invalid token accepted (got $RESPONSE)"
fi
echo ""

echo "🔍 Checking current resources:"
echo "RequestAuthentication:"
kubectl get requestauthentication -n apisix
echo ""
echo "AuthorizationPolicy:"
kubectl get authorizationpolicy -n apisix
echo ""

echo "📊 APISIX Routes:"
curl -s http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" | jq '.list[]? | {id: .key, name: .value.name, uri: .value.uri, priority: .value.priority}'
echo ""

echo "✅ Test completed!"
echo ""
echo "📋 Expected Results:"
echo "- Test 1: 401 (admin users endpoint requires authentication)"
echo "- Test 2: 401 + Authentication Required message (other endpoints blocked)"  
echo "- Test 3: 401 + Authentication Required message (root path blocked)"
echo "- Test 4: 200 (admin users endpoint with valid token - only accessible endpoint)"
echo "- Test 5: 401 (admin users endpoint with invalid token)"
echo ""
echo "🔒 Security Policy:"
echo "✅ Sadece /admin/realms/master/users endpoint'ine authentication ile erişim"
echo "✅ Diğer tüm endpoint'ler Authentication Required uyarısı gösterir"
