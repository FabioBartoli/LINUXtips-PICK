#!/bin/bash

# Instalando o Harbor
kubectl config set-context --current --namespace=harbor
helm install harbor harbor/harbor --set expose.type=clusterIP --set expose.tls.auto.commonName=fabiobartoli.com.br \
    --set persistence.enabled=false --set externalURL=https://harbor.fabiobartoli.com.br \
    --set fullnameOverride=harbor-harbor --set trivy.enabled=true --namespace harbor 
# Instalando o Kube-Prometheus
kubectl config set-context --current --namespace=monitoring
helm install kube-prometheus prometheus-community/kube-prometheus-stack
# Ajustando a captura de logs do Kubeadm
kubectl apply -f /home/ubuntu/LINUXtips-PICK/monitoring/proxy-prometheus.yaml
# Instalando o Kyverno
kubectl config set-context --current --namespace=default
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
# Criando Regras do Kyverno
kubectl apply -f /home/ubuntu/LINUXtips-PICK/security/kyverno/
# Instalando o Locust
sudo mkdir -p /usr/src/app/scripts/
kubectl apply -f /home/ubuntu/LINUXtips-PICK/manifests/locust/
# Passando a Secret de Login do Docker
kubectl apply -f /home/ubuntu/LINUXtips-PICK/security/kyverno/docker-cred.yaml -n giropops
kubectl apply -f /home/ubuntu/LINUXtips-PICK/security/kyverno/docker-cred.yaml -n kyverno
# Instalando os Paths do Ingress
helm install ingress-controller ingress/ingress-templates
# Instalando o Metrics Server
kubectl apply -f /home/ubuntu/LINUXtips-PICK/manifests/metrics-hpa/metrics-components.yaml
# Instalando o Keda
helm install keda kedacore/keda --namespace keda --create-namespace
#helm install giropops giropops-app/giropops-chart --set env=stg
#kubectl apply -f /home/ubuntu/LINUXtips-PICK/monitoring/prometheus-metrics.yaml
#kubectl apply -f /home/ubuntu/LINUXtips-PICK/manifests/metrics-hpa/hpa-giropops.senhas.yaml
#kubectl apply -f /home/ubuntu/LINUXtips-PICK/manifests/metrics-hpa/KEDA-scaledObjectRedis.yaml