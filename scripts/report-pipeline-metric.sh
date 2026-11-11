#!/usr/bin/env bash
# Reporta métricas del pipeline CI/CD al Pushgateway en Kubernetes.
# Alimenta Prometheus (R1.4) y la regla BuildFallidoConsecutivo en Alertmanager (R1.6).
#
# Uso:
#   ./scripts/report-pipeline-metric.sh success [duration_sec] [pipeline_name]
#   ./scripts/report-pipeline-metric.sh failure [duration_sec] [pipeline_name]
set -euo pipefail

STATUS="${1:-success}"
DURATION="${2:-0}"
INSTANCE="${3:-github_actions_cd}"
NS_MONITORING="${NS_MONITORING:-monitoring}"
STATE_FILE="${TMPDIR:-/tmp}/cicd_consecutive_failures_${INSTANCE}.count"

PREV_FAILURES=0
if [[ -f "${STATE_FILE}" ]]; then
  PREV_FAILURES="$(cat "${STATE_FILE}" 2>/dev/null || echo 0)"
fi

if [[ "${STATUS}" == "failure" ]]; then
  CONSECUTIVE=$((PREV_FAILURES + 1))
  SUCCESS_VAL=0
else
  CONSECUTIVE=0
  SUCCESS_VAL=1
fi

echo "${CONSECUTIVE}" > "${STATE_FILE}"
NOW_TS="$(date +%s)"

PAYLOAD="$(cat <<EOF
# TYPE cicd_pipeline_consecutive_failures gauge
cicd_pipeline_consecutive_failures ${CONSECUTIVE}
# TYPE cicd_pipeline_last_run_status gauge
cicd_pipeline_last_run_status ${SUCCESS_VAL}
# TYPE cicd_pipeline_last_duration_seconds gauge
cicd_pipeline_last_duration_seconds ${DURATION}
# TYPE cicd_pipeline_last_run_timestamp_seconds gauge
cicd_pipeline_last_run_timestamp_seconds ${NOW_TS}
EOF
)"

echo "==> Reportando métricas CI/CD a Pushgateway (status=${STATUS}, consecutive_failures=${CONSECUTIVE})"

if ! kubectl get svc pushgateway -n "${NS_MONITORING}" >/dev/null 2>&1; then
  echo "AVISO: Service pushgateway no existe aún en namespace ${NS_MONITORING}; se omite push."
  exit 0
fi

kubectl run pushgateway-ci-reporter \
  --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -n "${NS_MONITORING}" \
  --command -- sh -c "cat <<'METRICS' | curl -fsS --data-binary @- http://pushgateway.${NS_MONITORING}.svc.cluster.local:9091/metrics/job/ci_pipeline/instance/${INSTANCE}
${PAYLOAD}
METRICS" >/dev/null 2>&1 || echo "AVISO: no se pudo empujar métrica a Pushgateway"
