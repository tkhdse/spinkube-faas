# spinkube-faas
Spinkube-based platform to benchmark against WarmWhisk.

1a. On control-plane machine:
```
sudo ./k3s-bootstrap.sh server
```

1b. On each worker machine:
```
sudo ./k3s-bootstrap.sh agent --server-url https://<server-ip>:6443 --token '<token-from-server>'
```


1c. Verify on server:
```
sudo k3s kubectl get nodes -o wide
```

2. After setting up appropriate server and worker nodes, depending on the node, run either command:
```
sudo ./setup_server.sh

# OR

sudo ./setup_worker.sh --server-url https://<server-ip>:6443 --token '<token-from-server>'
```

3. Label worker nodes:
```
kubectl label node <worker1> spin=true

# verify:
kubectl get runtimeclass
...
```


4. Install Spin Operator
Next, we need to install the Spin Operator for SpinKube:
```
kubectl apply -f https://github.com/spinframework/spin-operator/releases/download/v0.6.1/spin-operator.crds.yaml

helm upgrade --install spin-operator \
  -n spin-operator --create-namespace \
  --version 0.6.1 --wait \
  oci://ghcr.io/spinframework/charts/spin-operator

kubectl apply -f https://github.com/spinframework/spin-operator/releases/download/v0.6.1/spin-operator.shim-executor.yaml
```

At this point, the cluster creates a serverless platform. Now we need to enable runtime/execution logic. 
