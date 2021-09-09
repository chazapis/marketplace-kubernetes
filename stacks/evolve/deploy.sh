#!/bin/sh

set -e
# set -x

################################################################################
# repo
################################################################################
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
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
    helm upgrade "$STACK" "$CHART" \
      --atomic \
      --timeout 15m0s \
      --create-namespace \
      --install \
      --namespace "$NAMESPACE" \
      --values "$(get_yaml $VALUES)" \
      --version "$CHART_VERSION" \
      $EXTRA
}

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
NAMESPACE="ingress-nginx"
VALUES="values/$STACK.yaml"
EXTRA=""
install_chart

INGRESS_EXTERNAL_IP=`kubectl -n $NAMESPACE get services ingress-ingress-nginx-controller --output jsonpath='{.status.loadBalancer.ingress[0].ip}'`
if [ -z "${MP_KUBERNETES}" ]; then
    INGRESS_EXTERNAL_IP=${INGRESS_EXTERNAL_IP:-"127.0.0.1"}
fi
INGRESS_CERTIFICATE_ISSUER=selfsigned
if [ "$INGRESS_EXTERNAL_IP" = "127.0.0.1" ]; then
    INGRESS_EXTERNAL_ADDRESS=localtest.me
else
    INGRESS_EXTERNAL_ADDRESS=${INGRESS_EXTERNAL_IP}.nip.io
fi

if kubectl -n $NAMESPACE get secret ssl-certificate; then
    :
else
    export INGRESS_CERTIFICATE_ISSUER
    export INGRESS_EXTERNAL_ADDRESS
    envsubst < $(get_yaml yaml/ingress-issuer-${INGRESS_CERTIFICATE_ISSUER}.yaml) | kubectl -n $NAMESPACE apply -f -
    envsubst < $(get_yaml yaml/ingress-certificate.yaml) | kubectl -n $NAMESPACE apply -f -
fi

# csi-nfs
STACK="csi-driver-nfs"
CHART="csi-driver-nfs/csi-driver-nfs"
CHART_VERSION="v3.0.0"
NAMESPACE="csi-nfs"
VALUES="values/$STACK.yaml"
EXTRA=""
install_chart

# datashim
# kubectl apply -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml
# kubectl wait --timeout=600s --for=condition=ready pods -l app.kubernetes.io/name=dlf -n dlf

# nfs-server
NAMESPACE="nfs"

if kubectl -n $NAMESPACE get service nfs-server; then
    :
else
    kubectl create namespace $NAMESPACE || true
    kubectl -n $NAMESPACE apply -f $(get_yaml yaml/nfs-service.yaml)
fi

# karvdash
STACK="karvdash"
CHART="karvdash/karvdash"
CHART_VERSION="3.0.0"
NAMESPACE="default"
VALUES="values/$STACK.yaml"
EXTRA="--set karvdash.ingressURL=https://${INGRESS_EXTERNAL_ADDRESS} --set karvdash.filesURL=nfs://nfs-server.nfs.svc/exports"

if kubectl -n $NAMESPACE get pvc karvdash-state-pvc; then
    :
else
    kubectl create namespace $NAMESPACE || true
    kubectl -n $NAMESPACE apply -f $(get_yaml yaml/karvdash-volume.yaml)
fi

install_chart
