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
### İstio kurulumu : 
``
kubectl create ns istio-system
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
# Base
helm upgrade --install istio-base istio/base -n istio-system
# Control plane
helm upgrade --install istiod istio/istiod -n istio-system 
# (İstersen) Ingress Gateway
helm upgrade --install istio-ingress istio/gateway -n istio-system
``


### 2. Manuel Route Yönetimi
```bash
chmod +x test_run.sh
./test_run.sh
```

Bu script şunları yapar:
- Mevcut APISIX route'larını temizler
- Keycloak discovery endpoint'ini test eder
- OIDC client'ını oluşturur/günceller
- Tüm route'ları yeniden oluşturur

## Konfigürasyon Detayları

### APISIX Route Yapısı

1. **Public Routes** (Priority: 1)
   - `/realms/*`: Keycloak realm bilgileri
   - `/resources/*`: Public resource endpoints

2. **Auth Routes** (Priority: 2)
   - `/auth/*`: Authentication endpoints

3. **Protected Admin Routes** (Priority: 3)
   - `/admin/realms/*/users/*`: Sadece users resource'una erişim
   - OIDC authentication gerektirir

### OIDC Konfigürasyonu

```yaml
discovery: http://keycloak.keycloak.svc.cluster.local:8080/realms/master/.well-known/openid_configuration
client_id: apisix-client
client_secret: [auto-generated]
redirect_uri: http://127.0.0.1:9080/auth/callback
```

## Erişim URL'leri

### Port Forwarding ile Local Erişim
```bash
# APISIX Gateway
kubectl port-forward svc/apisix-gateway -n apisix 9080:80

# APISIX Dashboard
kubectl port-forward svc/apisix-dashboard -n apisix 9000:80

# Keycloak
kubectl port-forward svc/keycloak -n keycloak 8080:80
```

### Test Endpoints
```bash
# Public access
curl http://127.0.0.1:9080/realms/master

# Protected admin access (authentication required)
curl http://127.0.0.1:9080/admin/realms/master/users
```

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

