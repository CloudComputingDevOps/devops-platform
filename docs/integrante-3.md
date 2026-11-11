# Integrante 3 — Despliegue Avanzado y Alertas (R1.6 / R1.7)

> **Guía práctica para terminar hoy:** [`guia-paso-a-paso-integrante-3.md`](guia-paso-a-paso-integrante-3.md)

## Tu alcance en el proyecto

| ID | Requerimiento | Estado en repo | Estado en clúster |
| --- | --- | --- | --- |
| **R1.6** | ≥3 alertas Alertmanager + email/Slack | Listo (config) | Pendiente ejecutar en VM |
| **R1.7** | Blue-green + Ingress sin pérdida de requests | Listo (config + scripts) | Pendiente demostrar con k6/wrk |
| Carga | wrk / k6 | Scripts listos | Pendiente ejecutar |
| Fallos | Escenarios simulados | Scripts listos | Pendiente ejecutar |

### No es tuyo (otros integrantes), pero depende de ellos

| ID | Quién suele llevarlo | Nota |
| --- | --- | --- |
| R1.1 | Git/flujo de ramas | Necesitas PRs para integrar tus cambios |
| R1.2 | CI/CD | Debe publicar imágenes a GHCR; la alerta de build usa Pushgateway si CI no exporta métricas |
| R1.3 | Infra base | Rolling update + 2 réplicas (este chart aún usa `replicaCount: 1` salvo blue/green) |
| R1.4 / R1.5 | Monitoreo dashboards | Prometheus ya queda instalado con retención 7d; Grafana JSON de 6 paneles es R1.5 |
| R1.8 | Documentación global | Tú aportas la sección de blue-green/alertas |

## Secretos locales

Están en `secrets/devops/` (**gitignored**):

- `administrative-data.env`
- `users.env`
- `trajectory.env`
- `alertmanager.env` (SMTP Resend → email)

Cópialos a la VM junto con el repo (o regenera tras rotar claves).

## Ejecutar en la VM (checklist de sustentación)

```bash
chmod +x scripts/*.sh scripts/load/*.sh scripts/failures/*.sh

# 1. App + blue-green + Ingress
./scripts/deploy-stack.sh
echo "$(minikube ip) gateway.local" | sudo tee -a /etc/hosts

# 2. Prometheus + Alertmanager (email + webhook) + Pushgateway
./scripts/install-monitoring.sh

# 3. R1.7 — switch bajo carga (evidencia sin pérdida de requests)
./scripts/load/blue-green-during-load.sh green

# 4. R1.6 — disparar las 3 alertas
./scripts/failures/simulate-failures.sh pod-down      # PodCaido
./scripts/failures/simulate-failures.sh restore-pod-down

./scripts/failures/simulate-failures.sh cpu-stress    # PodCPUAlto (~2-3 min)
./scripts/failures/simulate-failures.sh restore-cpu-stress

./scripts/failures/simulate-failures.sh build-fail    # BuildFallidoConsecutivo
./scripts/failures/simulate-failures.sh restore-build-fail

# Evidencia notificaciones
kubectl -n monitoring logs deploy/alertmanager-webhook -f
# + capturas de email en notificaciones@devcorebits.com
```

### Las 3 alertas (criterio R1.6)

1. **PodCaido** — pod no Ready / Failed  
2. **PodCPUAlto** — CPU > 80% del límite  
3. **BuildFallidoConsecutivo** — `cicd_pipeline_consecutive_failures > 1` (Pushgateway)

Notificación: **email (Resend SMTP)** + webhook local para logs de evidencia.

## Qué falta de tu parte (acción humana)

1. **Correr todo en la VM Minikube** — desde este Windows no hay clúster.  
2. **Capturar evidencias**: switch blue-green bajo k6/wrk, Alertmanager firing, email recibido, logs del webhook.  
3. **Rotar secretos** cuando toque (ya quedaron en archivos locales; no subirlos a Git).  
4. **Confirmar que el correo llega** — Resend debe permitir enviar desde `notificaciones@devcorebits.com`; si falla SMTP, usa Slack webhook en `values.yaml`.  
5. **Opcional con CI**: que el pipeline empuje `cicd_pipeline_consecutive_failures` al Pushgateway en fallos reales (hoy se simula).  
6. **No eres responsable de R1.5**, pero si el equipo te pide ayuda: exportar dashboards Grafana a JSON en el repo.

## Criterios de aceptación vs evidencia

| Criterio | Cómo lo demuestras |
| --- | --- |
| Alertas disparadas y recibidas | Fallos simulados + email/webhook |
| Blue-green sin pérdida de requests | `blue-green-during-load.sh` + salida k6/wrk sin errores de conexión |
