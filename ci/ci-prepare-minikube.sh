#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

say "Running script: $0"

until minikube_start "true"
do
  say "minikube failed to start, retrying."
done

minikube_get_ip

say "Waiting for kubernetes to be available."
until (echo > /dev/tcp/${MINIKUBE_IP}/8443) &> /dev/null; do
    sleep 1 
done

# Create cosmic namespace
kubectl create namespace cosmic

# Setup docker registry with certificates
cosmic_docker_registry

say "Starting deployment: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/rabbitmq-deployment.yml

say "Starting service: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/rabbitmq-service.yml

say "Starting deployment: mariadb"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/mariadb-deployment.yml

say "Starting service: mariadb"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/mariadb-service.yml
