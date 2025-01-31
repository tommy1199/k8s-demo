base_host := '127.0.0.1.nip.io'

cilium_version := 'v1.15.5'
sealed_secrets_version := '2.15.3'
argo_rollouts_version := '2.35.2'
kubeclarity_version := 'v2.23.1'
metacontroller_version := '4.11.12'
kyverno_version := '3.2.2'
kubevela_version := '1.9.11'
pyroscope_version := '1.5.1'
prometheus_version := '25.21.0'
loki_version := '6.5.2'
promtail_version := '6.15.5'
tempo_version := '1.7.3'
mimir_version := '5.3.0'
grafana_version := '7.3.11'
argocd_version := '6.9.3'
crossplane_version := '1.16.0'
cnpg_version := '0.21.2'
metrics_server_version := '3.12.1'

_default:
  @just -l

## Deploys in a single node cluster
single:
  just ingress_single
  just install

## Starts KIND cluster and installs all apps
up:
  just stop_kind
  just start_kind
  just ingress
  just install

## Installs all apps
install:
  just metrics_server
  just helm_repos
  just cnpg
  #just sealed_secrets
  #just rollouts
  #just metacontroller
  #just kyverno
  just kubevela
  just pyroscope
  just mimir
  just loki
  just tempo
  just grafana
  just prometheus
  just argocd
  just crossplane
  just backstage

# Adds all needed repos to helm
helm_repos:
  helm repo add cilium https://helm.cilium.io/
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo add kyverno https://kyverno.github.io/kyverno/
  helm repo add kubevela https://kubevela.github.io/charts
  helm repo add pyroscope-io https://pyroscope-io.github.io/helm-chart
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo add crossplane-stable https://charts.crossplane.io/stable
  helm repo add cnpg https://cloudnative-pg.github.io/charts
  helm repo add kubeclarity https://openclarity.github.io/kubeclarity
  helm repo update

# Stops KIND cluster
down:
  just stop_kind

# Stops KIND cluster
stop_kind:
  kind delete cluster --name k8s-demo

# Starts KIND cluster
start_kind:
  kind create cluster --name k8s-demo --config=cluster.yaml
  just cilium

# Installs cilium
cilium:
  helm upgrade --install \
    cilium cilium/cilium \
    -n kube-system \
    --set nodeinit.enabled=true \
    --set kubeProxyReplacement=partial \
    --set hostServices.enabled=false \
    --set externalIPs.enabled=true \
    --set nodePort.enabled=true \
    --set hostPort.enabled=true \
    --set ipam.mode=kubernetes \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true \
    --set hubble.metrics.enabled="{dns,drop,tcp,flow,icmp,http}" \
    --version {{cilium_version}} \
    --timeout 6m0s \
    --wait

# Installs Ingress Controller for single node
ingress_single:
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
  kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type JSON --patch-file ./ingress/single_ingress_deployment_patch.yaml
  kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=5m

# Installs Ingress Controller
ingress:
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=5m

code_server:
  helm upgrade --install code-server code-server/chart \
    -n code-server \
    --create-namespace \
    --set-json ingress.hosts='[{"host":"code.{{base_host}}","paths":["/"]}]' \
    --values code-server/helm-values.yaml

# Installs Cloudnative Postgres
cnpg:
  helm upgrade --install \
  cnpg cnpg/cloudnative-pg \
  -n cnpg-system \
  --create-namespace \
  --version {{cnpg_version}}

# Installs metrics server
metrics_server:
  helm upgrade --install \
  metrics-server metrics-server/metrics-server \
  -n metrics-server \
  --create-namespace \
  --set "args={'--kubelet-insecure-tls','--kubelet-preferred-address-types=InternalIP'}" \
  --version {{metrics_server_version}}

# Installs Sealed Secrets
sealed_secrets:
  kubectl delete secret -n kube-system sealed-secrets || true
  echo "$SEALED_SECRETS_KEY" > sealed-secrets.key
  echo "$SEALED_SECRETS_CRT" > sealed-secrets.crt
  kubectl create secret tls sealed-secrets -n kube-system \
    --key=sealed-secrets.key \
    --cert=sealed-secrets.crt
  rm sealed-secrets.*
  helm upgrade --install \
    sealed-secrets sealed-secrets/sealed-secrets \
    -n kube-system \
    --set "secretName=sealed-secrets" \
    --set "fullnameOverride=sealed-secrets-controller" \
    --version {{sealed_secrets_version}}

# Installs Argo Rollouts
rollouts:
  helm upgrade --install \
    argocd argo/argo-rollouts \
    -n argo-rollouts \
    --create-namespace \
    --version {{argo_rollouts_version}}

# Installs Kubeclarity
kubeclarity:
  helm upgrade --install \
    kubeclarity kubeclarity/kubeclarity \
    -n kubeclarity \
    --set-json kubeclarity.ingress.hosts='[{"host":"kubeclarity.{{base_host}}","paths":[{"path":"/","pathType":"Prefix"}]}]' \
    --values kubeclarity/helm-values.yaml \
    --create-namespace \
    --version {{kubeclarity_version}}

# Installs metacontroller
metacontroller:
  helm pull oci://ghcr.io/metacontroller/metacontroller-helm --version={{metacontroller_version}}
  helm upgrade --install metacontroller ./metacontroller-helm-{{metacontroller_version}}.tgz \
    -n metacontroller \
    --create-namespace \
    --set fullnameOverride=metacontroller
  rm ./metacontroller-helm-{{metacontroller_version}}.tgz

# Installs kyverno
kyverno:
  helm upgrade --install \
    kyverno kyverno/kyverno \
    -n kyverno \
    --create-namespace \
    --version {{kyverno_version}}

# Installs Kubevela
kubevela:
  helm upgrade --install \
    kubevela kubevela/vela-core \
    -n vela-system \
    --create-namespace \
    --version {{kubevela_version}}

# Installs pyroscope
pyroscope:
  helm upgrade --install \
    pyroscope grafana/pyroscope \
    -n observability \
    --create-namespace \
    --version {{pyroscope_version}}
  kubectl apply -f grafana/pyroscope-datasource.yaml

# Installs mimir
mimir:
  helm upgrade --install \
    mimir grafana/mimir-distributed \
    -n observability \
    --create-namespace \
    --version {{mimir_version}}
  kubectl apply -f grafana/mimir-datasource.yaml

# Installs Loki
loki:
  helm upgrade --install \
    loki grafana/loki \
    -n observability \
    --create-namespace \
    --values loki/helm-values.yaml \
    --version {{loki_version}}

  helm upgrade --install \
    promtail grafana/promtail \
    -n observability \
    --create-namespace \
    --values promtail/helm-values.yaml \
    --version {{promtail_version}}

  kubectl apply -f grafana/loki-datasource.yaml

# Installs Tempo
tempo:
  helm upgrade --install \
    tempo grafana/tempo \
    -n observability \
    --create-namespace \
    --set "tempo.searchEnabled=true" \
    --version {{tempo_version}}
  kubectl apply -f grafana/tempo-datasource.yaml

## Installs Grafana
grafana:
  #!/usr/bin/env bash
  rm grafana.env
  echo "AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID" >> grafana.env
  echo "AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET" >> grafana.env

  kubectl create ns observability || true
  kubectl create secret generic grafana-github -n observability --from-env-file=grafana.env

  helm upgrade --install \
    grafana grafana/grafana \
    -n observability \
    --create-namespace \
    --set ingress.hosts="{grafana.{{base_host}}}" \
    --set "grafana\.ini".server.root_url="https://grafana.{{base_host}}" \
    --values grafana/helm-values.yaml \
    --version {{grafana_version}}

# Installs Prometheus
prometheus:
  helm upgrade --install \
    prometheus prometheus-community/prometheus \
    -n observability \
    --create-namespace \
    --values prometheus/helm-values.yaml \
    --version {{prometheus_version}}
  kubectl apply -f grafana/prometheus-datasource.yaml


# Installs ArgoCD
argocd:
  helm upgrade --install \
    argocd argo/argo-cd \
    -n argocd \
    --create-namespace \
    --version {{argocd_version}} \
    --set server.ingress.hostname="argo-cd.{{base_host}}" \
    --values argocd/helm-values.yaml \
    --timeout 6m0s \
    --wait
  kubectl apply -n argocd -f https://raw.githubusercontent.com/devops-syndicate/argocd-apps/main/applicationset.yaml
  kubectl apply -n argocd -f https://raw.githubusercontent.com/devops-syndicate/infrastructure/main/applicationset.yaml

# Installs Crossplane
crossplane:
  #!/usr/bin/env bash
  set -euxo pipefail

  helm upgrade --install \
    crossplane crossplane-stable/crossplane \
    -n crossplane-system \
    --create-namespace \
    --version {{crossplane_version}} \
    --set "provider.packages={xpkg.upbound.io/upbound/provider-family-aws:v1.4.0,xpkg.upbound.io/upbound/provider-aws-rds:v1.4.0,xpkg.upbound.io/crossplane-contrib/provider-helm:v0.18.1,xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.13.0}" \
    --wait

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-kubernetes \
      --timeout=3m0s && break
    sleep 5
  done

  ## Configure Kubernetes Crossplane Provider
  KUBERNETES_PROVIDER_SA=$(kubectl -n crossplane-system get sa -o name | grep provider-kubernetes | sed -e 's|serviceaccount\/|crossplane-system:|g')
  kubectl create clusterrolebinding provider-kubernetes-admin-binding --clusterrole cluster-admin --serviceaccount="${KUBERNETES_PROVIDER_SA}" || true
  kubectl apply -n crossplane-system -f crossplane/kubernetes-provider-config.yaml

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-helm \
      --timeout=3m0s && break
    sleep 5
  done

  ## Configure Helm Crossplane Provider
  HELM_PROVIDER_SA=$(kubectl -n crossplane-system get sa -o name | grep provider-helm | sed -e 's|serviceaccount\/|crossplane-system:|g')
  kubectl create clusterrolebinding provider-helm-admin-binding --clusterrole cluster-admin --serviceaccount="${HELM_PROVIDER_SA}" || true
  kubectl apply -n crossplane-system -f crossplane/helm-provider-config.yaml

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-aws-rds \
      --timeout=3m0s && break
    sleep 5
  done

  ## Create AWS credential secrets for AWS crossplane provider
  AWS_PROFILE=default && echo "[default]
  aws_access_key_id=$(aws configure get aws_access_key_id --profile $AWS_PROFILE)
  aws_secret_access_key=$(aws configure get aws_secret_access_key --profile $AWS_PROFILE)" > creds.conf

  kubectl create secret generic aws-creds -n crossplane-system --from-file=creds=./creds.conf || true
  rm creds.conf

  kubectl wait --for condition=established --timeout=60s crd/compositeresourcedefinitions.apiextensions.crossplane.io crd/compositions.apiextensions.crossplane.io crd/providerconfigs.aws.upbound.io

  ## Configure AWS Crossplane Provider
  kubectl apply -n crossplane-system -f crossplane/package.yaml
  kubectl apply -n crossplane-system -f crossplane/aws-provider-config.yaml

# Installs Backstage
backstage:
  #!/usr/bin/env bash
  kubectl create ns backstage
  rm backstage.env
  echo "POSTGRES_HOST=backstage-db" >> backstage.env
  echo "POSTGRES_PORT=5432" >> backstage.env
  echo "AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID" >> backstage.env
  echo "AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET" >> backstage.env

  echo "Generate token for backstage"
  argocd login argo-cd.{{base_host}} --name local --username admin --password admin --insecure --grpc-web-root-path /
  AUTH_TOKEN=$(yq eval '.users[0].auth-token' ~/.config/argocd/config)
  argocd --server argo-cd.{{base_host}} account generate-token --account backstage --id backstage --auth-token ${AUTH_TOKEN} | sed -e 's/^/ARGOCD_AUTH_TOKEN=/' >> backstage.env

  kubectl create secret generic backstage -n backstage --from-env-file=backstage.env

  rm backstage.env

  kubectl create secret generic backstage-github-file -n backstage --from-file=github-credentials.yaml=./github-credentials.yaml

  sed "s/BASE_DOMAIN_VALUE/{{base_host}}/g" backstage/app.yaml | kubectl apply -f -

  kubectl wait -n backstage \
    --for=condition=ready pod \
    --selector=app=backstage \
    --timeout=5m
