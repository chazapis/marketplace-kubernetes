#!/bin/sh

set -e

################################################################################
# charts
################################################################################

uninstall_chart () {
    helm uninstall "$STACK" \
      --namespace "$NAMESPACE" \
      || true
	kubectl delete namespace $NAMESPACE
}

# karvdash
STACK="karvdash"
NAMESPACE="karvdash"
uninstall_chart

# datashim
kubectl delete -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml || true

# minio
STACK="minio"
NAMESPACE="minio"
uninstall_chart

# registry
STACK="registry"
NAMESPACE="registry"
uninstall_chart

# ingress
STACK="ingress"
NAMESPACE="ingress-nginx"
uninstall_chart

# cert-manager
STACK="cert-manager"
NAMESPACE="cert-manager"
uninstall_chart
