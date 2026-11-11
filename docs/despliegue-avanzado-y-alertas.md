# Despliegue Avanzado, Entrega Continua y Sistema de Alertas

Documentación técnica de los componentes de **Despliegue Avanzado (Blue-Green con Ingress)**, **Entrega Continua (CD)**, **Alertmanager** y **Pruebas de Carga / Fallos Simulados** correspondientes a los requerimientos **R1.6** y **R1.7**.

## 1. Estrategia Blue-Green e Ingress (R1.7)

El servicio **API Gateway** se despliega bajo una arquitectura Blue-Green en el namespace `devops` para garantizar transiciones de versión sin pérdida de peticiones HTTP:

- **Deployments paralelos**: `gateway-blue` y `gateway-green` (plantilla `helm/microservices/templates/gateway-blue-green.yaml`), cada uno con etiquetas `app: gateway` y `version: blue | green`, sondas `readinessProbe` y `livenessProbe`.
- **Service conmutador**: el Service `gateway` (`ClusterIP`, puerto `3000`) enruta tráfico únicamente hacia el color activo mediante el selector `version: <activeColor>`.
- **Ingress NGINX**: el recurso `Ingress` (`helm/microservices/templates/ingress.yaml`) expone el host `gateway.local` hacia el Service `gateway:3000`.

### Flujo de liberación sin tiempo de inactividad

1. El pipeline identifica el color activo actual en el Service `gateway` (por ejemplo, `blue`) y selecciona el slot inactivo (`green`).
2. Actualiza la imagen contenedor en `deployment/gateway-green` sin alterar el tráfico productivo.
3. Espera la confirmación de disponibilidad (`kubectl rollout status deployment/gateway-green`).
4. Verifica la salud del pod candidato y conmuta el selector del Service `gateway` hacia `green` (`scripts/blue-green-release.sh` y `scripts/blue-green-switch.sh`).
5. En caso de anomalía durante la verificación, revierte automáticamente el selector al color previo.

## 2. Pipeline de Entrega Continua — CD (`.github/workflows/cd.yml`)

El flujo de despliegue continuo está automatizado en GitHub Actions y se ejecuta ante cambios en `main`/`develop`, eventos `repository_dispatch` desde los repositorios de los microservicios o ejecución manual (`workflow_dispatch`):

- **Job `validate-manifests` (`ubuntu-latest`)**: valida la sintaxis de los scripts, ejecuta `helm lint` y renderiza las plantillas con `values.yaml` y `values-images.yaml`.
- **Job `deploy-cluster` (`self-hosted`)**:
  - Sincroniza el namespace `devops` y los Secrets de Kubernetes desde `~/secrets/devops/`.
  - Aplica `helm upgrade --install microservices` preservando el color activo del Gateway y ejecutando `RollingUpdate` (`maxUnavailable: 0`, `maxSurge: 1`) en los microservicios de negocio.
  - Ejecuta la liberación Blue-Green del Gateway (`scripts/blue-green-release.sh`).
  - Publica métricas de estado y duración del despliegue en **Prometheus Pushgateway** (`scripts/report-pipeline-metric.sh`).

## 3. Reglas de Alertmanager y Notificaciones (R1.6)

El stack `kube-prometheus-stack` se configura en el namespace `monitoring` mediante `monitoring/kube-prometheus-stack/values.yaml` y `scripts/install-monitoring.sh`.

### Reglas de alerta implementadas

| Regla | Expresión / Condición | Duración (`for`) | Severidad |
| --- | --- | --- | --- |
| `PodCaido` | Pods en namespace `devops` con `kube_pod_status_ready == 0` o en fase `Failed\|Unknown` | `1m` | `critical` |
| `PodCPUAlto` | Uso de CPU del contenedor superior al `80%` de su límite configurado (`resources.limits.cpu`) | `2m` | `warning` |
| `BuildFallidoConsecutivo` | Métrica `cicd_pipeline_consecutive_failures > 1` reportada en Pushgateway | `1m` | `critical` |

### Canales de notificación

- **Correo electrónico (SMTP TLS)**: enviado a través de `smtp.resend.com:587` hacia la cuenta de notificaciones del equipo (plantilla `monitoring/kube-prometheus-stack/values-email.yaml.tpl` inyectada desde `secrets/devops/alertmanager.env`).
- **Receptor Webhook interno**: servicio `alertmanager-webhook` (`monitoring/alertmanager-webhook/deployment.yaml`) que registra en estructurado JSON cada alerta disparada (`firing`) y resuelta (`resolved`).

## 4. Pruebas de Carga y Escenarios de Fallos Simulados

### Pruebas de carga (wrk y k6)

Ubicadas en `scripts/load/`:

- `gateway-k6.js` y `run-k6.sh`: prueba de carga sostenida con `k6` contra el Gateway (`http://gateway.local/api/areas`), evaluando latencia `p95` y tasa de fallos.
- `run-wrk.sh`: prueba de concurrencia HTTP mediante `wrk`.
- `blue-green-during-load.sh`: inicia carga continua y ejecuta la conmutación Blue-Green a mitad de la prueba para verificar cero pérdidas de conexión.

```bash
# Prueba de transición Blue-Green bajo carga
./scripts/load/blue-green-during-load.sh green
```

### Simulación controlada de fallos

El script `scripts/failures/simulate-failures.sh` permite inducir y restaurar cada condición para verificar la activación de las alertas en Prometheus y Alertmanager:

```bash
# 1. Alerta PodCaido
./scripts/failures/simulate-failures.sh pod-down
./scripts/failures/simulate-failures.sh restore-pod-down

# 2. Alerta PodCPUAlto (> 80% límite CPU)
./scripts/failures/simulate-failures.sh cpu-stress
./scripts/failures/simulate-failures.sh restore-cpu-stress

# 3. Alerta BuildFallidoConsecutivo (Pushgateway)
./scripts/failures/simulate-failures.sh build-fail
./scripts/failures/simulate-failures.sh restore-build-fail
```
