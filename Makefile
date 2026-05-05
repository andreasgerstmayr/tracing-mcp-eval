setup:  # setup KinD cluster and operators
	scripts/setup-cluster.sh

deploy:
	kubectl apply -f manifests

teardown:
	kind delete cluster --name tracing-mcp-eval

generate-otel-demo-manifests:
	helm template opentelemetry-demo open-telemetry/opentelemetry-demo --namespace otel-demo | \
      yq eval-all '(select(.metadata.namespace == null and .kind != "Namespace" and .kind != "ClusterRole" and .kind != "ClusterRoleBinding") | .metadata.namespace) = "otel-demo"' \
      > manifests/otel-demo.orig.yaml

port-forward:
	kubectl port-forward -n otel-demo svc/frontend-proxy 8080:8080 & \
	kubectl port-forward -n obs-mcp svc/obs-mcp 9100:9100 & \
	trap 'kill %1 %2' INT; wait
