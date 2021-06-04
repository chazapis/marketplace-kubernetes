#!/bin/sh

set -e

################################################################################
# charts
################################################################################

uninstall_chart () {
    helm uninstall "$STACK" \
      --namespace "$NAMESPACE" \
      || true
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

kubectl -n $NAMESPACE delete secret ssl-certificate || true

# minio
STACK="minio"
NAMESPACE="minio"
uninstall_chart

# datashim
kubectl delete -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml || true

# karvdash
STACK="karvdash"
NAMESPACE="karvdash"
uninstall_chart
