# spinkube-faas
Spinkube-based platform to benchmark against WarmWhisk.

On control-plane machine:
```
sudo ./k3s-bootstrap.sh server
```

On each worker machine:
```
sudo ./k3s-bootstrap.sh agent --server-url https://<server-ip>:6443 --token '<token-from-server>'
```


Verify on server:
```
sudo k3s kubectl get nodes -o wide
```

After setting up appropriate server and worker nodes, depending on the node, run either command:
```
sudo ./setup_server.sh

# OR

sudo ./setup_worker.sh --server-url https://<server-ip>:6443 --token '<token-from-server>'
```

