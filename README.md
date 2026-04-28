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
