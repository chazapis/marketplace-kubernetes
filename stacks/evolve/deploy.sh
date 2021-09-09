#!/bin/sh

set -e
# set -x

################################################################################
# repo
################################################################################
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo add argo https://argoproj.github.io/argo-helm
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
    --values "$(get_yaml values/$STACK.yaml)" \
    --version "$CHART_VERSION" \
    $EXTRA
}

INGRESS_NAMESPACE="ingress-nginx"
JUPYTERHUB_NAMESPACE="jupyterhub"
ARGO_NAMESPACE="argo"

# cert-manager
STACK="cert-manager"
CHART="jetstack/cert-manager"
CHART_VERSION="v1.1.0"
NAMESPACE="cert-manager"
EXTRA=""
install_chart
sleep 5 # wait for startup

# NGINX Ingress Controller
STACK="ingress"
CHART="ingress-nginx/ingress-nginx"
CHART_VERSION="3.19.0"
NAMESPACE=$INGRESS_NAMESPACE
EXTRA=""
install_chart

INGRESS_EXTERNAL_IP=`kubectl -n $NAMESPACE get services ingress-ingress-nginx-controller --output jsonpath='{.status.loadBalancer.ingress[0].ip}'`
if [ -z "${MP_KUBERNETES}" ] || [ -z "${INGRESS_EXTERNAL_IP}" ]; then
    # use local IP for testing on Docker Desktop
    INGRESS_EXTERNAL_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
fi
INGRESS_EXTERNAL_ADDRESS=${INGRESS_EXTERNAL_IP}.nip.io
INGRESS_CERTIFICATE_ISSUER=selfsigned

if kubectl -n $NAMESPACE get secret ssl-certificate; then
    :
else
    export INGRESS_CERTIFICATE_ISSUER
    export INGRESS_EXTERNAL_ADDRESS
    envsubst < $(get_yaml yaml/ingress-issuer-${INGRESS_CERTIFICATE_ISSUER}.yaml) | kubectl -n $NAMESPACE apply -f -
    envsubst < $(get_yaml yaml/ingress-certificate.yaml) | kubectl -n $NAMESPACE apply -f -
fi

# NFS CSI Driver
STACK="csi-driver-nfs"
CHART="csi-driver-nfs/csi-driver-nfs"
CHART_VERSION="v3.0.0"
NAMESPACE="csi-nfs"
EXTRA=""
install_chart

# Datashim
# kubectl apply -f https://raw.githubusercontent.com/datashim-io/datashim/master/release-tools/manifests/dlf.yaml
# kubectl wait --timeout=600s --for=condition=ready pods -l app.kubernetes.io/name=dlf -n dlf

# NFS server
NAMESPACE="nfs"

if kubectl -n $NAMESPACE get service nfs-server; then
    :
else
    kubectl create namespace $NAMESPACE || true
    kubectl -n $NAMESPACE apply -f $(get_yaml yaml/nfs-service.yaml)
fi

# Karvdash
STACK="karvdash"
CHART="karvdash/karvdash"
CHART_VERSION="3.0.0"
NAMESPACE="default"
EXTRA="--set karvdash.ingressURL=https://${INGRESS_EXTERNAL_ADDRESS} \
       --set karvdash.filesURL=nfs://nfs-server.nfs.svc/exports \
       --set karvdash.jupyterHubURL=https://jupyterhub.${INGRESS_EXTERNAL_ADDRESS} \
       --set karvdash.jupyterHubNamespace=${JUPYTERHUB_NAMESPACE} \
       --set karvdash.jupyterHubNotebookDir=notebooks \
       --set karvdash.argoWorkflowsURL=https://argo.${INGRESS_EXTERNAL_ADDRESS} \
       --set karvdash.argoWorkflowsNamespace=${ARGO_NAMESPACE}"

if kubectl -n $NAMESPACE get pvc karvdash-state-pvc; then
    :
else
    kubectl create namespace $NAMESPACE || true
    kubectl -n $NAMESPACE apply -f $(get_yaml yaml/karvdash-volume.yaml)
fi

kubectl create namespace $JUPYTERHUB_NAMESPACE || true
kubectl create namespace $ARGO_NAMESPACE || true

install_chart

# JupyterHub
NAMESPACE=$JUPYTERHUB_NAMESPACE

JUPYTERHUB_CLIENT_ID=$(kubectl -n $NAMESPACE get secret karvdash-oauth-jupyterhub --output jsonpath='{.data.client-id}' | base64 -d)
JUPYTERHUB_CLIENT_SECRET=$(kubectl -n $NAMESPACE get secret karvdash-oauth-jupyterhub --output jsonpath='{.data.client-secret}' | base64 -d)

STACK="jupyterhub"
CHART="jupyterhub/jupyterhub"
CHART_VERSION="1.0.1"
EXTRA="--set hub.config.GenericOAuthenticator.client_id=${JUPYTERHUB_CLIENT_ID} \
       --set hub.config.GenericOAuthenticator.client_secret=${JUPYTERHUB_CLIENT_SECRET} \
       --set hub.config.GenericOAuthenticator.oauth_callback_url=https://jupyterhub.${INGRESS_EXTERNAL_ADDRESS}/hub/oauth_callback \
       --set hub.config.GenericOAuthenticator.authorize_url=https://${INGRESS_EXTERNAL_ADDRESS}/oauth/authorize/ \
       --set hub.config.GenericOAuthenticator.token_url=https://${INGRESS_EXTERNAL_ADDRESS}/oauth/token/ \
       --set hub.config.GenericOAuthenticator.userdata_url=https://${INGRESS_EXTERNAL_ADDRESS}/oauth/userinfo/ \
       --set ingress.hosts[0]=jupyterhub.${INGRESS_EXTERNAL_ADDRESS}"
install_chart

# Argo Workflows
STACK="argo"
CHART="argo/argo-workflows"
CHART_VERSION="0.2.12"
NAMESPACE=$ARGO_NAMESPACE
EXTRA="--set server.volumeMounts[0].mountPath=/etc/ssl/certs/${INGRESS_EXTERNAL_ADDRESS}.crt \
       --set server.ingress.hosts[0]=argo.${INGRESS_EXTERNAL_ADDRESS} \
       --set server.sso.issuer=https://${INGRESS_EXTERNAL_ADDRESS}/oauth \
       --set server.sso.redirectUrl=https://argo.${INGRESS_EXTERNAL_ADDRESS}/oauth2/callback"

if kubectl -n $NAMESPACE get configmap ssl-certificate; then
    :
else
    kubectl -n $NAMESPACE create configmap ssl-certificate --from-literal="ca.crt=`kubectl get secret ssl-certificate -n ${INGRESS_NAMESPACE} -o 'go-template={{index .data \"ca.crt\" | base64decode }}'`"
fi

install_chart
