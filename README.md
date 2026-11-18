# Proyecto 1 — Plataforma DevOps de extremo a extremo con CI/CD, contenedores y monitoreo

**Asignatura:** Computación en la Nube

**Profesor:** Oscar Mondragón

## Integrantes del grupo

| Integrante | Nombre completo |
| --- | --- |
| 1 | Camila Paz |
| 2 | Juan Penagos |
| 3 | Esteban Triviño |
| 4 | Juan Zuluaga |


## Introducción

Desplegar una aplicación de microservicios de forma manual implica repetir pasos para construir imágenes, actualizar el clúster y comprobar que los servicios siguen disponibles. Este proyecto académico integra esas tareas en un flujo DevOps que va desde un cambio en GitHub hasta su despliegue en Kubernetes y el seguimiento de la aplicación una vez desplegada.

La solución usa GitHub Actions para ejecutar la integración y la entrega continua. Los pipelines construyen y publican imágenes Docker en GitHub Container Registry, y Helm gestiona el despliegue del backend en Minikube. Los servicios de negocio se actualizan de forma gradual mediante *rolling update*, mientras que el API Gateway utiliza *blue-green* para preparar y comprobar una versión candidata antes de dirigirle el tráfico. Prometheus recopila métricas, Grafana permite consultarlas y Alertmanager gestiona las notificaciones durante las pruebas de carga o los fallos simulados.

La entrega académica incluye el código y la configuración de despliegue, un dashboard con métricas de la aplicación y del pipeline, una comparación de tiempos entre el despliegue manual y el automatizado, y una guía reproducible. Este README cubre esa última parte. Su objetivo es que un estudiante externo pueda preparar el entorno, levantar el backend y el frontend y comprobar una operación real en menos de 60 minutos con los prerrequisitos disponibles.

## Cómo leer este README

Este documento es la guía paso a paso del proyecto. Está pensado para que una persona externa, sin haber participado en él, pueda reproducir el entorno y entender las decisiones de diseño.

| Parte | Secciones | Para qué sirve |
| --- | --- | --- |
| Antes de empezar | Arquitectura, organización del repositorio, glosario y "Qué necesitas y qué entrega el equipo" | Vocabulario básico y lista de todo lo que debes tener **antes** del primer comando |
| Levantar la plataforma | 1 a 9 | Desplegar el backend en Minikube, abrir el frontend, instalar el monitoreo, actualizar con Blue-Green y diagnosticar fallos |
| Integración continua | 10 | Cómo están montados las ramas protegidas, el pipeline de GitHub Actions y el registro de imágenes, y cómo comprobar que funcionan |
| Manual vs. automatizado | 11 | Comparación de tiempos entre construir y publicar a mano y hacerlo con el pipeline, con los comandos para repetir la medición |

**Orden recomendado:** lee el glosario, completa la lista de la sección "Qué necesitas", y sigue las secciones 1 a 9. Las secciones 10 y 11 explican cómo se producen las imágenes que usa el clúster y no son necesarias para levantar la plataforma, porque las imágenes ya están publicadas.

## Arquitectura de la aplicación

El frontend Next.js se ejecuta fuera del clúster y accede al Gateway a través de `gateway.local`. El Service `gateway` dirige el tráfico a uno de los dos despliegues según el selector activo. Los microservicios de negocio se comunican con el Gateway mediante NATS y cada uno usa su propia base de datos en Supabase.

```mermaid
flowchart TB
    FRONT["Frontend Next.js"]

    subgraph CLUSTER["Minikube"]
        INGRESS["Ingress NGINX  gateway.local"]
        SERVICE["Service gateway  Port: 3000"]
        BLUE("Gateway")
        NATS["NATS  4222"]
        ADMIN["Administrative Data"]
        USERS["Users"]
        TRAJECTORY["Trajectory"]

        INGRESS --> SERVICE
        SERVICE --> BLUE
        BLUE <--> NATS
        NATS <--> ADMIN
        NATS <--> USERS
        NATS <--> TRAJECTORY
    end

    subgraph SUPABASE["Supabase"]
        DB_ADMIN[("AdministrativeDataDB")]
        DB_USERS[("UsersDB")]
        DB_TRAJECTORY[("TrajectoryDB")]
    end

    FRONT -->|"HTTP /api"| INGRESS
    ADMIN --> DB_ADMIN
    USERS --> DB_USERS
    TRAJECTORY --> DB_TRAJECTORY

    classDef client fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e,stroke-width:1.5px
    classDef entry fill:#ede9fe,stroke:#7c3aed,color:#4c1d95,stroke-width:1.5px
    classDef blue fill:#dbeafe,stroke:#2563eb,color:#1e3a8a,stroke-width:2px
    classDef green fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef broker fill:#fef3c7,stroke:#b45309,color:#78350f,stroke-width:1.5px
    classDef service fill:#f1f5f9,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef data fill:#ccfbf1,stroke:#0f766e,color:#134e4a,stroke-width:1.5px

    class FRONT client
    class INGRESS,SERVICE entry
    class BLUE blue
    class NATS broker
    class ADMIN,USERS,TRAJECTORY service
    class DB_ADMIN,DB_USERS,DB_TRAJECTORY data
```

## Organización del repositorio

Así está organizado el repositorio `devops-platform`, para que sepas dónde está cada cosa cuando el README te pida abrir un archivo o ejecutar un script.

```text
devops-platform/
├── .github/
│   └── workflows/            # Workflow de CD (cd.yml)
├── docs/
│   ├── infraestructura.md
│   ├── despliegue-avanzado-y-alertas.md   # CD, Blue-Green, alertas, carga y fallos
│   └── guia-reproducible.md               # Paso a paso completo y guion de demostración
├── helm/
│   ├── microservices/        # Incluye Gateway blue/green + Ingress
│   └── nats/
├── kubernetes/
│   └── namespace.yaml
├── monitoring/
│   ├── kube-prometheus-stack/   # Prometheus + Alertmanager (3 reglas)
│   ├── alertmanager-webhook/    # Receptor de notificaciones
│   └── gateway-metrics/         # Parche de métricas para el Gateway
├── scripts/
│   ├── deploy-stack.sh
│   ├── install-monitoring.sh
│   ├── blue-green-switch.sh
│   ├── load/                    # wrk + k6
│   └── failures/                # Escenarios de fallo
├── secrets/examples/            # Plantillas .env (sin secretos reales)
└── README.md
```

> La estructura muestra los archivos relevantes para infraestructura. Pueden existir otros archivos auxiliares generados por Helm.

## Glosario rápido

Si un término del README no te suena, búscalo aquí.

| Término | Qué es, en simple |
| --- | --- |
| **VM / Vagrant** | Una VM es un computador virtual dentro de tu computador. Vagrant es la herramienta que crea y enciende esas VM con un comando (`vagrant up`). |
| **Contenedor / imagen Docker** | Una *imagen* es una caja sellada con la aplicación y todo lo que necesita para funcionar. Un *contenedor* es esa caja en ejecución. |
| **Tag** | La etiqueta de versión de una imagen, por ejemplo `sha-6741a34` (las 7 primeras letras del commit que la generó). |
| **GHCR** | *GitHub Container Registry* (`ghcr.io`). La "bodega" donde se guardan las imágenes para que el clúster las descargue. |
| **Clúster / nodo / pod** | Un *clúster* es un grupo de máquinas que trabajan como una sola. Cada máquina es un *nodo*, y un *pod* es la unidad mínima que Kubernetes ejecuta (normalmente, un contenedor). |
| **Kubernetes** | El sistema que decide en qué nodo corre cada pod, vigila que sigan vivos y los reinicia si se caen. |
| **Minikube** | Un Kubernetes de un solo nodo dentro de tu VM, pensado para aprender y probar. |
| **kubectl** | La línea de comandos para hablar con Kubernetes (ver pods, leer logs, reiniciar despliegues). |
| **Helm / chart / release** | Helm es el "instalador de aplicaciones" de Kubernetes. Un *chart* es el paquete con las plantillas, y un *release* es una instalación concreta de ese paquete. |
| **Service** | La dirección estable dentro del clúster a la que llegan las peticiones, aunque los pods cambien. |
| **Ingress** | La "puerta de entrada" desde afuera del clúster; aquí, el host `gateway.local`. |
| **port-forward** | Un túnel temporal que conecta un puerto de tu máquina con un servicio del clúster, para probarlo sin exponerlo. |
| **Secret** | Un objeto de Kubernetes que guarda datos sensibles (contraseñas, claves) fuera de las imágenes y del repositorio. |
| **API Gateway** | El servicio que recibe todas las peticiones de afuera y las reparte a los microservicios correctos. |
| **NATS** | El sistema de mensajes por el que el Gateway y los microservicios se hablan entre sí. |
| **Rolling update** | Actualizar una aplicación reemplazando sus pods poco a poco, sin apagarla toda a la vez. |
| **Blue-Green** | Mantener dos copias completas (azul y verde), probar la nueva mientras la otra atiende, y cambiar el tráfico de una a otra. Si algo falla, se vuelve atrás al instante. |
| **CI / CD** | *Integración continua*: probar y empaquetar el código automáticamente en cada cambio. *Entrega continua*: desplegar automáticamente lo que ya pasó las pruebas. |
| **Pipeline** | La secuencia automática de pasos por los que pasa el código (probar, construir la imagen, publicarla, desplegarla). |
| **GitHub Actions / runner** | GitHub Actions ejecuta el pipeline. Un *runner* es el computador temporal donde se ejecuta; uno *self-hosted* es una máquina propia registrada en el repositorio. |
| **Pull request (PR)** | La propuesta de unir los cambios de una rama con otra, que otra persona revisa y aprueba antes del *merge*. |
| **Ruleset** | Las reglas de protección de una rama en GitHub (por ejemplo, exigir un PR aprobado y checks en verde). |
| **Prometheus / Grafana / Alertmanager** | Prometheus recoge y guarda métricas. Grafana las dibuja en paneles. Alertmanager avisa cuando una métrica pasa un límite. |

## Qué necesitas y qué entrega el equipo

### Lo que debes instalar o tener

| Requisito | Versión de referencia | Nota |
| --- | --- | --- |
| Computador con virtualización | 16 GB de RAM recomendados | La VM usa 12 GB (ver sección 1) |
| VirtualBox y Vagrant | Los de tu curso | Solo si usas VM; en una Ubuntu 22.04 nativa no hacen falta |
| VM Ubuntu 22.04 | 4 vCPU y 12 GB de RAM | Referencia de la sección 1 |
| Docker, Minikube, kubectl y Helm | 29.8.1, 1.39.0, la de Minikube y 3.22.1 | Instrucciones en la sección 1 |
| Git y curl | Cualquiera reciente | Se instalan con `apt` en la sección 1 |
| Node.js | 22 | Solo para el frontend (sección 5) |
| Internet | Estable | Se descargan imágenes, paquetes de npm y charts |
| Cuenta de GitHub | Con una llave SSH registrada, para los clones por SSH de las secciones 1 y 5 | Si prefieres no usar SSH, clona por HTTPS (los repositorios son públicos) |

### Material que entrega el equipo

Hay datos que **no están en el repositorio a propósito**, porque son credenciales. El equipo los entrega aparte. Sin ellos no se puede probar el flujo completo.

| # | Material | Para qué se usa | Cómo se entrega | Dónde se usa |
| --- | --- | --- | --- | --- |
| 1 | Acceso a los 6 repositorios de la organización `CloudComputingDevOps` | Clonar el código y los scripts | Los seis repositorios son **públicos**: `devops-platform` (scripts, charts de Helm y CD), `Gateway`, `Users-Microservice`, `Administrative-Data-Microservice`, `Trajectory-Microservice` y `Frontend`. La guía los clona por SSH (requiere cuenta de GitHub con llave SSH); si no tienes llave, usa la dirección HTTPS equivalente, por ejemplo `https://github.com/CloudComputingDevOps/devops-platform.git`. | Secciones 1, 3, 5 y 11 |
| 2 | Una **carpeta** con los tres archivos `administrative-data.env`, `users.env` y `trajectory.env` ya rellenados | Credenciales de las bases, de Cloudinary, de Supabase y de Resend | El equipo entrega la carpeta al profesor por separado, **nunca dentro del repositorio**. Ver "Colocar la carpeta entregada" abajo. | Sección 2 |
| 3 | Acceso a las tres bases PostgreSQL de Supabase (Users, Administrative Data y Trajectory) | El backend consulta estas bases. **Ya existen en la nube con su esquema y sus datos**, así que no hay que crear tablas ni cargar scripts: los repositorios solo traen `prisma/schema.prisma`, que es la capa de Prisma (el ORM) entre el código y la base, no la base misma. | Las cadenas de conexión (`DATABASE_URL`) y las claves van dentro de los `.env` de la fila 2. No hay nada más que instalar. | Sección 2 |
| 4 | Archivo `frontend.env.local` con los tres valores públicos del frontend: `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY` | Que el frontend se conecte al Gateway y a Supabase | Va **dentro de la misma carpeta entregada** que los `.env` del backend. | Sección 5 |
| 5 | Usuario de pruebas del frontend (correo y contraseña) | Probar inicio de sesión y una operación real | Va **dentro de la misma carpeta entregada**, en un archivo `usuarios-prueba.txt` con el correo y la contraseña de cada usuario. | Sección 5 |
| 6 | Token de GitHub de solo lectura (**opcional**) | Que el exportador del monitoreo lea las ejecuciones de GitHub Actions | No se entrega. Los repositorios son públicos, así que el monitoreo arranca sin token; solo hace falta si algún repositorio fuera privado. | Sección 6 |

**Colocar la carpeta entregada.** Los tres archivos `.env` tienen que quedar dentro de la VM, en `~/secrets/devops`, que es donde los busca la sección 2 y el despliegue.

1. En Windows, copia la carpeta entregada dentro de la carpeta donde está el `Vagrantfile`. La VM comparte esa carpeta y la verás en `/vagrant`.
2. Dentro de la VM, reemplaza `NOMBRE_DE_LA_CARPETA` por el nombre de la carpeta que recibiste:

```bash
ls /vagrant
mkdir -p "$HOME/secrets/devops"
cp /vagrant/NOMBRE_DE_LA_CARPETA/*.env "$HOME/secrets/devops/"
chmod 700 "$HOME/secrets/devops"
chmod 600 "$HOME/secrets/devops"/*.env
ls -l "$HOME/secrets/devops"
```

- `ls /vagrant` confirma que ves la carpeta compartida con tus archivos.
- `mkdir -p` crea la carpeta de destino dentro de la VM.
- `cp ... *.env` copia los tres archivos al destino.
- `chmod 700` y `chmod 600` dejan la carpeta y los archivos legibles solo por tu usuario, porque contienen credenciales.
- El último `ls -l` debe mostrar **tres archivos** con permisos `-rw-------`.

Si `ls /vagrant` sale vacío, la carpeta compartida no está activa. En ese caso, crea primero la carpeta de destino dentro de la VM con `mkdir -p "$HOME/secrets/devops"`, y desde PowerShell, en la carpeta del `Vagrantfile`, sube cada archivo con `vagrant upload`, por ejemplo `vagrant upload .\NOMBRE_DE_LA_CARPETA\users.env /home/vagrant/secrets/devops/users.env`, y lo mismo con los otros dos. Si trabajas en Ubuntu nativo, copia los tres archivos con `cp` a `~/secrets/devops`.

Cuando llegues a la sección 2, el bucle con `cp -n` **no sobrescribe** estos archivos, y puedes saltar los `nano`: solo comprueba que no falte ninguno.

## Guía de levantamiento en Minikube

Guía para reproducir el proyecto en una VM Ubuntu. El backend corre en Kubernetes con NATS, un API Gateway y los servicios Administrative Data, Users y Trajectory. Helm instala sus imágenes de GHCR. El frontend Next.js se ejecuta desde su propio repositorio.

**Meta de la primera sesión:** abrir el frontend, confirmar una consulta real al backend y, si alcanza el tiempo, abrir Grafana. Reserva los ensayos de carga, fallos y CD para después de comprobar el flujo base.

| Tiempo orientativo | Resultado |
| --- | --- |
| 0–10 min | Acceso a los repos, credenciales y Minikube listos |
| 10–25 min | NATS, Gateway y microservicios desplegados |
| 25–40 min | Ruta funcional comprobada y frontend abierto |
| 40–60 min | Monitoreo instalado y dashboard accesible |

La estimación supone una VM preparada, bases con esquema y datos de prueba, credenciales válidas y acceso a las imágenes. Crear la VM, provisionar las bases o resolver permisos de GHCR puede extender la primera sesión. Los tiempos son estimados a partir de la configuración y los límites de los scripts.

## 1. Preparar la VM

Usa Ubuntu 22.04 como referencia. El entorno documentado tenía 4 vCPU y 12 GB de RAM para la VM, Docker 29.8.1, Minikube 1.39.0, Kubernetes 1.37.0 y Helm 3.22.1. Toma las versiones como referencia de la práctica.

Si tu VM Vagrant ya existe, ejecuta esto desde Windows, en la carpeta de su `Vagrantfile`:

```powershell
vagrant status
vagrant up
vagrant ssh
```

Desde aquí, ejecuta los comandos en Ubuntu, con el usuario normal que administra Minikube. Instala las utilidades básicas si faltan:

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates gettext-base
docker info --format '{{.ServerVersion}}'
minikube version
kubectl version --client
helm version --short
```

Si Docker responde con `permission denied` y tu usuario de laboratorio debe administrarlo, agrégalo al grupo `docker` y vuelve a iniciar sesión en la VM. Si Docker, Minikube, kubectl o Helm faltan, instálalos antes de empezar. [Docker en Ubuntu](https://docs.docker.com/engine/install/ubuntu/) · [Minikube](https://minikube.sigs.k8s.io/docs/start/) · [kubectl en Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) · [Helm](https://helm.sh/docs/intro/install/)

Clona la rama `main` con una cuenta de GitHub que pueda leer el repo. Este ejemplo usa SSH. Puedes usar HTTPS con tu autenticación habitual de GitHub.

```bash
git clone --branch main git@github.com:CloudComputingDevOps/devops-platform.git
cd devops-platform
git rev-parse --short HEAD
```

Para un perfil nuevo:

```bash
minikube start --driver=docker --cpus=4 --memory=8192
kubectl config use-context minikube
kubectl config current-context
kubectl wait --for=condition=Ready node/minikube --timeout=120s
kubectl get nodes -o wide
```

Si ya tienes el perfil `minikube`, arráncalo con `minikube start` si está detenido y conserva sus recursos. Verifica que el contexto activo sea el del clúster de laboratorio antes de ejecutar comandos de despliegue.

## 2. Preparar bases y credenciales

Consigue las tres cadenas PostgreSQL del entorno de pruebas, las credenciales Cloudinary de Administrative Data y Users, las claves de Supabase para Users y la clave de Resend de Administrative Data. Confirma que las bases sean accesibles desde la VM y que tengan el esquema esperado por **los tags de imagen que vas a desplegar**. Los scripts de infraestructura no ejecutan migraciones. Las imágenes revisadas generan el cliente Prisma durante el build y arrancan la aplicación en runtime. Si te entregan bases vacías, coordina con el equipo la creación del esquema y los datos iniciales antes de probar la API.

Crea archivos privados fuera de Git. `cp -n` conserva los archivos que ya tengas preparados.

```bash
export SECRETS_DIR="$HOME/secrets/devops"
umask 077
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

for service in administrative-data users trajectory; do
  cp -n "secrets/examples/$service.env.example" "$SECRETS_DIR/$service.env"
  chmod 600 "$SECRETS_DIR/$service.env"
done

nano "$SECRETS_DIR/administrative-data.env"
nano "$SECRETS_DIR/users.env"
nano "$SECRETS_DIR/trajectory.env"
```

| Archivo | Configuración |
| --- | --- |
| `administrative-data.env` | `DATABASE_URL`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`, `RESEND_API_KEY`. Ajusta también los valores públicos descritos abajo. |
| `users.env` | `DATABASE_URL`, `DATABASE_KEY`, `DATABASE_ADMIN_KEY`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`. Las claves Supabase deben corresponder al proyecto que use Users. |
| `trajectory.env` | `DATABASE_URL` de Trajectory. |

**Los valores de `env` del chart tienen prioridad sobre las mismas claves de `envFrom`.** Si cambias de Supabase, Cloudinary o remitente, revisa también `helm/microservices/values.yaml`. Ahí se definen `SUPABASE_URL` y `REDIRECT_URL` para Users, `CLOUDINARY_NAME` para los servicios que lo usan y `EMAIL_FROM` y `EMAIL_FROM_ADDRESS` para Administrative Data. Elimina de las plantillas copiadas las claves duplicadas que configura Helm, o alinea sus valores para evitar confusión. Users incluye variables extra de correo en su plantilla que su esquema actual no exige. Mantén un `CLAVE=valor` por línea y permisos privados.

## 3. Desplegar con el script base

### Instalación nueva con imágenes que el clúster puede descargar

Desde la raíz:

```bash
SECRETS_DIR="$HOME/secrets/devops" bash scripts/deploy-stack.sh
```

El script aplica el namespace `devops`, intenta habilitar el Ingress de Minikube, crea los tres Secrets, instala NATS y ejecuta `helm lint` y `helm upgrade --install` para el backend. También elimina un Deployment antiguo llamado `gateway`, si existe, antes de instalar `gateway-blue` y `gateway-green`.

Por defecto hay dos réplicas de cada microservicio de negocio y dos por cada color del Gateway. Ambos colores arrancan con la misma imagen, el Service `gateway` selecciona `blue`, y el Ingress responde a `gateway.local`. El Service es `NodePort`, con puerto interno 3000 y puerto de nodo 30080. Los tres servicios de negocio se comunican por NATS en `nats://nats:4222`.

**En un clúster con releases previos**, revisa primero `helm list -n devops` y `bash scripts/blue-green-switch.sh status`. El script base reaplica los valores versionados y puede restaurar los tags iniciales y el selector `blue`. Para retomar una instalación ya configurada, inicia Minikube y verifica el estado. Para actualizar imágenes, usa el flujo de la sección 8.

### Si GHCR exige autenticación

Para imágenes privadas, el clúster necesita un Secret de pull. Un `docker login` en la VM autoriza al cliente Docker de la VM. Configura además el Secret en Kubernetes y referencia su nombre desde el chart. Usa un token autorizado para leer los paquetes y, si la organización aplica SSO, autorízalo también allí. [Autenticación de GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry)

```bash
kubectl apply -f kubernetes/namespace.yaml
read -rp 'Usuario de GitHub: ' GHCR_USER
read -rsp 'Token de lectura de paquetes: ' GHCR_TOKEN
printf '\n'
( umask 077
  cfg="$(mktemp -d)"
  trap 'rm -rf "$cfg"' EXIT
  printf '%s' "$GHCR_TOKEN" |
    docker --config "$cfg" login ghcr.io -u "$GHCR_USER" --password-stdin &&
    kubectl -n devops create secret generic ghcr-pull \
      --type=kubernetes.io/dockerconfigjson \
      --from-file=.dockerconfigjson="$cfg/config.json" \
      --dry-run=client -o yaml | kubectl apply -f -
)
unset GHCR_TOKEN
kubectl -n devops get secret ghcr-pull
```

En la copia local de `helm/microservices/values.yaml`, cambia `imagePullSecrets: []` por:

```yaml
imagePullSecrets:
  - name: ghcr-pull
```

Esto permite que el script base instale el pull Secret en la especificación de los Deployments. Si ya existe el release, aplica el ajuste conservando tags y color:

```bash
ACTIVE="$(kubectl -n devops get svc gateway -o jsonpath='{.spec.selector.version}')"
case "$ACTIVE" in
  blue|green)
    helm upgrade microservices ./helm/microservices -n devops --reuse-values \
      --set "blueGreen.activeColor=$ACTIVE" \
      --set 'imagePullSecrets[0].name=ghcr-pull' --wait --timeout 10m
    ;;
  *) printf 'Selector inesperado: %s\n' "$ACTIVE" >&2 ;;
esac
```

Si un tag de `values-images.yaml` fue retirado, obtén uno publicado y compatible con el entorno. Para un primer despliegue, actualiza el tag del servicio en `values-images.yaml`. Para el Gateway blue-green los tags efectivos son `blueGreen.blue.tag` y `blueGreen.green.tag` en `values.yaml`.

## 4. Comprobar el backend

```bash
helm list -n devops
kubectl -n devops get deploy,pods,svc,ingress
kubectl -n devops get endpointslice -l kubernetes.io/service-name=gateway
bash scripts/blue-green-switch.sh status

for deployment in gateway-blue gateway-green administrative-data users trajectory; do
  kubectl -n devops rollout status "deployment/$deployment" --timeout=90s
done
```

Confirma que NATS está disponible y que `gateway` tiene endpoints del color activo. Después prueba una operación real: los pods pueden figurar como `Running` incluso si una consulta al servicio o a su base falla.

### Prueba rápida desde la VM

Deja esto abierto en una terminal:

```bash
kubectl -n devops port-forward --address 127.0.0.1 svc/gateway 3000:3000
```

En otra terminal de la VM:

```bash
curl -i --max-time 10 http://localhost:3000/
curl -i --max-time 10 http://localhost:3000/api/docs
curl -fsS --max-time 15 http://localhost:3000/api/areas
```

La raíz y Swagger permiten revisar que el Gateway responde. Usa la consulta de áreas para verificar el flujo HTTP, NATS y Administrative Data. Espera HTTP 2xx y un cuerpo coherente con los datos de prueba. Si la versión requiere autenticación, verifica los requisitos en Swagger y repite con un token de usuario de pruebas. Un 401/403 sirve para diagnosticar autenticación, pero deja pendiente la verificación funcional.

### Comprobar Ingress desde la VM

```bash
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
kubectl -n devops get ingress
curl --noproxy '*' --resolve "gateway.local:80:$(minikube ip)" \
  -i --max-time 10 http://gateway.local/api/areas
```

`--resolve` prueba el host correcto sin editar `/etc/hosts`. Si el controlador no existe, ejecuta `minikube addons enable ingress` y vuelve a comprobarlo. Si el port-forward funciona y el Ingress no responde, puedes continuar con el frontend mediante el port-forward y luego revisar la conectividad del addon.

## 5. Abrir el frontend

El overlay de imágenes menciona `frontend`, pero en la rama revisada esa entrada solo tiene imagen y tag. Como el chart requiere puerto para crear un Deployment y `http` para crear un Service, el script base no arranca el frontend. Para la primera sesión úsalo en el host donde abrirás el navegador. El repo usa Node 22 en CI y Next.js escucha en 5173. [Repositorio del frontend](https://github.com/CloudComputingDevOps/Frontend)

**Si el frontend corre en Windows y el backend en Vagrant**, deja abierto el port-forward de la VM de la sección 4. Desde PowerShell, en la carpeta del `Vagrantfile`, abre un túnel SSH en otra terminal:

```powershell
vagrant ssh -- -N -L 3000:127.0.0.1:3000
```

Desde una segunda terminal de Windows verifica `curl.exe -i http://localhost:3000/api/areas`. Si el puerto 3000 de Windows está ocupado, usa `-L 3005:127.0.0.1:3000` y cambia la URL del API del frontend a `http://localhost:3005/api`. Si ejecutas el frontend y el navegador en Ubuntu, el port-forward local es suficiente.

Desde el host del frontend:

```bash
git clone --branch main git@github.com:CloudComputingDevOps/Frontend.git
cd Frontend
node --version
npm ci
```

Si el equipo te entregó el archivo `frontend.env.local` en la carpeta de credenciales, cópialo a la raíz de `Frontend` con el nombre `.env.local` y salta la creación manual de abajo. Desde la raíz de `Frontend`: `cp /vagrant/NOMBRE_DE_LA_CARPETA/frontend.env.local .env.local` (ajusta la ruta a donde esté el archivo en tu equipo).

Crea `.env.local` en la raíz de `Frontend` con valores reales:

```dotenv
NEXT_PUBLIC_API_URL=http://localhost:3000/api
NEXT_PUBLIC_SUPABASE_URL=https://TU_PROYECTO.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY=TU_CLAVE_PUBLICA
```

Usa la URL de Supabase configurada para Users y una clave publicable de ese proyecto. El prefijo `NEXT_PUBLIC_` expone esos valores al navegador, así que reserva la clave administrativa para el backend. Si cambias las variables, reinicia el proceso de desarrollo. Para una imagen de producción se pasan como argumentos de build de `dockerfile.prod`.

```bash
npm run dev
```

Abre **http://localhost:5173**. Usa exactamente ese origen para que coincida con el CORS revisado del Gateway. Para probar inicio de sesión o registro, usa usuarios de pruebas y confirma los redirects permitidos en Supabase. El backend configura por defecto `REDIRECT_URL=http://localhost:5173/signup` para Users.

## 6. Instalar monitoreo

Desde `devops-platform`, tras levantar el backend:

```bash
SECRETS_DIR="$HOME/secrets/devops" bash scripts/install-monitoring.sh
kubectl -n monitoring get pods,svc,prometheusrule
kubectl -n devops get servicemonitor gateway
```

Este script instala Alertmanager, Prometheus, Grafana, Pushgateway, un webhook local y un exportador que consulta ejecuciones de GitHub Actions. También carga el dashboard **Plataforma DevOps: aplicacion y pipeline**. Para el primer arranque basta el webhook. Para repos privados, el exportador necesita un token con acceso de lectura a los repos y ejecuciones correspondientes. Puedes introducirlo sin dejarlo en el historial y limitarlo a la ejecución del instalador:

```bash
read -rsp 'Token de lectura de GitHub: ' GITHUB_TOKEN
printf '\n'
GITHUB_TOKEN="$GITHUB_TOKEN" SECRETS_DIR="$HOME/secrets/devops" bash scripts/install-monitoring.sh
unset GITHUB_TOKEN
```

Abre cada port-forward en una terminal separada de la VM:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3001:80
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

| Interfaz | Dirección local | Qué comprobar |
| --- | --- | --- |
| Grafana | `http://localhost:3001` | Usuario y contraseña iniciales `admin / admin` en el laboratorio. Busca el dashboard del proyecto. |
| Prometheus | `http://localhost:9090/targets` | Revisa los targets y abre `/alerts` para consultar reglas. |
| Alertmanager | `http://localhost:9093` | Consulta alertas notificadas. |
| Webhook | `kubectl -n monitoring logs deploy/alertmanager-webhook -f` | Revisa cuándo se recibe la notificación. |

Para ver Grafana desde Windows con Vagrant, conserva el port-forward de la VM y ejecuta `vagrant ssh -- -N -L 3001:127.0.0.1:3001`. Aplica el mismo patrón para 9090 y 9093 si los necesitas.

**Métricas HTTP del Gateway:** `curl -i http://localhost:3000/api/metrics` debe devolver métricas Prometheus. Si el target Gateway falla con 404, comprueba que la imagen desplegada incluya el módulo de métricas. El repo proporciona `monitoring/gateway-metrics/gateway-metrics.patch` para integrarlo en el repo Gateway y publicar una imagen compatible.

**Correo opcional:** copia `secrets/examples/alertmanager.env.example` a `$SECRETS_DIR/alertmanager.env`, configura el SMTP y vuelve a ejecutar el instalador con `umask 077`. El instalador carga ese archivo como Bash y genera `monitoring/kube-prometheus-stack/values-email.generated.yaml` con la configuración SMTP. Mantén ese YAML fuera de los commits, evita mostrar sus valores y elimina la copia generada cuando termines. [Configuración de monitoreo del repo](https://github.com/CloudComputingDevOps/devops-platform/blob/main/monitoring/README.md)

## 7. Pruebas opcionales para la sustentación

Primero confirma que la ruta elegida responde 2xx. Con el port-forward del Gateway abierto:

```bash
BASE_URL=http://localhost:3000 REQUEST_PATH=/api/areas VUS=10 DURATION=30s \
  bash scripts/load/run-k6.sh

BASE_URL=http://localhost:3000 PATH_SUFFIX=/api/areas THREADS=2 CONNECTIONS=20 DURATION=30s \
  bash scripts/load/run-wrk.sh
```

Instala `k6` o `wrk` si vas a usar esa prueba. `wrk` está disponible con `sudo apt-get install -y wrk` en Ubuntu. El wrapper de k6 imprime las instrucciones de instalación si detecta que falta. Los scripts escriben resúmenes en `scripts/load/results/`. Los umbrales de k6 permiten cierta tasa de fallos. Para demostrar continuidad, registra el color inicial y final y revisa explícitamente errores de conexión, HTTP y latencia.

**Cambio de color bajo carga:** ejecuta esta prueba con Ingress operativo o con un acceso NodePort estable. Un port-forward al Service puede quedar conectado al pod original durante la transición y dar una evidencia engañosa.

```bash
bash scripts/blue-green-switch.sh status
# Usa green si el color actual es blue. Si ya es green, usa blue.
BASE_URL=http://gateway.local TOOL=k6 DURATION_SEC=30 SWITCH_AT=10 \
  bash scripts/load/blue-green-during-load.sh green
bash scripts/blue-green-switch.sh status
```

Para usar `gateway.local` en el script, configura la IP devuelta por `minikube ip` en `/etc/hosts` de la VM. Este ensayo modifica directamente el selector del Service. Verifica el cambio aunque la carga termine con código cero, dado que el wrapper no propaga un fallo del switch. Una ejecución posterior de Helm puede volver a aplicar el color guardado en la release.

**Alerta de fallos de pipeline:** ejecuta en el entorno de laboratorio, con monitoreo activo, y espera el tiempo de evaluación y agrupación de la alerta:

```bash
bash scripts/failures/simulate-failures.sh list
bash scripts/failures/simulate-failures.sh build-fail
# Verifica BuildFallidoConsecutivo en Prometheus y en los logs del webhook.
bash scripts/failures/simulate-failures.sh restore-build-fail
```

`pod-down` escala Users a cero. Como `PodCaido` evalúa métricas de pods existentes, al desaparecer esos pods el comando puede no generar la alerta esperada. Además, `restore-pod-down` fija una réplica aunque el chart inicial usa dos. Si ensayas ese caso, registra el número original de réplicas y restáuralo explícitamente al terminar.

## 8. Actualizar y recuperar

### Gateway con Blue-Green

Usa un tag que ya exista en GHCR y una ruta pública 2xx que esté incluida en la imagen candidata. El script conserva los valores de la release, actualiza el color inactivo, espera el rollout, verifica la referencia de imagen, hace un smoke test directo al candidato y luego cambia el selector mediante Helm.

```bash
bash scripts/blue-green-switch.sh status
read -rp 'Tag publicado del Gateway: ' GATEWAY_TAG
SMOKE_PATH=/ bash scripts/blue-green-release.sh "$GATEWAY_TAG"
bash scripts/blue-green-switch.sh status
```

Si la raíz devuelve 404 en la imagen candidata, indica otra ruta pública confirmada mediante `SMOKE_PATH`. Si 18080 está ocupado, define `SMOKE_LOCAL_PORT`. Después del cambio repite la prueba funcional de la sección 4. Para volver al color anterior cuando ese Deployment sigue listo, persiste el selector con Helm:

```bash
# Ejemplo: el color anterior era blue.
kubectl -n devops rollout status deployment/gateway-blue --timeout=180s
helm upgrade microservices ./helm/microservices -n devops --reuse-values \
  --set blueGreen.activeColor=blue --wait --timeout 5m
bash scripts/blue-green-switch.sh status
```

### CI/CD del proyecto

El workflow `.github/workflows/cd.yml` valida Helm y los scripts en un runner hospedado y despliega en un runner `self-hosted`. Para habilitarlo, registra el runner con acceso al repo y comprueba, **con el usuario que ejecuta el runner**, que el contexto Kubernetes, Helm y los Secrets de `devops` están disponibles. En la configuración estándar, el job busca los archivos de credenciales en `~/secrets/devops` del usuario del runner y exige que existan los tres Secrets en el clúster.

- Los repos que publican imágenes pueden enviar `repository_dispatch` con `event_type: deploy-service` y `client_payload.service` y `client_payload.tag`. Usa `gateway`, `administrative-data`, `users` o `trajectory` como servicio.
- El Gateway usa `blue-green-release.sh`. Los tres servicios de negocio aplican un rolling update con el tag recibido.
- Un push a `main`, `develop` o `dp` en las rutas configuradas reconcilia el release existente conservando sus valores. El modo manual `rolling` sin payload también reconcilia. Para publicar un tag nuevo de un microservicio de negocio usa el dispatch.
- El modo manual `blue-green` requiere `gateway_tag`. El modo `full-stack` vuelve a ejecutar los instaladores y puede restablecer versiones. En una VM nueva, la ruta de las secciones 1–4 es la más directa: el workflow exige los Secrets antes de alcanzar el paso `full-stack`.
- `run_load_verification` realiza otro cambio de color durante la prueba. Déjalo desmarcado si solo quieres validar la versión recién activada.

[Workflow CD](https://github.com/CloudComputingDevOps/devops-platform/blob/main/.github/workflows/cd.yml) · [Despliegue avanzado y alertas](https://github.com/CloudComputingDevOps/devops-platform/blob/main/docs/despliegue-avanzado-y-alertas.md)

## 9. Diagnóstico y cierre

| Síntoma | Qué revisar |
| --- | --- |
| `CreateContainerConfigError` | Ejecuta `kubectl -n devops describe pod NOMBRE` y verifica que el Secret esperado existe. |
| `ImagePullBackOff` | Revisa eventos, acceso a GHCR, tag, configuración de `imagePullSecrets` y arquitectura de la imagen. |
| `CrashLoopBackOff` | Usa `kubectl -n devops logs POD --previous --tail=80`. Busca errores de validación, DB o NATS. |
| Se corrigió un Secret pero el pod sigue fallando | Reinicia el Deployment que consume ese Secret con `kubectl -n devops rollout restart deploy/NOMBRE` y comprueba el rollout. Las variables se leen al arrancar el contenedor. |
| Gateway responde, pero `/api/areas` falla | Revisa Swagger, logs de Gateway y Administrative Data, conexión a NATS y permisos/esquema de la base. |
| `gateway.local` falla, pero port-forward funciona | Verifica addon, host de Ingress y resolución desde la VM. |
| Frontend abre, pero las peticiones fallan | Revisa DevTools → Network. Confirma `NEXT_PUBLIC_API_URL`, el túnel y el origen `http://localhost:5173`. |
| Helm marca timeout | Consulta `kubectl -n devops get events --sort-by=.lastTimestamp` y `helm history microservices -n devops` antes de repetir. |
| Grafana no muestra latencia ni errores HTTP | Confirma `/api/metrics` en Gateway y el estado del target en Prometheus. |

Para pausar el laboratorio, cierra los port-forwards, túneles y el servidor de Next.js con `Ctrl+C`. Ejecuta `minikube stop` para apagar el clúster y conservar su estado. Para retomar, inicia Minikube y repite la comprobación de la sección 4.

Guía contrastada con los scripts y manifiestos de la rama `main`, la configuración de entorno de los servicios y el Dockerfile del frontend. Se comprobó la sintaxis de los nueve scripts Bash con `bash -n`. El despliegue y la duración quedan por verificar en una VM con acceso a los paquetes y a los servicios externos.


## 10. Integración continua y control de versiones (R1.1 y R1.2)

Las secciones 1 a 9 levantan la plataforma usando imágenes que **ya están publicadas** en GHCR. Esta sección explica cómo llegan ahí: qué ramas existen, qué reglas las protegen, qué hace el pipeline en cada cambio y cómo avisa al CD. No necesitas hacerla para levantar la plataforma, pero sí si quieres entender o reproducir el flujo de desarrollo.

```mermaid
flowchart LR
    DEV["Push o Pull Request<br/>a develop o main"] --> BT["Build y Test<br/>npm ci, test, build"]
    BT -->|"pasan"| IMG["Imagen Docker<br/>build y push a GHCR"]
    BT -.->|"falla una prueba"| STOP["Se bloquea el merge"]
    IMG -->|"solo push a main"| CD["Notificar CD<br/>repository_dispatch"]
    CD --> PLAT["devops-platform<br/>Helm y Blue-Green"]

    classDef ok fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:1.5px
    classDef bad fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.5px
    classDef step fill:#f1f5f9,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    class BT,IMG,CD step
    class STOP bad
    class PLAT ok
```

### 10.1 Ramas y políticas de merge

| Rama | Propósito |
| --- | --- |
| `main` | Código estable, listo para desplegar. Solo recibe Pull Requests desde `develop`. |
| `develop` | Integración del trabajo. Cada push dispara el pipeline completo. |
| `feature/*` | Una rama por cambio. Se elimina después de fusionar (solo estas se borran, nunca `main` ni `develop`). |

Los mensajes de commit siguen el formato `tipo: descripcion`, con los tipos `feat`, `fix`, `test`, `docs`, `ci` y `chore`. La convención está en `CONTRIBUTING.md` y cada Pull Request usa la plantilla `.github/pull_request_template.md`, ambos presentes en los cinco repositorios.

### 10.2 Reglas de protección (ruleset)

Cada repositorio tiene el ruleset `proteger-main-y-develop`, aplicado a las ramas `main` y `develop`:

- No se pueden eliminar las ramas.
- No se permite force push.
- Todo cambio entra por Pull Request con **1 aprobación**. Quien abre el PR no puede aprobar el suyo, así que lo aprueba otra persona.
- Los checks **Build y Test** e **Imagen Docker** deben estar en verde para fusionar.

**Evidencia:** un `git push origin develop` directo es rechazado con `GH013: Repository rule violations found for refs/heads/develop`, con los motivos *Changes must be made through a pull request* y *2 of 2 required status checks are expected*.

### 10.3 El pipeline (`.github/workflows/ci.yml`)

Se activa con `pull_request` y con `push` sobre `main` y `develop`. Cada repositorio de backend y el frontend tiene su propio `ci.yml`; el de Gateway sirve de referencia.

| Job | Qué hace | Cuándo corre |
| --- | --- | --- |
| **Build y Test** | Checkout, Node 22, `npm ci`, `npx prisma generate` (solo si existe `prisma/schema.prisma`), lint informativo, `npm test` y `npm run build` | En cada PR y cada push |
| **Imagen Docker** | Construye la imagen con `dockerfile.prod`, inicia sesión en `ghcr.io` y la publica | En cada PR y push, pero **solo publica** cuando no es un PR. Solo corre si Build y Test pasó. |
| **Notificar CD centralizado** | Envía un `repository_dispatch` al repositorio `devops-platform` (ver 10.5) | Solo en push a `main`, y únicamente en los 4 servicios de backend |

Decisiones de diseño:

- **Dos jobs encadenados.** Si una prueba falla, la imagen ni se construye. Ahorra tiempo y evita publicar código roto. En el PR de demostración (`feature/demo-test-fallido`), Build y Test falló en menos de 1 minuto y Imagen Docker quedó omitido.
- **Lint informativo.** El código heredado tenía 514 problemas de lint, y bloquear el pipeline por eso lo habría dejado inservible. Corre con `continue-on-error`, y queda como mejora pendiente volverlo bloqueante.
- **Pruebas mínimas.** Los repositorios no tenían pruebas ("No tests found"). Se añadió `pagination.dto.spec.ts`, con 6 pruebas del DTO de paginación, en los 4 servicios NestJS.
- **Prisma en Docker.** `prisma generate` exige una URL de base de datos al construir. Se usa una URL falsa (`postgresql://user:pass@localhost:5432/db`) como argumento de build, solo para generar el cliente. No hay credenciales reales en la imagen ni en el repositorio.
- **Caché.** El job de imagen usa caché de capas de GitHub Actions (`gha`), por eso las corridas posteriores son más rápidas que la primera.
- **Frontend.** Las variables `NEXT_PUBLIC_*` se incrustan al construir la imagen. El pipeline las toma de las *Variables* del repositorio (`vars.X`) o usa un marcador. Los valores reales se cargan en *Settings > Secrets and variables > Actions > Variables*.

### 10.4 Imágenes publicadas

Los paquetes son públicos y quedan en `ghcr.io/cloudcomputingdevops/` con estos nombres: `gateway`, `users-microservice`, `administrative-data-microservice`, `trajectory-microservice` y `frontend`.

Tags: `sha-xxxxxxx` (los 7 primeros caracteres del commit, para saber exactamente qué código contiene y poder volver atrás), el nombre de la rama (por ejemplo `develop`) y `latest` (al hacer push a `main`).

### 10.5 Aviso al CD (`notify-cd`)

Cuando un cambio llega a `main` en uno de los 4 servicios de backend, el último job envía un `repository_dispatch` al repositorio `CloudComputingDevOps/devops-platform` con:

- `event_type`: `deploy-service`
- `client_payload[service]`: `gateway`, `users`, `administrative-data` o `trajectory`
- `client_payload[image]`: la imagen en GHCR, por ejemplo `ghcr.io/cloudcomputingdevops/gateway`
- `client_payload[tag]`: `sha-` seguido de los 7 primeros caracteres del commit

El workflow `cd.yml` de `devops-platform` recibe ese evento y despliega (sección 8). Para que funcione necesita un secreto llamado `CD_DISPATCH_TOKEN`. **Nunca escribas el valor del token en el repositorio, en capturas ni en el chat.**

1. **Crear el token.** En GitHub, *Settings > Developer settings > Personal access tokens > Fine-grained tokens > Generate new token*. Elige como *Resource owner* la organización `CloudComputingDevOps`. En *Repository access* elige **Only select repositories** y marca solo `devops-platform`. En *Permissions > Repository permissions* pon **Contents: Read and write**. Pon una fecha de vencimiento. Si la organización exige aprobar tokens, un propietario debe aprobarlo.
2. **Guardarlo como secreto de la organización.** En la organización, *Settings > Secrets and variables > Actions > New organization secret*. Nombre: `CD_DISPATCH_TOKEN`. Pega el valor. En *Repository access* elige **Selected repositories** y marca los 4 de backend (`Gateway`, `Users-Microservice`, `Administrative-Data-Microservice` y `Trajectory-Microservice`).
3. **Renovarlo.** Los tokens vencen. Cuando venza, el job falla con el mensaje `Falta configurar CD_DISPATCH_TOKEN` o con un error de autorización. Genera uno nuevo y actualiza el secreto con el mismo nombre.

Si el aviso llega pero el segundo job del CD se queda en cola (*Queued*), los runners *self-hosted* de `devops-platform` están apagados. Enciéndelos y vuelve a ejecutar el job (sección 8).

### 10.6 Reproducir la configuración desde cero

Para armar este flujo en un conjunto nuevo de repositorios:

1. **Crear `develop`.** Desde `main`: `git checkout main`, `git pull`, `git checkout -b develop` y `git push -u origin develop`.
2. **Añadir los archivos del flujo** en cada repositorio: `CONTRIBUTING.md`, `.github/pull_request_template.md` y `.github/workflows/ci.yml` (copia el de Gateway y ajusta el nombre del servicio en el job de notificación).
3. **Añadir `dockerfile.prod` y `.dockerignore`** donde falten (el Frontend no los tenía).
4. **Añadir pruebas mínimas** donde no existan, para que `npm test` no falle por "No tests found".
5. **Permitir paquetes públicos.** En la organización: *Settings > Packages > Package creation > Public*. Tras la primera publicación, si un paquete aparece como privado, ábrelo en *Packages > nombre > Package settings* y cambia su visibilidad a público.
6. **Crear el ruleset en Gateway.** *Settings > Rules > Rulesets > New ruleset > New branch ruleset*. Nombre `proteger-main-y-develop`, *Enforcement status* en **Active**. En *Target branches* añade `main` y `develop`. Activa: *Restrict deletions*, *Block force pushes*, *Require a pull request before merging* (con **1** aprobación) y *Require status checks to pass* (añade `Build y Test` e `Imagen Docker`). **Los checks solo aparecen en la lista después de haber corrido al menos una vez**, así que haz primero un push de prueba a una rama `feature/*` para que se ejecuten.
7. **Exportar e importar el ruleset.** En la lista de rulesets de Gateway, usa **Export ruleset** para descargar el JSON. En cada uno de los otros repositorios, *New ruleset > Import a ruleset* y sube ese archivo. Así las reglas quedan idénticas en los cinco.
8. **Frontend.** Carga las variables `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY` en *Settings > Secrets and variables > Actions > Variables* y vuelve a hacer push.
9. **Crear el secreto `CD_DISPATCH_TOKEN`** como se explica en 10.5.

### 10.7 Comprobar que todo funciona

Estas tres pruebas demuestran los criterios de R1.1 y R1.2. Hazlas en un clon de prueba.

**Prueba A. El push directo a `develop` se rechaza.**

```bash
git checkout develop
git pull
git commit --allow-empty -m "test: push directo de prueba"
git push origin develop
```

- `git commit --allow-empty` crea un commit vacío, sin cambiar ningún archivo.
- `git push origin develop` intenta subirlo directo.

Debe aparecer `GH013: Repository rule violations found for refs/heads/develop`. Para limpiar tu copia local, ejecuta `git reset --hard origin/develop`. Esto descarta el commit de prueba, que no llegó a subirse.

**Prueba B. Una prueba rota bloquea el merge.** Crea una rama `feature/demo-test-fallido` y rompe a propósito un `expect` de una prueba. Sube la rama y abre un Pull Request hacia `develop`. Resultado esperado: **Build y Test** en rojo, **Imagen Docker** omitido y el botón de *Merge* bloqueado. Cierra el PR sin fusionar y borra la rama.

**Prueba C. Un PR correcto se fusiona y publica la imagen.** Abre un PR con un cambio pequeño. Con los dos checks en verde y la aprobación de otra persona, fusiona. Resultado esperado: en la pestaña **Actions**, el push a `develop` muestra los jobs en verde, y en *Packages* aparece la imagen con el tag `sha-` del nuevo commit.

## 11. Comparación de tiempos: manual vs. automatizado (R1.8)

La meta de R1.2 es que el pipeline tarde menos de 10 minutos. Aquí se compara contra hacer lo mismo a mano en una VM, con el servicio Gateway.

### 11.1 Resultados

**Pipeline (GitHub Actions), push a `develop`:**

| Servicio | Duración |
| --- | --- |
| Gateway | 3 min 15 s |
| Users | 5 min 23 s |
| Administrative-Data | 4 min 26 s |
| Trajectory | 4 min 08 s |
| Frontend | 5 min 23 s |
| **Máximo** | **5 min 23 s** (cumple la meta de menos de 10 minutos) |

La corrida de Gateway es la **CI #12** (commit `6741a34`, rama `develop`): Build y Test 52 s, Imagen Docker 2 min 17 s. Las corridas posteriores, con caché caliente, rondan los 2 minutos.

**Manual vs. automatizado (Gateway, mismo commit `6741a34`):**

| Paso | Manual (VM de 2 CPU) | Pipeline |
| --- | --- | --- |
| `npm ci` | 5 min 5,4 s | |
| `npm test` (6 pruebas) | 19,1 s | Build y Test: 52 s en total |
| `npm run build` | 22,5 s | |
| `docker build` (en frío) | 8 min 12,9 s | Imagen Docker: 2 min 17 s |
| **Total** | **13 min 59,9 s** | **3 min 15 s** |
| **Relación** | | **El pipeline es unas 4,3 veces más rápido** |

Una medición anterior dio 14 min 18,8 s y 13 min 56,4 s (corridas 1 y 2), consistente con ésta.

### 11.2 Por qué no es solo una cuestión de tiempo

- El pipeline corre **siempre y de la misma forma**. A mano se omiten pasos, se pega mal un comando o se olvida cambiar de rama.
- Las pruebas fallidas **bloquean** el merge. A mano depende de la disciplina de cada persona.
- Las imágenes quedan etiquetadas por commit (`sha-xxxxxxx`), lo que da trazabilidad y permite volver atrás.
- La persona queda libre mientras el robot trabaja.

### 11.3 Cómo repetir la medición manual

Usa la VM Ubuntu de la sección 1 (la de la medición tenía 2 CPU, 2,9 GB de RAM, Node 22.23.4, npm 10.9.9 y Docker 29.8.1). Cada paso se mide con `time`, que muestra cuánto tardó el comando (el valor que importa es `real`).

**Preparación (no se mide):**

```bash
cd ~
rm -rf ~/medicion ~/.npm
docker rmi gateway:manual
docker builder prune -f
mkdir -p ~/medicion
cd ~/medicion
git clone https://github.com/CloudComputingDevOps/Gateway.git
cd Gateway
git checkout develop
git log --oneline -3
```

- `rm -rf ~/medicion ~/.npm` y `docker builder prune -f` dejan todo **en frío** (sin carpeta, sin caché de npm y sin caché de capas de Docker), igual que un runner limpio de GitHub. Si `docker rmi` dice que la imagen no existe, es normal.
- `git checkout develop` y `git log` confirman que estás en la rama correcta y en el commit que quieres medir.

**Medición:**

```bash
node -v && npm -v && docker --version && nproc
time npm ci
time npm test
time npm run build
time docker build --network=host -f dockerfile.prod -t gateway:manual .
```

Anota el `real` de cada uno y súmalos. Usa `dockerfile.prod`, el mismo que usa el pipeline: el archivo `dockerfile` (sin `.prod`) es otro y da tiempos distintos.

**Limpieza al terminar:**

```bash
docker rmi gateway:manual
cd ~
rm -rf ~/medicion
```

### 11.4 Problema conocido: el `docker build` falla con `Exit handler never called`

En algunas VM de Vagrant, el contenedor hereda como DNS la dirección `10.0.2.3` de VirtualBox, que no responde desde dentro de Docker. Los síntomas son: `npm ping` dentro de un contenedor falla con `EAI_AGAIN` y el `docker build` termina con `npm error Exit handler never called!` a los ~150 s. Para comprobarlo:

```bash
docker run --rm node:22-alpine sh -c "npm ping"
docker run --rm --dns 8.8.8.8 node:22-alpine sh -c "npm ping"
```

Si el primero falla y el segundo responde `PONG`, es el DNS. Dos soluciones:

- **Solo para ese build:** usa `docker build --network=host ...` (es lo que usa el comando de 11.3). El build usa la red de la VM, donde npm sí funciona. No cambia los tiempos.
- **Para toda la VM:** crea o edita `/etc/docker/daemon.json` con `{ "dns": ["8.8.8.8", "1.1.1.1"] }` y reinicia Docker con `sudo systemctl restart docker`. Revisa antes si el archivo ya existe para no pisarlo. Reiniciar Docker detiene los contenedores en ejecución, incluido el clúster de Minikube.

### 11.5 Salvedades

- La medición manual se hizo en una VM de 2 CPU con red doméstica. Los runners de GitHub son otra máquina, así que sirve como orden de magnitud y no como medida exacta.
- El pipeline usa caché de capas de Docker y de npm. La medición manual de `npm ci` y de `docker build` fue **en frío**.
- El pipeline además publica la imagen en GHCR (inicio de sesión y subida), y a mano **no se midió** ese paso. Incluirlo aumentaría el tiempo manual.
- Solo se midió Gateway a mano. Los demás servicios tienen dependencias de tamaño parecido, pero no idéntico.
- El número de vulnerabilidades que reporta `npm ci` cambia con el tiempo (varía de una semana a otra). No uses `npm audit fix --force` a ciegas, porque puede romper el código.


