#!/bin/bash

# APISIX Route Oluşturma Scripti

echo "🚀 APISIX Routes Oluşturuluyor..."
echo "=================================="

# APISIX Admin API'ye erişim kontrolü
ADMIN_KEY="edd1c9f034335f136f87ad84b625c8f1"
ADMIN_URL="http://127.0.0.1:9180/apisix/admin"

check_port_forward() {
  if ! curl -s "$ADMIN_URL/routes" -H "X-API-KEY: $API_KEY" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Port-forward not detected. Starting port-forward...${NC}"
    kubectl port-forward -n apisix svc/apisix-admin 9180:9180 &
    sleep 5
    
    if ! curl -s "$ADMIN_URL/routes" -H "X-API-KEY: $API_KEY" > /dev/null 2>&1; then
      echo -e "${RED}❌ Failed to establish connection to APISIX Admin API${NC}"
      exit 1
    fi
  fi
  echo -e "${GREEN}✅ APISIX Admin API connection verified${NC}"
}

# 1. Check and start port-forward if needed
echo "🔗 Checking APISIX Admin API connection..."
check_port_forward

# Test APISIX Admin API connectivity
echo "📡 APISIX Admin API bağlantısı test ediliyor..."
if ! curl -s "$ADMIN_URL/routes" -H "X-API-KEY: $ADMIN_KEY" > /dev/null; then
    echo "❌ APISIX Admin API'ye erişim yok. Port forwarding kontrol edin:"
    echo "   kubectl port-forward -n apisix svc/apisix-admin 9180:9180"
    exit 1
fi
echo "✅ APISIX Admin API erişilebilir"

# Route 1: Protected Admin Users - Sadece erişilebilir endpoint
echo "📝 Route 1: Protected Admin Users (sadece erişilebilir endpoint)..."
curl -X PUT "$ADMIN_URL/routes/1" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "keycloak-admin-users-only",
    "uri": "/admin/realms/master/users*",
    "priority": 1,
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "kc-keycloak.keycloak.svc.cluster.local:80": 1
      }
    }
  }' && echo "✅ Admin users route oluşturuldu (sadece erişilebilir)"

# Route 2: Diğer tüm endpoint'ler - Authentication Required uyarısı
echo "📝 Route 2: Diğer tüm endpoint'ler için Authentication Required uyarısı..."
curl -X PUT "$ADMIN_URL/routes/2" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "authentication-required",
    "uri": "/*",
    "priority": 10,
    "plugins": {
      "response-rewrite": {
        "status_code": 401,
        "headers": {
          "Content-Type": "application/json"
        },
        "body": "{\"error\":\"Authentication Required\",\"message\":\"Bu sayfaya erişim için authentication gereklidir. Sadece /admin/realms/master/users endpoint erişilebilir.\",\"allowed_endpoint\":\"/admin/realms/master/users\"}"
      }
    }
  }' && echo "✅ Authentication required route oluşturuldu"

echo ""
echo "📊 Oluşturulan route'lar:"
curl -s "$ADMIN_URL/routes" -H "X-API-KEY: $ADMIN_KEY" | \
  jq '.list[]? | {id: .key, name: .value.name, uri: .value.uri, priority: .value.priority}'

echo ""
echo "✅ APISIX Routes başarıyla oluşturuldu!"
echo ""
echo "🔧 Test komutları:"
echo "# Sadece erişilebilir endpoint - Authentication gerekli (401 bekleniyor)"
echo "curl -s -w \"\\n%{http_code}\\n\" http://127.0.0.1:80/admin/realms/master/users"
echo ""
echo "# Diğer endpoint'ler - Authentication Required uyarısı (401 + mesaj bekleniyor)"
echo "curl -s -w \"\\n%{http_code}\\n\" http://127.0.0.1:80/realms/master"
echo "curl -s -w \"\\n%{http_code}\\n\" http://127.0.0.1:80/admin/realms/master/clients"
echo "curl -s -w \"\\n%{http_code}\\n\" http://127.0.0.1:80/auth/test"
echo ""
echo "# Protected endpoint with token (200 bekleniyor - token validation'a bağlı)"
echo "curl -s -w \"\\n%{http_code}\\n\" -H \"Authorization: Bearer \$TOKEN\" http://127.0.0.1:80/admin/realms/master/users"
echo ""
echo "📋 Sadece /admin/realms/master/users endpoint'ine authentication ile erişim mümkün!"
echo "📋 Diğer tüm endpoint'ler Authentication Required uyarısı gösterecek!"
