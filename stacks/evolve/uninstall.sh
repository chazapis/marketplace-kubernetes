#!/bin/sh

set -e
# set -x

################################################################################
# charts
################################################################################

uninstall_chart () {
    helm uninstall "$STACK" \
      --namespace "$NAMESPACE" \
      || true
    kubectl delete namespace $NAMESPACE || true
}

# karvdash
STACK="karvdash"
NAMESPACE="karvdash"

for i in `kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'`; do
    if echo $i | grep "karvdash-" > /dev/null; then
        kubectl delete ns $i # clean up user namespaces
    fi
done

uninstall_chart

# datashim
kubectl delete -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml || true

# minio
STACK="minio"
NAMESPACE="minio"
uninstall_chart

# ingress
STACK="ingress"
NAMESPACE="ingress-nginx"
uninstall_chart

# cert-manager
STACK="cert-manager"
NAMESPACE="cert-manager"
uninstall_chart
