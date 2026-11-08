# Infraestructura local

## Máquina virtual

- Hipervisor: VirtualBox
- Provisionamiento: Vagrant
- Sistema operativo: Ubuntu 22.04.5 LTS
- Hostname: servidor
- IP privada Vagrant: 192.168.100.3
- CPU: 4 vCPU
- RAM configurada: 12 GB

## Herramientas

- Docker: 29.8.1
- Minikube: 1.39.0
- Kubernetes: 1.37.0
- kubectl: 1.37.0
- Helm: 3.22.1

## Kubernetes

- Driver Minikube: Docker
- Runtime: containerd
- Namespace del proyecto: devops
- Addons habilitados: ingress, metrics-server

## Comandos de verificación

```bash
docker info
minikube status
kubectl get nodes
kubectl get pods -A
helm version
```

## Consideraciones

El clúster utiliza una única VM y un nodo de Minikube.

Los despliegues del proyecto se realizarán en el namespace
devops para mantenerlos separados de otras prácticas.
