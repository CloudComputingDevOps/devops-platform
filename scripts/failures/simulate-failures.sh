#!/usr/bin/env bash
# Escenarios de fallos simulados para evidenciar alertas (R1.6) y blue-green (R1.7).
#
# Uso: ./scripts/failures/simulate-failures.sh <accion>
set -euo pipefail

NS="${NS:-devops}"
ACTION="${1:-list}"

watch_hints() {
  cat <<'EOF'

Observa alertas / notificaciones:
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
  kubectl -n monitoring logs deploy/alertmanager-webhook -f
  # Email: bandeja de ALERT_EMAIL_TO (Resend SMTP)

EOF
}

list() {
  cat <<'EOF'
Escenarios R1.6:

  pod-down / restore-pod-down     Dispara PodCaido (escala un deployment a 0)
  cpu-stress / restore-cpu-stress Dispara PodCPUAlto (stress en gateway-blue)
  build-fail / restore-build-fail Dispara BuildFallidoConsecutivo (Pushgateway)

Extras:

  gateway-down / restore-gateway
  crashloop / restore-crashloop
  bad-switch / restore-bad-switch [blue|green]

EOF
}

pod_down() {
  echo "==> Escalando users a 0 (PodCaido / sin Ready)"
  kubectl scale deploy/users -n "${NS}" --replicas=0
  watch_hints
}

restore_pod_down() {
  echo "==> Restaurando users a 1"
  kubectl scale deploy/users -n "${NS}" --replicas=1
  kubectl rollout status deploy/users -n "${NS}" --timeout=180s
}

cpu_stress() {
  echo "==> Lanzando stress de CPU en gateway-blue (necesita ~2m para PodCPUAlto)"
  local pod
  pod="$(kubectl get pod -n "${NS}" -l app=gateway,version=blue -o jsonpath='{.items[0].metadata.name}')"
  if [[ -z "${pod}" ]]; then
    echo "No hay pod gateway-blue" >&2
    exit 1
  fi
  # stress-ng puede no existir; usamos un busy-loop en el contenedor
  kubectl exec -n "${NS}" "${pod}" -- sh -c \
    'nohup sh -c "while true; do :; done" >/tmp/cpu-stress.log 2>&1 &' || \
  kubectl exec -n "${NS}" "${pod}" -- /bin/sh -c \
    'nohup /bin/sh -c "while true; do :; done" >/tmp/cpu-stress.log 2>&1 &'
  echo "Stress iniciado en ${pod}. Espera 2-3 minutos y revisa la alerta PodCPUAlto."
  watch_hints
}

restore_cpu_stress() {
  echo "==> Reiniciando gateway-blue para cortar el stress"
  kubectl rollout restart deploy/gateway-blue -n "${NS}"
  kubectl rollout status deploy/gateway-blue -n "${NS}" --timeout=180s
}

build_fail() {
  echo "==> Publicando cicd_pipeline_consecutive_failures=2 en Pushgateway"
  kubectl -n monitoring run curl-push --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- \
    sh -c 'printf "cicd_pipeline_consecutive_failures 2\n" | curl --data-binary @- http://pushgateway.monitoring.svc.cluster.local:9091/metrics/job/ci_pipeline/instance/github_actions'
  watch_hints
}

restore_build_fail() {
  echo "==> Reseteando métrica de builds fallidos"
  kubectl -n monitoring run curl-push --rm -i --restart=Never --image=curlimages/curl:8.5.0 -- \
    sh -c 'printf "cicd_pipeline_consecutive_failures 0\n" | curl --data-binary @- http://pushgateway.monitoring.svc.cluster.local:9091/metrics/job/ci_pipeline/instance/github_actions'
}

gateway_down() {
  echo "==> Escalando gateway-blue y gateway-green a 0"
  kubectl scale deploy/gateway-blue deploy/gateway-green -n "${NS}" --replicas=0
  watch_hints
}

restore_gateway() {
  echo "==> Restaurando gateway-blue/green a 1"
  kubectl scale deploy/gateway-blue deploy/gateway-green -n "${NS}" --replicas=1
  kubectl rollout status deploy/gateway-blue -n "${NS}" --timeout=180s
  kubectl rollout status deploy/gateway-green -n "${NS}" --timeout=180s
}

crashloop() {
  echo "==> Imagen inválida en gateway-green"
  kubectl set image "deployment/gateway-green" -n "${NS}" \
    gateway=ghcr.io/cloudcomputingdevops/gateway:does-not-exist-fail
  watch_hints
}

restore_crashloop() {
  local tag="${GREEN_TAG:-sha-d712b92}"
  echo "==> Restaurando gateway-green a tag ${tag}"
  kubectl set image "deployment/gateway-green" -n "${NS}" \
    gateway="ghcr.io/cloudcomputingdevops/gateway:${tag}"
  kubectl rollout status deploy/gateway-green -n "${NS}" --timeout=180s
}

bad_switch() {
  echo "==> Service gateway -> version=orange (sin endpoints)"
  kubectl patch svc gateway -n "${NS}" --type merge -p \
    '{"metadata":{"labels":{"bluegreen.active":"orange"}},"spec":{"selector":{"app":"gateway","version":"orange"}}}'
  watch_hints
}

restore_bad_switch() {
  local color="${2:-blue}"
  echo "==> Service gateway -> version=${color}"
  kubectl patch svc gateway -n "${NS}" --type merge -p \
    "{\"metadata\":{\"labels\":{\"bluegreen.active\":\"${color}\"}},\"spec\":{\"selector\":{\"app\":\"gateway\",\"version\":\"${color}\"}}}"
  kubectl get endpoints gateway -n "${NS}"
}

case "${ACTION}" in
  list) list ;;
  pod-down) pod_down ;;
  restore-pod-down) restore_pod_down ;;
  cpu-stress) cpu_stress ;;
  restore-cpu-stress) restore_cpu_stress ;;
  build-fail) build_fail ;;
  restore-build-fail) restore_build_fail ;;
  gateway-down) gateway_down ;;
  restore-gateway) restore_gateway ;;
  crashloop) crashloop ;;
  restore-crashloop) restore_crashloop ;;
  bad-switch) bad_switch ;;
  restore-bad-switch) restore_bad_switch "$@" ;;
  *)
    echo "Acción desconocida: ${ACTION}" >&2
    list
    exit 1
    ;;
esac
