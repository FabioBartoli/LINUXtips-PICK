#!/bin/bash

# Instalando o Harbor
kubectl config set-context --current --namespace=harbor
helm install harbor harbor/harbor --set expose.type=clusterIP --set expose.tls.auto.commonName=fabiobartoli.com.br --set persistence.enabled=false --set externalURL=https://harbor.fabiobartoli.com.br --set fullnameOverride=harbor-harbor --set trivy.enabled=true
# Instalando o Kube-Prometheus
kubectl config set-context --current --namespace=monitoring
helm install kube-prometheus prometheus-community/kube-prometheus-stack
# Instalando o Kyverno
kubectl config set-context --current --namespace=default
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
# Instalando o Locust
sudo mkdir -p /usr/src/app/scripts/
sudo mv /home/ubuntu/LINUXtips-PICK/manifests/locust/locustfile.py /usr/src/app/scripts/locustfile.py
kubectl apply -f /home/ubuntu/LINUXtips-PICK/manifests/locust/
# Passando a Secret de Login do Docker
kubectl apply -f /home/ubuntu/LINUXtips-PICK/security/kyverno/docker-cred.yaml -n giropops
kubectl apply -f /home/ubuntu/LINUXtips-PICK/security/kyverno/docker-cred.yaml -n kyverno
# Instalando os Paths do Ingress
helm install ingress-controller ingress/ingress-templates
# Instalando o Metrics Server
kubectl apply -f /home/ubuntu/LINUXtips-PICK/manifests/metrics-hpa/components.yaml
# Instalando o Keda
helm install keda kedacore/keda --namespace keda --create-namespace
#helm install giropops giropops-app/giropops-chart --set env=stg