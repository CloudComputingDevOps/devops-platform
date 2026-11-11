# Guía paso a paso — Integrante 3 (terminar tu parte)

Esta guía es lo que tienes que hacer **ahora** para cerrar:

- **R1.7** Blue-green con Ingress  
- **R1.6** 3 alertas en Alertmanager con notificación  
- Pruebas de carga **wrk/k6**  
- Escenarios de **fallos simulados**

---

## 0. Respuesta rápida a tus dudas

| Pregunta | Respuesta |
| --- | --- |
| ¿Entro en Linux? | **Sí.** Todo se corre en la VM Ubuntu (Vagrant/VirtualBox) con Minikube. En Windows solo editamos el repo. |
| ¿Qué corro? | Scripts de este repo: `deploy-stack.sh` → `install-monitoring.sh` → carga → fallos. |
| ¿Tenemos SMTP? | **Sí.** Alertmanager usa **Resend SMTP** (`smtp.resend.com:587`) con la API key que ya está en `secrets/devops/alertmanager.env`. |
| ¿A qué correo llega? | A `notificaciones@devcorebits.com` (el mismo `ALERT_EMAIL_TO`). Debes poder abrir esa bandeja (o el panel de Resend → Emails). |
| ¿Qué más pide mi parte? | Evidencias: capturas/logs de blue-green bajo carga, 3 alertas firing, y notificación recibida (email y/o logs del webhook). |

---

## 1. Entrar a Linux y preparar el entorno

### 1.1 Abrir la VM

```bash
# En tu máquina host (donde tienes Vagrant), si aplica:
cd <carpeta-de-la-vm>
vagrant up
vagrant ssh
```

Si ya estás dentro de Ubuntu con Minikube, sigue.

### 1.2 Comprobar herramientas

```bash
minikube status
# Si está parado:
minikube start --driver=docker

kubectl get nodes
helm version
docker info | head
```

Addons necesarios:

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

Instala herramientas de carga (si no están):

```bash
# wrk
sudo apt-get update
sudo apt-get install -y wrk gettext-base

# k6 (Ubuntu)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install -y k6
```

### 1.3 Tener el repo en la VM

Copia o clona `devops-platform` **incluyendo** la carpeta local `secrets/devops/` (está en `.gitignore`, no viene del remoto).

Opciones:

**A)** Clonar y recrear secrets a mano desde tus `.env` locales.

**B)** Copiar desde Windows (carpeta compartida / `scp` / USB):

```bash
# Ejemplo: si montas el repo en ~/devops-platform
cd ~/devops-platform
ls secrets/devops/
# Debe mostrar:
#   administrative-data.env  users.env  trajectory.env  alertmanager.env
```

Si `secrets/devops/` no está:

```bash
mkdir -p secrets/devops
nano secrets/devops/administrative-data.env
nano secrets/devops/users.env
nano secrets/devops/trajectory.env
nano secrets/devops/alertmanager.env
# Pega el mismo contenido que tienes en Windows (sin subirlos a Git)
```

### 1.4 Permisos de scripts

```bash
cd ~/devops-platform   # o la ruta real del repo
chmod +x scripts/*.sh scripts/load/*.sh scripts/failures/*.sh
```

Crea carpeta de evidencias:

```bash
mkdir -p docs/evidencias/integrante-3
```

---

## 2. Desplegar la app + blue-green + Ingress (R1.7 base)

```bash
./scripts/deploy-stack.sh
```

Qué hace: namespace `devops`, Secrets, NATS, microservicios, `gateway-blue` + `gateway-green`, Service + Ingress.

Configura el host:

```bash
echo "$(minikube ip) gateway.local" | sudo tee -a /etc/hosts
curl -i http://gateway.local/ | head
```

**Evidencia 1 — Blue-green existe**

```bash
kubectl get deploy,svc,ingress -n devops | tee docs/evidencias/integrante-3/01-blue-green-recursos.txt
./scripts/blue-green-switch.sh status | tee docs/evidencias/integrante-3/02-blue-green-status.txt
```

Deberías ver `gateway-blue`, `gateway-green`, Service `gateway`, Ingress `gateway`.

---

## 3. Instalar monitoreo y Alertmanager (R1.6 base)

```bash
./scripts/install-monitoring.sh
```

Esto instala:

- Prometheus + Grafana + **Alertmanager**
- Webhook local (logs de evidencia)
- Pushgateway (para la alerta de builds)
- **Email SMTP vía Resend** (lee `secrets/devops/alertmanager.env`)

**Evidencia 2 — Stack de monitoreo**

```bash
kubectl get pods -n monitoring | tee docs/evidencias/integrante-3/03-monitoring-pods.txt
kubectl get prometheusrule -n monitoring | tee docs/evidencias/integrante-3/04-prometheus-rules.txt
```

Abre UIs (en 3 terminales distintas si quieres):

```bash
# Prometheus
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/alerts

# Alertmanager
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
# → http://localhost:9093

# Logs del webhook (evidencia aunque el email falle)
kubectl -n monitoring logs deploy/alertmanager-webhook -f
```

Si estás en la VM por SSH sin GUI, usa `curl` o captura desde el host con otro port-forward; o saca pantallazos si tienes escritorio.

---

## 4. Cómo funciona el correo (SMTP)

### ¿Tenemos SMTP?

**Sí.** No montamos un servidor SMTP propio. Usamos el de **Resend**:

| Campo | Valor |
| --- | --- |
| Servidor | `smtp.resend.com:587` |
| Usuario | `resend` |
| Password | tu `RESEND_API_KEY` (en `alertmanager.env`) |
| From | `notificaciones@devcorebits.com` |
| To | `notificaciones@devcorebits.com` |

Alertmanager, cuando una alerta pasa a **firing**, envía:

1. **Email** a esa bandeja  
2. **Webhook** al pod `alertmanager-webhook` (queda en `kubectl logs`)

### Cómo ver si el correo llegó

1. Abre el buzón de `notificaciones@devcorebits.com` (quien administre ese dominio/correo del equipo).  
2. O entra al [dashboard de Resend](https://resend.com) → sección de emails enviados (ahí ves entregados/fallidos).  
3. Si el email falla (dominio no verificado, API key inválida, etc.), **igual sirve la evidencia del webhook** + captura de Alertmanager. El enunciado pide email **o** Slack; el webhook es respaldo técnico, pero lo ideal es email.

### Si el email no llega

Revisa logs de Alertmanager:

```bash
kubectl -n monitoring logs statefulset/monitoring-kube-prometheus-alertmanager --tail=100
```

Causas típicas:

- Dominio `devcorebits.com` no verificado en Resend  
- API key revocada  
- Destino en spam  

Mientras tanto, guarda siempre:

```bash
kubectl -n monitoring logs deploy/alertmanager-webhook --tail=200 \
  | tee docs/evidencias/integrante-3/05-webhook-notificaciones.txt
```

---

## 5. Demostrar blue-green sin cortar tráfico (R1.7)

Criterio: cambio de versión **sin pérdida de requests** durante wrk/k6.

```bash
# Asegura que blue está activo y green está Ready
./scripts/blue-green-switch.sh blue
kubectl rollout status deploy/gateway-green -n devops

# Carga 60s y a los ~20s cambia a green
./scripts/load/blue-green-during-load.sh green \
  | tee docs/evidencias/integrante-3/06-blue-green-bajo-carga.txt
```

También puedes correr wrk aparte:

```bash
BASE_URL=http://gateway.local ./scripts/load/run-wrk.sh \
  | tee docs/evidencias/integrante-3/07-wrk.txt

BASE_URL=http://gateway.local ./scripts/load/run-k6.sh \
  | tee docs/evidencias/integrante-3/08-k6.txt
```

**Qué mirar en la evidencia:** pocos/cero errores de conexión durante el switch. Un 404 en `/` puede ser normal si el Gateway no tiene esa ruta; lo crítico es que **no caiga la conexión** (no `connection refused` / fallos de red).

Si Ingress no responde:

```bash
kubectl -n devops port-forward svc/gateway 3000:3000
BASE_URL=http://127.0.0.1:3000 ./scripts/load/blue-green-during-load.sh green
```

---

## 6. Disparar las 3 alertas (R1.6) + fallos simulados

Deja abiertos en paralelo:

- Prometheus → `/alerts`  
- Alertmanager → UI  
- `kubectl -n monitoring logs deploy/alertmanager-webhook -f`  
- Bandeja / Resend  

### Alerta 1 — PodCaido

```bash
./scripts/failures/simulate-failures.sh pod-down
# Espera 1–2 minutos hasta que figure FIRING
# Captura pantalla de Prometheus/Alertmanager + email/webhook
./scripts/failures/simulate-failures.sh restore-pod-down
```

### Alerta 2 — PodCPUAlto (> 80%)

```bash
./scripts/failures/simulate-failures.sh cpu-stress
# Espera 2–3 minutos
# Captura evidencia
./scripts/failures/simulate-failures.sh restore-cpu-stress
```

### Alerta 3 — BuildFallidoConsecutivo

```bash
./scripts/failures/simulate-failures.sh build-fail
# Espera ~1 minuto
# Captura evidencia
./scripts/failures/simulate-failures.sh restore-build-fail
```

Guarda logs finales:

```bash
kubectl -n monitoring logs deploy/alertmanager-webhook --tail=300 \
  | tee docs/evidencias/integrante-3/09-alertas-webhook.txt
```

---

## 7. Checklist final de tu entrega

Marca cuando esté hecho:

### R1.7 Blue-green + Ingress

- [ ] Existen `gateway-blue` y `gateway-green`
- [ ] Hay Ingress hacia `gateway.local` (o port-forward documentado)
- [ ] Hiciste switch blue → green
- [ ] Corriste wrk o k6 **durante** el switch
- [ ] Guardaste salida demostrando que no se perdieron requests (sin errores de conexión)

### R1.6 Alertmanager

- [ ] 3 reglas visibles: `PodCaido`, `PodCPUAlto`, `BuildFallidoConsecutivo`
- [ ] Disparaste las 3 con fallos simulados
- [ ] Notificación recibida: **email** y/o logs del webhook
- [ ] Capturas de Alertmanager/Prometheus en estado firing

### Carga y fallos

- [ ] Resultado wrk en `docs/evidencias/...`
- [ ] Resultado k6 en `docs/evidencias/...`
- [ ] Scripts de fallo usados y restaurados

### Repo / docs

- [ ] Tus cambios de manifiestos/scripts están en el repo (sin secretos)
- [ ] `secrets/devops/` **no** está en Git
- [ ] Puedes explicar en la sustentación el flujo en 2 minutos

---

## 8. Orden recomendado el día que lo hagas (45–90 min)

1. `vagrant ssh` / entrar a Linux  
2. `minikube start` + addons  
3. `./scripts/deploy-stack.sh` + `/etc/hosts`  
4. `./scripts/install-monitoring.sh`  
5. Port-forwards + terminal del webhook  
6. `./scripts/load/blue-green-during-load.sh green` → evidencia R1.7  
7. Tres fallos (`pod-down`, `cpu-stress`, `build-fail`) → evidencia R1.6  
8. Revisar email en Resend / bandeja  
9. Empaquetar capturas en `docs/evidencias/integrante-3/`

---

## 9. Qué NO tienes que hacer tú

- Configurar ramas `main`/`develop` (R1.1)  
- Pipeline Jenkins/GitHub Actions completo (R1.2)  
- Dashboard Grafana de 6 paneles JSON (R1.5) — otro integrante, aunque Prometheus ya queda instalado  
- Informe comparativo manual vs automático completo (R1.8) — aporta tu sección de blue-green/alertas si te lo piden  

---

## 10. Si algo falla

| Problema | Qué hacer |
| --- | --- |
| `ImagePullBackOff` | Imágenes GHCR privadas → hace falta `imagePullSecrets` (pide ayuda al de CI) |
| Pods CrashLoop | `kubectl logs deploy/<nombre> -n devops --tail=100` — casi siempre falta Secret/env |
| Ingress 404/no resuelve | `/etc/hosts` con `minikube ip` o usa `port-forward` |
| No llega email | Logs Alertmanager + panel Resend; usa webhook como evidencia alternativa |
| No hay `secrets/devops` en la VM | Cópialos desde Windows; sin eso no arrancan Users/Admin/Trajectory ni el SMTP |

---

**Resumen en una frase:** entras a Linux (VM), despliegas con los scripts, demuestras blue-green bajo k6/wrk, disparas las 3 alertas y guardas capturas + email/webhook. Eso cierra tu parte.
