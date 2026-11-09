# DevOps Platform

Plataforma DevOps para el despliegue y monitoreo de una
arquitectura de microservicios con Kubernetes.

## Arquitectura

La aplicación está compuesta por cuatro servicios:

- API Gateway
- Users Service
- Products Service
- Orders Service

Cada servicio tiene su propio repositorio y pipeline de CI.

## Tecnologías

- NestJS y TypeScript
- Docker
- GitHub Actions
- GitHub Container Registry (GHCR)
- Kubernetes (Minikube)
- Helm
- Prometheus
- Grafana
- Alertmanager

## Infraestructura

Entorno de despliegue:

- Ubuntu 22.04 LTS
- Vagrant + VirtualBox
- Docker
- Minikube con driver Docker
- Kubernetes v1.37.0
- Helm 3

## Flujo CI/CD

1. Se realiza un push o pull request en un microservicio.
2. GitHub Actions ejecuta las pruebas y construye la imagen.
3. La imagen se publica en GHCR con un tag identificable.
4. Se actualiza la referencia de imagen en este repositorio.
5. El runner self-hosted ejecuta el despliegue con Helm.
6. Kubernetes realiza un rolling update.
7. Se verifica el estado del despliegue.

## Estructura

- .github/workflows: pipelines de CD.
- helm: charts y valores de despliegue.
- kubernetes: manifiestos complementarios.
- monitoring: configuración de observabilidad.
- scripts: scripts de automatización.
- docs: documentación y evidencias.

## Estado del proyecto

- [x] Docker instalado.
- [x] Minikube configurado.
- [x] Kubernetes operativo.
- [x] Helm instalado.
- [x] Namespace devops creado.
- [ ] Despliegue de microservicios.
- [ ] Runner self-hosted.
- [ ] Pipeline CD.
- [ ] Monitoreo y alertas.
- [ ] Blue-Green Deployment.
