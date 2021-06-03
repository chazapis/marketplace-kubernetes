#!/bin/sh

set -e

################################################################################
# charts
################################################################################

install_chart () {
    helm uninstall "$STACK" \
      --namespace "$NAMESPACE"
}

# registry
STACK="registry"
NAMESPACE="registry"
uninstall_chart

# cert-manager
STACK="cert-manager"
NAMESPACE="cert-manager"
uninstall_chart

# ingress
STACK="ingress"
NAMESPACE="ingress"
uninstall_chart

kubectl -n ingress delete secret ssl-certificate

# minio
STACK="minio"
NAMESPACE="minio"
uninstall_chart

# datashim
kubectl delete -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml

# karvdash
STACK="karvdash"
NAMESPACE="karvdash"
uninstall_chart
