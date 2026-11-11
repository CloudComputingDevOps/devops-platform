#!/usr/bin/env bash
# Cambia el color activo del Gateway (blue <-> green) vía selector del Service.
# Uso:
#   ./scripts/blue-green-switch.sh            # alterna
#   ./scripts/blue-green-switch.sh blue       # fuerza blue
#   ./scripts/blue-green-switch.sh green      # fuerza green
#   ./scripts/blue-green-switch.sh status     # solo muestra estado
set -euo pipefail

NS="${NS:-devops}"
SVC="${SVC:-gateway}"
TARGET="${1:-toggle}"

current() {
  kubectl get svc "${SVC}" -n "${NS}" -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "unknown"
}

status() {
  local active
  active="$(current)"
  echo "Namespace: ${NS}"
  echo "Service:   ${SVC}"
  echo "Activo:    ${active}"
  echo
  kubectl get deploy -n "${NS}" -l app=gateway -o wide
  echo
  kubectl get endpoints "${SVC}" -n "${NS}" -o wide
  echo
  kubectl get ingress -n "${NS}" 2>/dev/null || true
}

wait_ready() {
  local color="$1"
  echo "==> Esperando readiness de gateway-${color}"
  kubectl rollout status "deployment/gateway-${color}" -n "${NS}" --timeout=180s
  # Confirmar que el Service tiene endpoints
  for i in $(seq 1 30); do
    local ready
    ready="$(kubectl get endpoints "${SVC}" -n "${NS}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
    if [[ -n "${ready}" ]]; then
      echo "==> Endpoints listos: ${ready}"
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Service ${SVC} sin endpoints tras el switch" >&2
  return 1
}

switch_to() {
  local color="$1"
  if [[ "${color}" != "blue" && "${color}" != "green" ]]; then
    echo "Color inválido: ${color} (usa blue|green)" >&2
    exit 1
  fi

  echo "==> Color actual: $(current) -> ${color}"
  kubectl patch svc "${SVC}" -n "${NS}" --type merge -p \
    "{\"metadata\":{\"labels\":{\"bluegreen.active\":\"${color}\"}},\"spec\":{\"selector\":{\"app\":\"gateway\",\"version\":\"${color}\"}}}"

  wait_ready "${color}"
  status
}

case "${TARGET}" in
  status)
    status
    ;;
  blue|green)
    switch_to "${TARGET}"
    ;;
  toggle|"")
    cur="$(current)"
    if [[ "${cur}" == "blue" ]]; then
      switch_to green
    else
      switch_to blue
    fi
    ;;
  *)
    echo "Uso: $0 [toggle|blue|green|status]" >&2
    exit 1
    ;;
esac
