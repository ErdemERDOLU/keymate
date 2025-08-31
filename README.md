# Keymate - Kubernetes OAuth Gateway System

Bu proje, Google OAuth tokeni ile gelen isteklerin Istio üzerinden yönlendirilmesi, APISIX ile API Gateway yönetimi ve Keycloak Admin API'nin sadece users kaynağına erişim izni veren bir Kubernetes sistemi sağlar.

## Sistem Mimarisi

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client/User   │───▶│  Istio Gateway  │───▶│  APISIX Gateway │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                      ┌─────────────────┐    ┌─────────────────┐
                      │   Keycloak      │◀───│  Authentication │
                      │   (Identity)    │    │   & Routing     │
                      └─────────────────┘    └─────────────────┘
```

## Bileşenler

- **Istio Service Mesh**: Mikroservis trafiği yönetimi ve güvenlik
- **APISIX API Gateway**: API Gateway yönetimi ve yönlendirme
- **Keycloak**: Identity ve Access Management (IAM)
- **PostgreSQL**: Keycloak veritabanı
- **Helm Charts**: Declarative paket yönetimi

## Kurulum Gereksinimleri

### Gerekli Araçlar
```bash
# Kubernetes cluster (minikube önerilir)
minikube start --driver=docker

# Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Helm
curl https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz | tar xz

# jq (JSON parser)
sudo apt-get install jq
```

### Namespace Yapısı
- `istio-system`: Istio bileşenleri
- `keycloak`: Keycloak ve PostgreSQL
- `apisix`: APISIX Gateway ve Controller

## Hızlı Kurulum

### 1. Otomatik Kurulum
```bash
chmod +x run.sh
./run.sh
```

Bu script şunları yapar:
- Tüm namespace'leri oluşturur
- Istio'yu Helm chart ile kurar
- Keycloak'u PostgreSQL ile birlikte deploy eder
- APISIX Gateway'i kurar
- Gerekli route'ları ve OIDC konfigürasyonunu yapar

### 2. Manuel kurulum : 
# İstio kurulumu : 
```
kubectl create ns istio-system
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
# Base
helm upgrade --install istio-base istio/base -n istio-system
# Control plane
helm upgrade --install istiod istio/istiod -n istio-system 
# (İstersen) Ingress Gateway
helm upgrade --install istio-ingress istio/gateway -n istio-system
```
#  keycloack kurulumu 
```
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create namespace keycloak

helm install kc bitnami/keycloak -n keycloak \
  --set auth.adminUser=admin \
  --set auth.adminPassword='Admin#12345' \
  --set postgresql.enabled=true \
  --set postgresql.auth.postgresPassword='Pg#12345'

```
# Apsix Kurulumu: 

```
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
```

#  Template altındaki bütün yaml’lar apply edilir

```
kubectl apply -f template/plugins/
kubectl apply -f template/upstreams/
kubectl apply -f template/
```


## Apisix kurulumu sırasında oluşan configmap’te apsix gateway parametresi çalışmıyor eski versionlarında çalışıyoro laiblir bu yüzden template altında oluşturdugum ApisixRoute ve ApisixPluginConfig kind’ları ingress’e bir şekilde route olamıyor bunun geçmek için curl ile ilgili komutları çalıştırıp manuel bir şekilde ilgili kind’ları ekliyoruz. 


# Port-forward başlat
``` kubectl port-forward -n apisix svc/apisix-admin 9180:9180 & ```

# Keycloak service IP'sini al
``` KC_SERVICE_IP=$(kubectl get svc kc-keycloak -n keycloak -o jsonpath='{.spec.clusterIP}') ```

# Client secret'ı yukarıdan al ve kullan
``` CLIENT_SECRET="zNbh7IuUnj1Qc7wXXDGgNgB1QZ3Rnh1H" ```

```
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
        "discovery": "http://'$KC_SERVICE_IP':8080/realms/master/.well-known/openid_configuration",
        "scope": "openid profile email",
        "bearer_only": false,
        "realm": "master"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "'$KC_SERVICE_IP':8080": 1
      }
    }
  }'
```

# 2. Fallback Route (Deny All)
```
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
```
# Denied:
<img width="975" height="168" alt="image" src="https://github.com/user-attachments/assets/0929a8e4-9b8d-4371-bb94-f4c6d9833a1f" />


# Hata için biraz daha uğraşmam lazım😊 

<img width="975" height="231" alt="image" src="https://github.com/user-attachments/assets/07e2f22b-15be-4df1-bf0a-197ea81536ff" />

### 2. Script ile Manuel Route Yönetimi
```bash
chmod +x test_run.sh
./test_run.sh
```

Bu script şunları yapar:
- Mevcut APISIX route'larını temizler
- Keycloak discovery endpoint'ini test eder
- OIDC client'ını oluşturur/günceller
- Tüm route'ları yeniden oluşturur


## Troubleshooting

### APISIX Controller Sync Issues
```bash
# Controller loglarını kontrol et
kubectl logs -n apisix deployment/apisix-ingress-controller

# Admin API connectivity test
kubectl exec -it -n apisix deployment/apisix-ingress-controller -- curl http://apisix-admin.apisix.svc.cluster.local:9180/apisix/admin/routes
```

### Keycloak Discovery Endpoint Issues
```bash
# Discovery endpoint test
curl http://127.0.0.1:8080/realms/master/.well-known/openid_configuration

# Service DNS resolution test
kubectl exec -it -n apisix deployment/apisix -- nslookup keycloak.keycloak.svc.cluster.local
```

### Route Creation Issues
```bash
# APISIX route listesi
curl http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"

# Route deletion (if needed)
curl -X DELETE http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"
```

## Gelişmiş Konfigürasyon

### Custom OIDC Provider
```bash
# OIDC client secret'ını manuel olarak ayarla
kubectl create secret generic oidc-secret -n apisix --from-literal=client-secret=your-secret
```

### Istio Traffic Management
```yaml
# Custom VirtualService için
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keymate-routing
spec:
  hosts:
  - "*"
  gateways:
  - istio-system/keymate-gateway
  http:
  - route:
    - destination:
        host: apisix-gateway.apisix.svc.cluster.local
```

