#!/usr/bin/env bash
# Instala Prometheus + Grafana + Alertmanager + Pushgateway (R1.4, R1.5 y R1.6),
# el exportador de metricas del pipeline y el dashboard de Grafana.
# Se puede ejecutar varias veces.
#
# Opcional: export GITHUB_TOKEN=ghp_xxx antes de ejecutarlo (ver monitoring/README.md).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS_MONITORING="monitoring"
SECRETS_DIR="${SECRETS_DIR:-${ROOT_DIR}/secrets/devops}"
ALERT_ENV="${SECRETS_DIR}/alertmanager.env"
EMAIL_TPL="${ROOT_DIR}/monitoring/kube-prometheus-stack/values-email.yaml.tpl"
EMAIL_GEN="${ROOT_DIR}/monitoring/kube-prometheus-stack/values-email.generated.yaml"

echo "==> Namespace + webhook + pushgateway"
kubectl apply -f "${ROOT_DIR}/monitoring/alertmanager-webhook/deployment.yaml"
kubectl apply -f "${ROOT_DIR}/monitoring/pushgateway/deployment.yaml"
kubectl rollout status deployment/alertmanager-webhook -n "${NS_MONITORING}" --timeout=120s
kubectl rollout status deployment/pushgateway -n "${NS_MONITORING}" --timeout=120s

HELM_EXTRA=()
if [[ -f "${ALERT_ENV}" ]]; then
  echo "==> Generando config SMTP email desde ${ALERT_ENV}"
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "${ALERT_ENV}"
  set +a
  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "${EMAIL_TPL}" > "${EMAIL_GEN}"
  else
    python3 -c '
import os, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
for key, value in os.environ.items():
    text = text.replace("${%s}" % key, value)
open(dst, "w", encoding="utf-8").write(text)
' "${EMAIL_TPL}" "${EMAIL_GEN}"
  fi
  HELM_EXTRA+=(-f "${EMAIL_GEN}")
  echo "    Notificaciones: webhook + email -> ${ALERT_EMAIL_TO:-?(sin ALERT_EMAIL_TO)}"
else
  echo "AVISO: no existe ${ALERT_ENV} — solo webhook local (sin email)"
fi

echo "==> Repo Helm prometheus-community"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "==> Instalar/actualizar kube-prometheus-stack"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "${NS_MONITORING}" \
  --create-namespace \
  -f "${ROOT_DIR}/monitoring/kube-prometheus-stack/values.yaml" \
  -f "${ROOT_DIR}/monitoring/prometheus/values.yaml" \
  "${HELM_EXTRA[@]}" \
  --wait \
  --timeout 10m

echo "==> Exportador de metricas del pipeline (R1.4)"
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  kubectl -n "${NS_MONITORING}" create secret generic github-token \
    --from-literal=token="${GITHUB_TOKEN}" --dry-run=client -o yaml | kubectl apply -f -
else
  echo "    AVISO: sin GITHUB_TOKEN el exportador consulta GitHub solo cada 10 minutos."
fi
kubectl -n "${NS_MONITORING}" create configmap pipeline-exporter-code \
  --from-file=exporter.py="${ROOT_DIR}/monitoring/prometheus/pipeline-exporter/exporter.py" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${ROOT_DIR}/monitoring/prometheus/pipeline-exporter/pipeline-exporter.yaml"
kubectl -n "${NS_MONITORING}" rollout restart deployment/pipeline-exporter >/dev/null
kubectl -n "${NS_MONITORING}" rollout status deployment/pipeline-exporter --timeout=3m

echo "==> Metricas del Gateway (R1.4)"
kubectl apply -f "${ROOT_DIR}/monitoring/prometheus/servicemonitor-gateway.yaml"

echo "==> Dashboard de Grafana (R1.5)"
kubectl -n "${NS_MONITORING}" create configmap grafana-dashboard-devops-platform \
  --from-file=devops-platform.json="${ROOT_DIR}/monitoring/grafana/dashboards/devops-platform.json" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f -

echo "==> Estado"
kubectl get pods -n "${NS_MONITORING}"
kubectl get prometheusrule -n "${NS_MONITORING}" | grep -E 'devops|NAME' || true

cat <<'EOF'

Monitoreo listo (R1.4, R1.5 y R1.6).

Alertas custom:
  - PodCaido
  - PodCPUAlto (>80%)
  - BuildFallidoConsecutivo

Ver alertas y targets (Prometheus):
  kubectl -n monitoring port-forward --address 0.0.0.0 svc/monitoring-kube-prometheus-prometheus 9090:9090

Grafana (admin / admin), dashboard "Plataforma DevOps: aplicacion y pipeline":
  kubectl -n monitoring port-forward --address 0.0.0.0 svc/monitoring-grafana 3001:80

Alertmanager:
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093

Webhook (evidencia local):
  kubectl -n monitoring logs deploy/alertmanager-webhook -f

Simular build fallido:
  ./scripts/failures/simulate-failures.sh build-fail

EOF
