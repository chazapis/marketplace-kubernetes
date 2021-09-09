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

# Argo Workflows
STACK="argo"
NAMESPACE="argo"
uninstall_chart

# JupyterHub
STACK="jupyterhub"
NAMESPACE="jupyterhub"
uninstall_chart

# Karvdash
STACK="karvdash"
NAMESPACE="karvdash"

for i in `kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'`; do
    if echo $i | grep "^karvdash-" > /dev/null; then
        kubectl delete ns $i # clean up user namespaces
    fi
    for j in `kubectl get pv -o jsonpath='{.items[*].metadata.name}'`; do
        if echo $j | grep "^$i" > /dev/null; then
            kubectl delete pv $j # clean up user persistent volumes
        fi
    done
done

uninstall_chart

# NFS server
NAMESPACE="nfs"
kubectl delete ns $NAMESPACE

# Datashim
# kubectl delete -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml || true

# NFS CSI Driver
STACK="csi-driver-nfs"
NAMESPACE="csi-nfs"
uninstall_chart

# NGINX Ingress Controller
STACK="ingress"
NAMESPACE="ingress-nginx"
uninstall_chart

# cert-manager
STACK="cert-manager"
NAMESPACE="cert-manager"
uninstall_chart
