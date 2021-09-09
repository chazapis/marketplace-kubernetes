#!/bin/sh

set -e
# set -x

################################################################################
# charts
################################################################################

uninstall_chart () {
    helm uninstall "$STACK" --namespace "$NAMESPACE" || true
    if [ $NAMESPACE -ne "default" ]; then
        kubectl delete namespace $NAMESPACE || true
    fi
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

# nfs-server
NAMESPACE="nfs"
kubectl delete ns $NAMESPACE

# datashim
# kubectl delete -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml || true

# csi-nfs
STACK="csi-driver-nfs"
NAMESPACE="csi-nfs"
uninstall_chart

# ingress
STACK="ingress"
NAMESPACE="ingress-nginx"
uninstall_chart

# cert-manager
STACK="cert-manager"
NAMESPACE="cert-manager"
uninstall_chart
