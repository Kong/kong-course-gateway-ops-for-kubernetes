#!/usr/bin/env bash

# Set alias and download kubeconfig
alias k=kubectl
./setup-k8s.sh

# Install Helm
curl -L -o helm-v3.8.1-linux-amd64.tar.gz https://get.helm.sh/helm-v3.8.1-linux-amd64.tar.gz
tar -xvf ./helm-v3.8.1-linux-amd64.tar.gz
export PATH=$PATH:$HOME/linux-amd64

# Clone Repo
git clone https://github.com/Kong/kong-course-gateway-ops-for-kubernetes.git
cd kong-course-gateway-ops-for-kubernetes

# Create Keys and Certs, Namespace, and Load into K8s
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
kubectl create namespace kong
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong

# Load License
kubectl create secret generic kong-enterprise-license -n kong --from-file=license=/etc/kong/license.json

# Create Manager Config
cat << EOF > admin_gui_session_conf
{
    "cookie_name":"admin_session",
    "cookie_samesite":"off",
    "secret":"kong",
    "cookie_secure":false,
    "storage":"kong"
}
EOF
kubectl create secret generic kong-session-config -n kong --from-file=admin_gui_session_conf

# Add Helm Repo
helm repo add kong https://charts.konghq.com
helm repo update

# Export Hostnames
export MANAGER_HOSTNAME="31112-1-$AVL_DEPLOY_ID.labs.konghq.com"
export ADMIN_HOSTNAME="30001-1-$AVL_DEPLOY_ID.labs.konghq.com"
export DEV_PORTAL_HOSTNAME="30004-1-$AVL_DEPLOY_ID.labs.konghq.com"

# Deploy Kong Control Plane
helm install -f cp-values.yaml kong kong/kong -n kong \
--set admin.ingress.hostname=$ADMIN_HOSTNAME \
--set manager.ingress.hostname=$MANAGER_HOSTNAME \
--set portal.ingress.hostname=$DEV_PORTAL_HOSTNAME

# Point Manager to Dataplane Endpoint
kubectl patch deployment kong-kong -n kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"30001-1-$AVL_DEPLOY_ID.labs.konghq.com\" }]}]}}}}"

# Point Manager to Dataplane Endpoint
kubectl patch deployment kong-kong -n kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"30001-1-$AVL_DEPLOY_ID.labs.konghq.com\" }]}]}}}}"

# Configure Portal Host Name
# kubectl patch deployment kong-kong -n kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_GUI_HOST\", \"value\": \"30004-1-$AVL_DEPLOY_ID.labs.konghq.com\" }]}]}}}}"

# Wait for Kong CP Pods
WAIT_POD=`kubectl get pods --selector=app=kong-kong -n kong -o jsonpath='{.items[*].metadata.name}'`
kubectl wait --for=condition=Ready pod $WAIT_POD -n kong

# Deploy Kong Data Plane
kubectl create namespace kong-dp
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp
kubectl create secret generic kong-enterprise-license -n kong-dp --from-file=license=/etc/kong/license.json
helm install -f dp-minimal.yaml kong-dp kong/kong -n kong-dp

echo "https://$MANAGER_HOSTNAME"