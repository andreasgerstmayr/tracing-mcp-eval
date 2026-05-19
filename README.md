# Quickstart
```
make setup
make deploy
make forward
```

# Access services
```
kubectl --namespace otel-demo port-forward svc/frontend-proxy 8080:8080
```

* Web store:             http://localhost:8080/
* Grafana:               http://localhost:8080/grafana/
* Load Generator UI:     http://localhost:8080/loadgen/
* Jaeger UI:             http://localhost:8080/jaeger/ui/
* Flagd configurator UI: http://localhost:8080/feature
