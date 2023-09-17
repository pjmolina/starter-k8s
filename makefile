
CLUSTER_TYPE="minikube"

.PHONY: separator

# -------------------------------------------------

# Create a cluster, install and configure software
all: start helmfile_lint helmfile_sync enable_audit_log

# Create a cluster
start:
	cd cluster/${CLUSTER_TYPE} && make start
	@@echo "-------------------------------------------------"

# Create a cluster just with Gatekeeper
start_gatekeeper: start install_gatekeeper reinstall_gatekeeper_rules

# Delete a cluster
delete:
	cd cluster/${CLUSTER_TYPE} && make delete

# Follow audit log
audit_log:
	cd cluster/${CLUSTER_TYPE} && make audit_log

# Get kubeconfig for kubectl
kubeconfig: 
	cd cluster/${CLUSTER_TYPE} && make kubeconfig

# -------------------------------------------------

# Sync a set of charts: Prometheus, Grafana, Alertmanager, Gatekeeper, Vault, cert-manager
helmfile_sync:
	cd charts && helmfile sync
	@@echo "-------------------------------------------------"

# Lint charts to be deployed
helmfile_lint: 
	cd charts && helmfile lint
	@@echo "-------------------------------------------------"

# Enable audit log
enable_audit_log:
	cd cluster/${CLUSTER_TYPE} && make enable_audit_log
	@@echo "-------------------------------------------------"

# Deprecated
prepare_secrets:
	@@sed "s/replace_api_key/$$opsgenie_api_key/g" ./charts/prometheus/am-opsgenie.sample.yaml \
		| sed "s/replace_team_id/$$opsgenie_responder_id/g" > ./charts/prometheus/am-opsgenie.yaml
	@@echo "./charts/prometheus/am-opsgenie.yaml generated"

# -------------------------------------------------

# Install gatekeeper
install_gatekeeper:
	helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
	helm upgrade --install  --namespace "gatekeeper" --create-namespace \
		gatekeeper-system gatekeeper/gatekeeper --wait \
		--version "3.13.0"

# Reinstall Gatekeeper constraints and templates
reinstall_gatekeeper_rules:
	@echo "# Linting charts"
	helm lint ./charts/gatekeeper/chart-templates/
	helm lint ./charts/gatekeeper/chart-constraints/
	@echo ""
	@echo "# Removing old charts"
	helm uninstall -n gatekeeper gatekeeper-constraints --wait ||:
	helm uninstall -n gatekeeper gatekeeper-templates --wait ||:
	sleep 1
	@echo ""
	@echo "# Installing charts"
	helm install -n gatekeeper gatekeeper-templates ./charts/gatekeeper/chart-templates/ --wait
	sleep 3
	helm install -n gatekeeper gatekeeper-constraints ./charts/gatekeeper/chart-constraints/

# -------------------------------------------------

# Install Google Microservices Demo
install_demo:
	kubectl create ns tenant ||:
	kubectl apply -n tenant -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml

# Delete Google Microservices Demo
delete_demo:
	kubectl delete -n tenant -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml

# Install Graylog
install_graylog:
	helm repo add kongz https://charts.kong-z.com
	helm upgrade --install  --namespace "graylog" --create-namespace \
		graylog kongz/graylog \
		--set graylog.replicas=1 \
		--set tags.install-mongodb=true \
		--set tags.install-elasticsearch=true \
		--set graylog.elasticsearch.version=7

# Delete Graylog
proxy_graylog:
	@echo "http://localhost:3010"
	@echo "User: admin"
	@PASS=$$(kubectl get secret --namespace graylog graylog -o "jsonpath={.data['graylog-password-secret']}" | base64 --decode) ; \
	echo "Password: $$PASS"
	kubectl -n graylog port-forward svc/graylog-web 3010:9000

# Install ArgoCD
install_argocd:
	kubectl create namespace argocd
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml

# Delete ArgoCD
delete_argocd:
	kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "Delete argocd namespace manually when objects are finalized"

# -------------------------------------------------

# Install Istio
install_istio:
	istioctl install --set profile=demo
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/prometheus.yaml
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/grafana.yaml
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/kiali.yaml
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/extras/zipkin.yaml
	kubectl label ns default istio-injection=enabled

install_istio_demo:
	kubectl apply -f release/kubernetes-manifests.yaml
	kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
	kubectl apply -f https://github.com/GoogleCloudPlatform/microservices-demo/blob/main/release/istio-manifests.yaml
	kubectl delete svc frontend

# -------------------------------------------------

proxy_prometheus:
	# We don't use port 9090 to avoid collision with local installation of Prometheus
	@echo "Navigate to http://localhost:9080"
	kubectl -n promstack port-forward svc/promstack-kube-prometheus-prometheus 9080:9090

proxy_grafana:
	@echo "Navigate to http://localhost:3000"
	@echo "Default user: admin , password: prom-operator"
	kubectl -n promstack port-forward svc/promstack-grafana 3000:80

proxy_alertmanager:
	@echo "Navigate to http://localhost:9093"
	kubectl -n promstack port-forward svc/promstack-kube-prometheus-alertmanager 9093:9093

proxy_robusta:
	@echo "No need to proxy, visit:"
	@echo "https://platform.robusta.dev/"

proxy_argocd:
	@echo "http://localhost:8090"
	@echo "user: admin"
	@echo "pass:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8090:443