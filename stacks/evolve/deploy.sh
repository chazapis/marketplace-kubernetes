#!/bin/sh

set -e

################################################################################
# repo
################################################################################
helm repo add twuni https://helm.twun.io
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add minio https://helm.min.io
helm repo add karvdash https://carv-ics-forth.github.io/karvdash/chart
helm repo update > /dev/null

################################################################################
# charts
################################################################################

get_yaml () {
    local yaml
    if [ -z "${MP_KUBERNETES}" ]; then
      # use local version
      ROOT_DIR=$(git rev-parse --show-toplevel)
      yaml="$ROOT_DIR/stacks/evolve/$1"
    else
      # use github hosted master version
      yaml="https://raw.githubusercontent.com/digitalocean/marketplace-kubernetes/master/stacks/evolve/$1"
    fi
    echo "$yaml"
}

install_chart () {
    # echo "helm upgrade \"$STACK\" \"$CHART\" \
    #   --atomic \
    #   --timeout 10m0s \
    #   --create-namespace \
    #   --install \
    #   --namespace \"$NAMESPACE\" \
    #   --values \"$(get_yaml $VALUES)\" \
    #   --version \"$CHART_VERSION\" \
    #   $EXTRA"
    helm upgrade "$STACK" "$CHART" \
      --atomic \
      --create-namespace \
      --install \
      --namespace "$NAMESPACE" \
      --values "$(get_yaml $VALUES)" \
      --version "$CHART_VERSION" \
      $EXTRA
}

# registry
STACK="registry"
CHART="twuni/docker-registry"
CHART_VERSION="1.10.0"
NAMESPACE="registry"
VALUES="values/$STACK.yaml"
EXTRA=""
install_chart

# cert-manager
STACK="cert-manager"
CHART="jetstack/cert-manager"
CHART_VERSION="v1.1.0"
NAMESPACE="cert-manager"
VALUES="values/$STACK.yaml"
EXTRA=""
install_chart
sleep 5 # wait for startup

# ingress
STACK="ingress"
CHART="ingress-nginx/ingress-nginx"
CHART_VERSION="3.19.0"
NAMESPACE="ingress"
VALUES="values/$STACK.yaml"
EXTRA=""

if kubectl -n $NAMESPACE get configmap nginx-custom-template; then
    :
else
    kubectl create namespace $NAMESPACE
    kubectl -n $NAMESPACE apply -f $(get_yaml yaml/ingress-configmap.yaml)
fi

install_chart

INGRESS_EXTERNAL_IP=`kubectl get services --namespace $NAMESPACE ingress-ingress-nginx-controller --output jsonpath='{.status.loadBalancer.ingress[0].ip}'`
if [ -z "${MP_KUBERNETES}" ]; then
    INGRESS_EXTERNAL_IP=${INGRESS_EXTERNAL_IP:-"127.0.0.1"}
else
    exit 255
fi

if kubectl -n $NAMESPACE get secret ssl-certificate; then
    :
else
    export INGRESS_EXTERNAL_IP
    envsubst < $(get_yaml yaml/ingress-certificate.yaml) | kubectl -n $NAMESPACE apply -f -
fi

# minio
STACK="minio"
CHART="minio/minio"
CHART_VERSION="8.0.10"
NAMESPACE="minio"
VALUES="values/$STACK.yaml"
EXTRA=""
install_chart

MINIO_ACCESS_KEY=$(kubectl -n $NAMESPACE get secret minio -o jsonpath="{.data.accesskey}" | base64 --decode)
MINIO_SECRET_KEY=$(kubectl -n $NAMESPACE get secret minio -o jsonpath="{.data.secretkey}" | base64 --decode)

# datashim
kubectl apply -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml
kubectl wait --timeout=600s --for=condition=ready pods -l app.kubernetes.io/name=dlf -n dlf

# karvdash
STACK="karvdash"
CHART="karvdash/karvdash"
CHART_VERSION="2.3.1"
NAMESPACE="karvdash"
VALUES="values/$STACK.yaml"
EXTRA="--set karvdash.ingressURL=https://${INGRESS_EXTERNAL_IP}.nip.io --set karvdash.filesURL=minio://${MINIO_ACCESS_KEY}:${MINIO_SECRET_KEY}@minio.minio.svc:9000/karvdash"

if kubectl -n karvdash get pvc karvdash-state-pvc; then
    :
else
    kubectl create namespace $NAMESPACE
    kubectl -n $NAMESPACE apply -f $(get_yaml yaml/karvdash-volume.yaml)
fi

install_chart
