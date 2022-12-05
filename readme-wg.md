
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
