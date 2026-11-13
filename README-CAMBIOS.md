# Correcciones del CD

Archivos para copiar a las mismas rutas de `devops-platform`.

- `cd.yml` recibe `client_payload.service` y `client_payload.tag`, y distingue Gateway (Blue-Green) de los demás microservicios (Rolling Update).
- `blue-green-release.sh` utiliza Helm `--reuse-values`, despliega el color inactivo, comprueba imagen y respuesta HTTP antes de conmutar el Service con Helm. No usa `kubectl set image` ni parches manuales persistentes.
- `gateway-blue-green.yaml` conserva los tags independientes por color.
- `values-images.yaml` es **base para nuevas instalaciones**; no es una fuente dinámica de tags. Se conserva la versión base anterior a propósito. No reemplaces los tags efectivos del release actual.

## Requisitos y comprobaciones

1. El CI de cada microservicio debe enviar `repository_dispatch` con `event_type: deploy-service` y `client_payload` de la forma `{"service":"gateway","tag":"sha-7595f88"}` (o `users`, `trajectory`, `administrative-data`). Revisar el CI productor: no está incluido.
2. Deben existir en el clúster `microservices`, `gateway-blue`, `gateway-green` y `svc/gateway`, y Helm debe conservar `blueGreen.activeColor` y tags por color. Este CD está diseñado para el clúster **ya instalado**, no para bootstrap inicial.
3. El endpoint de smoke por defecto es `/` y debe devolver HTTP 2xx. Si el Gateway usa otro endpoint público, configurar `SMOKE_PATH` en el entorno del paso de Actions. Una prueba HTTP 2xx no valida por sí sola la versión del código; para eso se comprueba el tag del Deployment.
4. Si el tag está publicado pero el rollout falla, el color activo no cambia. Si el cambio de selector no queda correcto, se intenta revertir con Helm. No se promete rollback ante todos los posibles fallos posteriores.
5. En `workflow_dispatch` con estrategia `blue-green`, indicar `gateway_tag`; para `rolling` o `full-stack` sin tag se reconcilia el release existente. El script `deploy-stack.sh` del modo `full-stack` debe revisarse por separado antes de usarlo en producción.
6. `--reuse-values` mantiene el estado de imágenes actual, pero puede requerir un tratamiento especial si se hacen cambios de estructura de `values.yaml` o si la revisión del release no incluye los valores esperados.
7. La opción `run_load_verification` invoca el script existente que conmuta colores; úsala solo si deseas ese switch adicional y has revisado el script.

## Validación antes de hacer push

```bash
bash -n scripts/blue-green-release.sh
helm lint ./helm/microservices -f ./helm/microservices/values.yaml -f ./helm/microservices/values-images.yaml
helm template microservices ./helm/microservices -f ./helm/microservices/values.yaml -f ./helm/microservices/values-images.yaml >/tmp/rendered.yaml
kubectl get svc gateway -n devops -o jsonpath='{.spec.selector.version}{"\n"}'
helm get values microservices -n devops -o yaml
```

No incluyas `.env` ni credenciales en los commits.
