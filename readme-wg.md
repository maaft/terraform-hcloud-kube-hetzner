
### 💡 [Do not skip] Creating your kube.tf file

1. Create a project in your [Hetzner Cloud Console](https://console.hetzner.cloud/), and go to **Security > API Tokens** of that project to grab the API key. Take note of the key! ✅
2. Generate a passphrase-less ed25519 SSH key pair for your cluster; take note of the respective paths of your private and public keys. Or, see our detailed [SSH options](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/docs/ssh.md). ✅
3. Prepare the module by copying `kube.tf.example` to `kube.tf` **in a new folder** which you cd into, then replace the values from steps 1 and 2. ✅
4. (Optional) Many variables in `kube.tf` can be customized to suit your needs, you can do so if you want. ✅
5. At this stage you should be in your new folder, with a fresh `kube.tf` file, if it is so, you can proceed forward! ✅

```sh
terraform init --upgrade
terraform validate
terraform apply -auto-approve
```

### Copy kubeconfig from cp node:
```sh
scp -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519 root@<cp-node-ip>:/etc/rancher/k3s/k3s.yaml .
```

### change endpoint ip to `cp-node-ip` in `k3s.yaml`

### test kubernetes connection
```sh
export KUBECONFIG=k3s.yaml
kubectl get nodes
```

install local pv provisioner
```
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml
```

### add bare metal server

Get Agent Config from agent
```sh
cat /etc/rancher/k3s/config.yaml
```

1. install OS
2. `mkdir -p /etc/rancher/k3s`
3. copy agent config to `/etc/rancher/k3s/config.yaml`
4. change `node-ip`to server IP
5. change `node-name` to server name (as seen in `robot.hetzner.com`)
5. install k3s `curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_CHANNEL=stable INSTALL_K3S_EXEC=agent sh -`
6. make sure that firewall rules are not blocking traffic

# Cluster Config

## cert-manager let's encrypt cert issuers

Production (will rate limit if called too often)
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mawe.sprenger@denkweit.de
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: traefik
```

Staging
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
 name: letsencrypt-staging
 namespace: cert-manager
spec:
 acme:
    # The ACME server URL
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: mawe.sprenger@denkweit.de
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-staging
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class:  traefik
```

## Traefik

Configure Namespace
```sh
# create namespace
kubectl create namespace traefik
```

### Dashboard

Enabled dashboard
```terraform
traefik_additional_options = ["--api.dashboard=true"]
```

Generate access secrets
```sh
# generate access credentials
htpasswd -nB admin | tee auth-string

# create secret
kubectl create secret generic -n traefik dashboard-auth-secret --from-file=users=auth-string
```

Create Certificate
```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: traefik-dashboard-cert
  namespace: traefik
spec:
  secretName: traefik-dashboard-cert-secret
  commonName: 'traefik.k3s1.denkweit.ai'
  dnsNames:
    - traefik.k3s1.denkweit.ai
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
```

Deploy ingressroute for dashboard
```yaml
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`traefik.k3s1.denkweit.ai`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))
      services:
        - name: api@internal
          kind: TraefikService
      middlewares:
        - name: traefik-dashboard-auth # Referencing the BasicAuth middleware
          namespace: traefik
  tls:
    secretName: traefik-dashboard-cert-secret
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: traefik-dashboard-auth
  namespace: traefik
spec:
  basicAuth:
    secret: dashboard-auth-secret
```
