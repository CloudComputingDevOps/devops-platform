#!/usr/bin/env bash
# Despliegue base + blue-green + Ingress en Minikube (VM Ubuntu).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="devops"
SECRETS_DIR="${SECRETS_DIR:-${ROOT_DIR}/secrets/devops}"
if [[ ! -d "${SECRETS_DIR}" && -d "${HOME}/secrets/devops" ]]; then
  SECRETS_DIR="${HOME}/secrets/devops"
fi

echo "==> Namespace"
kubectl apply -f "${ROOT_DIR}/kubernetes/namespace.yaml"

echo "==> Addon Ingress (Minikube)"
minikube addons enable ingress >/dev/null || true

if [[ -d "${SECRETS_DIR}" ]]; then
  echo "==> Secrets desde ${SECRETS_DIR}"
  kubectl create secret generic administrative-data-secrets \
    -n "${NS}" \
    --from-env-file="${SECRETS_DIR}/administrative-data.env" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic users-secrets \
    -n "${NS}" \
    --from-env-file="${SECRETS_DIR}/users.env" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic trajectory-secrets \
    -n "${NS}" \
    --from-env-file="${SECRETS_DIR}/trajectory.env" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "AVISO: no existe ${SECRETS_DIR} ni ~/secrets/devops"
fi

echo "==> NATS"
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ >/dev/null
helm repo update >/dev/null
helm upgrade --install nats nats/nats \
  --namespace "${NS}" \
  -f "${ROOT_DIR}/helm/nats/values.yaml" \
  --wait \
  --timeout 5m

echo "==> Microservicios (blue-green gateway + Ingress)"
kubectl delete deploy gateway -n "${NS}" --ignore-not-found
helm lint "${ROOT_DIR}/helm/microservices"
helm upgrade --install microservices "${ROOT_DIR}/helm/microservices" \
  --namespace "${NS}" \
  --wait \
  --timeout 5m

echo "==> Hosts hint"
MINIKUBE_IP="$(minikube ip)"
echo "Añade a /etc/hosts: ${MINIKUBE_IP} gateway.local"
echo "Prueba: curl -i http://gateway.local/"

kubectl get deploy,svc,ingress -n "${NS}"
bash "${ROOT_DIR}/scripts/blue-green-switch.sh" status || true
