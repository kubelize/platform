# Envoy Gateway

Envoy Gateway implementation replacing ingress-nginx with support for internal and external traffic separation.

## Overview

This setup provides:
- **Envoy Gateway** as the API gateway solution
- **Two GatewayClasses**:
  - `internal` - For services accessible only within the internal network
  - `external` - For services accessible from outside the network

## Architecture

```
┌─────────────────────────────────────────────────┐
│             Envoy Gateway System                │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌───────────────┐      ┌───────────────┐      │
│  │   Internal    │      │   External    │      │
│  │ GatewayClass  │      │ GatewayClass  │      │
│  └───────┬───────┘      └───────┬───────┘      │
│          │                      │              │
│  ┌───────▼───────┐      ┌───────▼───────┐      │
│  │   Internal    │      │   External    │      │
│  │   Gateway     │      │   Gateway     │      │
│  │  (Port 80/443)│      │  (Port 80/443)│      │
│  └───────────────┘      └───────────────┘      │
│                                                 │
└─────────────────────────────────────────────────┘
         │                          │
         │ Internal Network         │ External Network
         ▼                          ▼
```

## Usage

### For Internal Services

Create an HTTPRoute that references the `internal` gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-internal-service
  namespace: my-namespace
spec:
  parentRefs:
    - name: internal-gateway
      namespace: envoy-gateway
  hostnames:
    - "internal-app.example.local"
  rules:
    - backendRefs:
        - name: my-service
          port: 8080
```

### For External Services

Create an HTTPRoute that references the `external` gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-external-service
  namespace: my-namespace
spec:
  parentRefs:
    - name: external-gateway
      namespace: envoy-gateway
  hostnames:
    - "api.example.com"
  rules:
    - backendRefs:
        - name: my-service
          port: 8080
```

## TLS/HTTPS Support

Both gateways support TLS termination. You'll need to:

1. Create TLS certificates (using cert-manager):
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: internal-gateway-cert
     namespace: envoy-gateway
   spec:
     secretName: internal-gateway-cert
     issuerRef:
       name: letsencrypt-prod  # or your issuer
       kind: ClusterIssuer
     dnsNames:
       - "*.internal.example.local"
   ```

2. The gateways will automatically use these certificates for HTTPS traffic

## Configuration

### Cilium LoadBalancer IPAM

The gateway classes are configured to use Cilium's LoadBalancer IPAM:
- **Internal**: Uses `io.cilium/lb-ipam-ips` annotation for internal IP ranges
- **External**: Uses `io.cilium/lb-ipam-ips` annotation for external IP ranges

You can either:
1. Specify IP ranges directly in the annotation (e.g., `192.168.0.0/16`)
2. Create dedicated `CiliumLoadBalancerIPPool` resources and reference them
3. Let Cilium automatically assign IPs from available pools

Example IP pool configuration:

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: internal-pool
spec:
  blocks:
    - start: 192.168.1.100
      stop: 192.168.1.120
  serviceSelector:
    matchLabels:
      network-type: internal
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: external-pool
spec:
  blocks:
    - start: 203.0.113.10
      stop: 203.0.113.20
  serviceSelector:
    matchLabels:
      network-type: external
```

Adjust these annotations in the `EnvoyProxy` resources to match your network configuration.

### Replicas

- Internal Gateway: 2 replicas
- External Gateway: 3 replicas

Adjust in the respective `EnvoyProxy` resources as needed.

## Migration from ingress-nginx

To migrate from ingress-nginx:

1. Convert `Ingress` resources to `HTTPRoute` resources
2. Change `ingressClassName` to appropriate gateway `parentRef`
3. Update DNS entries to point to new gateway IPs
4. Test thoroughly before removing ingress-nginx

Example conversion:

**Before (Ingress):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 8080
```

**After (HTTPRoute):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  parentRefs:
    - name: external-gateway
      namespace: envoy-gateway
  hostnames:
    - "app.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-service
          port: 8080
```

## Monitoring

Both gateways are configured with Prometheus scraping annotations:
- Port: 19001
- Endpoint: `/stats/prometheus`

## Resources

- [Envoy Gateway Documentation](https://gateway.envoyproxy.io/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Kubernetes Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)

# DNS Configuration Guide for Envoy Gateway

## Overview

With two separate gateways, you'll have two LoadBalancer IPs:
- **External Gateway**: For internet-facing services (port forwarded from router)
- **Internal Gateway**: For internal-only services (no port forwarding)

## Example Setup

Assuming Cilium assigns these IPs:
- External Gateway: `192.168.1.100`
- Internal Gateway: `192.168.1.101`

## Router Configuration

### Port Forwarding
Keep your existing port forwarding, but update the target:
```
Public IP:80  → 192.168.1.100:80
Public IP:443 → 192.168.1.100:443
```

## DNS Configuration Options

### Option 1: Router DNS (Recommended - Simplest)

If your router supports custom DNS entries (most do):

**External services** (use public DNS as usual):
```
api.yourdomain.com → (public DNS, points to your public IP)
```

**Internal services** (add to router DNS):
```
dashboard.internal.local     → 192.168.1.101
homeassistant.internal.local → 192.168.1.101
prometheus.internal.local    → 192.168.1.101
grafana.internal.local       → 192.168.1.101
```

### Option 2: Pi-hole / AdGuard Home

Add to Local DNS Records:
```
# /etc/pihole/custom.list or AdGuard Home → Filters → DNS rewrites
192.168.1.101 dashboard.internal.local
192.168.1.101 homeassistant.internal.local
192.168.1.101 prometheus.internal.local
192.168.1.101 argocd.internal.local
```

### Option 3: dnsmasq (Advanced)

Create `/etc/dnsmasq.d/internal-gateway.conf`:
```
# Internal gateway entries
address=/dashboard.internal.local/192.168.1.101
address=/homeassistant.internal.local/192.168.1.101
address=/prometheus.internal.local/192.168.1.101

# Or use wildcard for a domain
address=/internal.local/192.168.1.101
```

### Option 4: CoreDNS + external-dns (Automated)

Use external-dns to automatically sync HTTPRoute hostnames to your DNS server:
- See `external-dns/` directory for ArgoCD app configuration
- Automatically creates DNS records from HTTPRoute resources
- Supports multiple providers (CoreDNS, Pi-hole, RFC2136, etc.)

### Option 5: Split Wildcard Approach

Use wildcard DNS subdomains:

**Router/Internal DNS**:
```
*.internal.yourdomain.com → 192.168.1.101
```

**Public DNS**:
```
*.external.yourdomain.com → Your Public IP
```

**HTTPRoute examples**:
```yaml
# Internal service
hostnames:
  - "grafana.internal.yourdomain.com"

# External service  
hostnames:
  - "api.external.yourdomain.com"
```

## Traffic Flow Examples

### External Service (e.g., public API)
```
Mobile App (internet)
  → dns: api.yourdomain.com → Your Public IP: 203.0.113.100
  → Router port forward: 203.0.113.100:443 → 192.168.1.100:443
  → External Gateway (192.168.1.100)
  → HTTPRoute matches hostname
  → Backend service
```

### Internal Service (e.g., home dashboard)
```
Your laptop (home network)
  → dns: dashboard.internal.local → 192.168.1.101
  → Internal Gateway (192.168.1.101) - direct connection
  → HTTPRoute matches hostname
  → Backend service
```

## Verifying Setup

### Check Gateway IPs
```bash
kubectl get svc -n envoy-gateway
```

Look for:
```
NAME                          TYPE           EXTERNAL-IP
envoy-external-gateway        LoadBalancer   192.168.1.100
envoy-internal-gateway        LoadBalancer   192.168.1.101
```

### Test DNS Resolution
```bash
# From internal network
dig dashboard.internal.local
# Should return: 192.168.1.101

# From anywhere
dig api.yourdomain.com
# Should return: Your public IP
```

### Test Connectivity
```bash
# Internal gateway (from internal network)
curl -k https://dashboard.internal.local

# External gateway (from anywhere)
curl https://api.yourdomain.com
```

## Security Considerations

### Internal Gateway
- Only accessible from your internal network (no port forwarding)
- Use this for:
  - Admin dashboards (ArgoCD, Grafana, Prometheus)
  - Home automation interfaces
  - Internal APIs
  - Development/staging services

### External Gateway
- Accessible from internet (via port forwarding)
- Use this for:
  - Public APIs
  - Public websites
  - Services that need external access
- Consider additional security:
  - Rate limiting (via EnvoyProxy config)
  - Authentication (OAuth2, JWT)
  - WAF rules
  - Cert-manager with Let's Encrypt

## Recommended Domain Strategy

### Using a single domain with subdomains:

**External (public DNS)**:
```
api.yourdomain.com
www.yourdomain.com
```

**Internal (local DNS only)**:
```
*.home.yourdomain.com → 192.168.1.101
```

Examples:
- `argocd.home.yourdomain.com` (internal)
- `grafana.home.yourdomain.com` (internal)
- `api.yourdomain.com` (external)

This way:
- Public DNS doesn't know about `*.home.yourdomain.com`
- Your internal DNS resolves `*.home.yourdomain.com` to internal gateway
- External services use regular subdomains via public DNS

## Quick Start

1. **Deploy Envoy Gateway** (already done)
2. **Note the LoadBalancer IPs**:
   ```bash
   kubectl get svc -n envoy-gateway -w
   ```
3. **Update router port forwarding** to external gateway IP
4. **Add internal DNS entries** using one of the options above
5. **Create your first HTTPRoutes** (see README.md for examples)
6. **Test** from both internal network and internet

## Troubleshooting

### Can't reach external services from outside
- Check router port forwarding points to external gateway IP
- Verify public DNS resolves to your public IP
- Check HTTPRoute uses `external-gateway` parent ref

### Can't reach internal services from internal network
- Verify DNS resolves to internal gateway IP (not public IP)
- Check HTTPRoute uses `internal-gateway` parent ref
- Ensure internal gateway has an IP assigned by Cilium

### Services accessible from wrong network
- Verify HTTPRoute has correct `parentRef` (internal vs external)
- Check gateway IP assignments
- Review DNS configuration for hostname

