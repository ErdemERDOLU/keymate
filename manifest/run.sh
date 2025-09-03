# İstio kurulumu : 

kubectl create ns istio-system
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
# Base
helm upgrade --install istio-base istio/base -n istio-system
# Control plane
helm upgrade --install istiod istio/istiod -n istio-system 
# Ingress Gateway
helm upgrade --install istio-ingress istio/gateway -n istio-system 


----- 
#  keycloack kurulumu 
-----
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create namespace keycloak

helm install kc bitnami/keycloak -n keycloak \
  --set auth.adminUser=admin \
  --set auth.adminPassword='Admin#12345' \
  --set postgresql.enabled=true \
  --set postgresql.auth.postgresPassword='Pg#12345'
----

#  Apsix
----

kubectl create ns apisix 
kubectl label namespace apisix istio-injection=enabled --overwrite
helm repo add apisix https://charts.apiseven.com 
helm repo update  
helm upgrade apisix apisix/apisix --namespace apisix \
  --set dashboard.enabled=true \
  --set ingress-controller.enabled=true \
  --set ingress-controller.config.apisix.serviceNamespace=apisix \
  --set ingress-controller.config.apisix.serviceName=apisix-admin \
  --set ingress-controller.config.apisix.servicePort=9180 \
  --set ingress-controller.config.apisix.baseURL="http://apisix-admin.apisix.svc.cluster.local:9180/apisix/admin" \
  --set admin.enabled=true \
  --set admin.allow.ipList={"0.0.0.0/0"} \
  --set admin.credentials.admin=edd1c9f034335f136f87ad84b625c8f1 \
  --set ingress-controller.config.apisix.adminKey=edd1c9f034335f136f87ad84b625c8f1

---
# Istio AuthorizationPolicy uygulamır
echo "Applying Istio Gateway and AuthorizationPolicy..."
kubectl apply -f template/istio-apisix.yaml

# Wait for pods to be ready
kubectl   --for=condition=ready pod -l app=apisix -n apisix --timeout=300s
kubectl   --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s

# APISIX Routes oluştur 
echo "Creating APISIX routes..."
sleep 5  # Pods'ların hazır olması için bekle

# Port forward APISIX admin API
kubectl port-forward -n apisix svc/apisix-admin 9180:9180 &
APISIX_PF_PID=$!
sleep 3

# APISIX route'lar oluşturulur
./create_apisix_routes.sh

echo "✅ Istio AuthorizationPolicy ve APISIX Routes başarıyla uygulandı!"
echo ""
echo "🔧 Test için port forward'ları başlat:"
echo "kubectl port-forward -n keycloak svc/kc-keycloak 8080:80"
echo "kubectl port-forward -n istio-system svc/istio-ingress 80:80"
echo ""
echo "📋 Test komutları:"
echo "# Public endpoint test:"
echo "curl -s -o /dev/null -w \"%{http_code}\" http://127.0.0.1:80/realms/master"
echo ""
echo "# Admin endpoint test (401 beklenir):"
echo "curl -s -o /dev/null -w \"%{http_code}\" http://127.0.0.1:80/admin/realms/master/users"

---

kubectl port-forward -n keycloak svc/kc-keycloak 8081:80 &
---
# Keycloak admin token alınır.
KC_TOKEN=$(curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=Admin#12345" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r .access_token)

# Client
curl -X POST http://localhost:8081/admin/realms/master/clients \
  -H "Authorization: Bearer $KC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "apisix-admin",
    "name": "APISIX Admin Access",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": ["*"],
    "webOrigins": ["*"],
    "serviceAccountsEnabled": true,
    "authorizationServicesEnabled": true,
    "standardFlowEnabled": true,
    "directAccessGrantsEnabled": true
  }'

# Client secret
CLIENT_SECRET=$(curl -s -X GET "http://localhost:8081/admin/realms/master/clients" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[] | select(.clientId=="apisix-admin") | .id')

curl -s -X GET "http://localhost:8081/admin/realms/master/clients/$CLIENT_SECRET/client-secret" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r .value

---

# Port-forward
kubectl port-forward -n apisix svc/apisix-admin 9180:9180 &

# Keycloak service IP

KC_SERVICE_IP=$(kubectl get svc kc-keycloak -n keycloak -o jsonpath='{.spec.clusterIP}')

# Client secret
CLIENT_SECRET="zNbh7IuUnj1Qc7wXXDGgNgB1QZ3Rnh1H"

curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "kc-admin-auth",
    "uri": "/admin/realms/master/users",
    "host": "kc-admin.local",
    "priority": 1,
    "plugins": {
      "openid-connect": {
        "client_id": "apisix-admin",
        "client_secret": "'$CLIENT_SECRET'",
        "discovery": "http://kc-keycloak.keycloak.svc.cluster.local:80/realms/master/.well-known/openid_configuration",
        "scope": "openid profile email",
        "bearer_only": false,
        "realm": "master"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "'kc-keycloak.keycloak.svc.cluster.local':80": 1
      }
    }
  }'

# 2. Fallback Route (Deny All)
curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/2 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "kc-admin-deny",
    "uri": "/*",
    "host": "kc-admin.local",
    "priority": 100,
    "plugins": {
      "response-rewrite": {
        "status_code": 403,
        "body": "{\"error\":\"Access denied. Authentication required.\"}"
      }
    }
  }'


# Route'ları kontrol et
curl -s http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" | jq '.list[] | {name: .value.name, uri: .value.uri, upstream: .value.upstream}'
