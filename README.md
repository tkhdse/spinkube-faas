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





# Action Registration and Invocation
```
./register_spinkube.sh bench-actions.json

# verify with the following:
kubectl -n bench get spinapps,deploy,svc
kubectl -n bench get pods -o wide

# deploy -> AVAILABLE
# pods -> Running
# NODE column should show placements across 1805/1811/1812 (with replicas: 3)
```


# Endpoints
Each of these must be run in a separate terminal. We can expose metric/observability endpoints from these endpoints.



```
# Prometheus UI (PromQL): (accessed via http://127.0.0.1:9090)
kubectl -n monitoring port-forward svc/kube-prom-kube-prometheus-prometheus 9090:9090

# to view locally (on another machine):
# ssh -L 9090:127.0.0.1:9090 \
#     -L 9464:127.0.0.1:9464 \
#     user@address
#


# Grafana: (accessed via http://127.0.0.1:3000)
kubectl -n monitoring port-forward svc/kube-prom-grafana 3000:80


# OTel Colelctor Prometheus exporter (raw spanmetrics): 
kubectl -n default port-forward svc/otel-collector-opentelemetry-collector 9464:9464
# verify:
# curl -s http://127.0.0.1:9464/metrics | rg traces_spanmetrics | head
```
