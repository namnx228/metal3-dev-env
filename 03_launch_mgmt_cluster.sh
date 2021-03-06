#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/releases.sh
# shellcheck disable=SC1091
source lib/network.sh

export IRONIC_HOST="${CLUSTER_URL_HOST}"
export IRONIC_HOST_IP="${CLUSTER_PROVISIONING_IP}"

sudo mkdir -p "${IRONIC_DATA_DIR}"
sudo chown -R "${USER}:${USER}" "${IRONIC_DATA_DIR}"

# Create certificates and related files for TLS
if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
  export IRONIC_BASE_URL="https://${CLUSTER_URL_HOST}"

  export IRONIC_CACERT_FILE="${IRONIC_CACERT_FILE:-"${WORKING_DIR}/certs/ironic-ca.pem"}"
  export IRONIC_CAKEY_FILE="${IRONIC_CAKEY_FILE:-"${WORKING_DIR}/certs/ironic-ca.key"}"
  export IRONIC_CERT_FILE="${IRONIC_CERT_FILE:-"${WORKING_DIR}/certs/ironic.crt"}"
  export IRONIC_KEY_FILE="${IRONIC_KEY_FILE:-"${WORKING_DIR}/certs/ironic.key"}"

  export IRONIC_INSPECTOR_CACERT_FILE="${IRONIC_INSPECTOR_CACERT_FILE:-"${WORKING_DIR}/certs/ironic-ca.pem"}"
  export IRONIC_INSPECTOR_CAKEY_FILE="${IRONIC_INSPECTOR_CAKEY_FILE:-"${WORKING_DIR}/certs/ironic-ca.key"}"
  export IRONIC_INSPECTOR_CERT_FILE="${IRONIC_INSPECTOR_CERT_FILE:-"${WORKING_DIR}/certs/ironic-inspector.crt"}"
  export IRONIC_INSPECTOR_KEY_FILE="${IRONIC_INSPECTOR_KEY_FILE:-"${WORKING_DIR}/certs/ironic-inspector.key"}"

  pushd "${WORKING_DIR}"
  mkdir -p "${WORKING_DIR}/certs"
  pushd "${WORKING_DIR}/certs"

  # Generate CA Key files
  if [ ! -f "${IRONIC_CAKEY_FILE}" ]; then
    openssl genrsa -out "${IRONIC_CAKEY_FILE}" 2048
  fi
  if [ ! -f "${IRONIC_INSPECTOR_CAKEY_FILE}" ]; then
    openssl genrsa -out "${IRONIC_INSPECTOR_CAKEY_FILE}" 2048
  fi

  # Generate CA cert files
  if [ ! -f "${IRONIC_CACERT_FILE}" ]; then
    openssl req -x509 -new -nodes -key "${IRONIC_CAKEY_FILE}" -sha256 -days 1825 -out "${IRONIC_CACERT_FILE}" -subj /CN="ironic CA"/
  fi
  if [ ! -f "${IRONIC_INSPECTOR_CACERT_FILE}" ]; then
    openssl req -x509 -new -nodes -key "${IRONIC_INSPECTOR_CAKEY_FILE}" -sha256 -days 1825 -out "${IRONIC_INSPECTOR_CACERT_FILE}" -subj /CN="ironic inspector CA"/
  fi

  # Generate Key files
  if [ ! -f "${IRONIC_KEY_FILE}" ]; then
    openssl genrsa -out "${IRONIC_KEY_FILE}" 2048
  fi
  if [ ! -f "${IRONIC_INSPECTOR_KEY_FILE}" ]; then
    openssl genrsa -out "${IRONIC_INSPECTOR_KEY_FILE}" 2048
  fi

  # Generate CSR and certificate files
  if [ ! -f "${IRONIC_CERT_FILE}" ]; then
    openssl req -new -key "${IRONIC_KEY_FILE}" -out /tmp/ironic.csr -subj /CN="${IRONIC_HOST}"/
    openssl x509 -req -in /tmp/ironic.csr -CA "${IRONIC_CACERT_FILE}" -CAkey "${IRONIC_CAKEY_FILE}" -CAcreateserial -out "${IRONIC_CERT_FILE}" -days 825 -sha256 -extfile <(printf "subjectAltName=IP:%s" "${IRONIC_HOST_IP}")
  fi
  if [ ! -f "${IRONIC_INSPECTOR_CERT_FILE}" ]; then
    openssl req -new -key "${IRONIC_INSPECTOR_KEY_FILE}" -out /tmp/ironic.csr -subj /CN="${IRONIC_HOST}"/
    openssl x509 -req -in /tmp/ironic.csr -CA "${IRONIC_INSPECTOR_CACERT_FILE}" -CAkey "${IRONIC_INSPECTOR_CAKEY_FILE}" -CAcreateserial -out "${IRONIC_INSPECTOR_CERT_FILE}" -days 825 -sha256 -extfile <(printf "subjectAltName=IP:%s" "${IRONIC_HOST_IP}")
  fi

  #Populate the CA certificate B64 variable
  if [ "${IRONIC_CACERT_FILE}" == "${IRONIC_INSPECTOR_CACERT_FILE}" ]; then
    IRONIC_CA_CERT_B64="${IRONIC_CA_CERT_B64:-"$(base64 -w 0 < "${IRONIC_CACERT_FILE}")"}"
  else
    IRONIC_CA_CERT_B64="${IRONIC_CA_CERT_B64:-"$(base64 -w 0 < "${IRONIC_CACERT_FILE}")$(base64 -w 0 < "${IRONIC_INSPECTOR_CACERT_FILE}")"}"
  fi
  export IRONIC_CA_CERT_B64

  popd
  popd
  unset IRONIC_NO_CA_CERT
else
  export IRONIC_BASE_URL="http://${CLUSTER_URL_HOST}"
  export IRONIC_NO_CA_CERT="true"

  # Unset all TLS related variables to prevent a TLS deployment
  unset IRONIC_CA_CERT_B64
  unset IRONIC_CACERT_FILE
  unset IRONIC_CERT_FILE
  unset IRONIC_KEY_FILE
  unset IRONIC_INSPECTOR_CACERT_FILE
  unset IRONIC_INSPECTOR_CERT_FILE
  unset IRONIC_INSPECTOR_KEY_FILE
fi


# Create usernames and passwords and other files related to basic auth
if [ "${IRONIC_BASIC_AUTH}" == "true" ]; then

  IRONIC_AUTH_DIR="${IRONIC_AUTH_DIR:-"${IRONIC_DATA_DIR}/auth/"}"
  mkdir -p "${IRONIC_AUTH_DIR}"

  #If usernames and passwords are unset, read them from file or generate them
  if [ -z "${IRONIC_USERNAME:-}" ]; then
    if [ ! -f "${IRONIC_AUTH_DIR}ironic-username" ]; then
        IRONIC_USERNAME="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)"
        echo "$IRONIC_USERNAME" > "${IRONIC_AUTH_DIR}ironic-username"
    else
        IRONIC_USERNAME="$(cat "${IRONIC_AUTH_DIR}ironic-username")"
    fi
  fi
  if [ -z "${IRONIC_PASSWORD:-}" ]; then
    if [ ! -f "${IRONIC_AUTH_DIR}ironic-password" ]; then
        IRONIC_PASSWORD="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)"
        echo "$IRONIC_PASSWORD" > "${IRONIC_AUTH_DIR}ironic-password"
    else
        IRONIC_PASSWORD="$(cat "${IRONIC_AUTH_DIR}ironic-password")"
    fi
  fi
  IRONIC_INSPECTOR_USERNAME="${IRONIC_INSPECTOR_USERNAME:-"${IRONIC_USERNAME}"}"
  IRONIC_INSPECTOR_PASSWORD="${IRONIC_INSPECTOR_PASSWORD:-"${IRONIC_PASSWORD}"}"

  export IRONIC_USERNAME
  export IRONIC_PASSWORD
  export IRONIC_INSPECTOR_USERNAME
  export IRONIC_INSPECTOR_PASSWORD

  unset IRONIC_NO_BASIC_AUTH
  unset IRONIC_INSPECTOR_NO_BASIC_AUTH
else
  # Disable Basic Authentication towards Ironic in BMO
  # Those variables are used in the CAPM3 component files
  export IRONIC_NO_BASIC_AUTH="true"
  export IRONIC_INSPECTOR_NO_BASIC_AUTH="true"

  unset IRONIC_USERNAME
  unset IRONIC_PASSWORD
  unset IRONIC_INSPECTOR_USERNAME
  unset IRONIC_INSPECTOR_PASSWORD
fi

# -----------------------
# Repositories management
# -----------------------

#
# Clone and checkout a repo
#
function clone_repo() {
  local REPO_URL="$1"
  local REPO_BRANCH="$2"
  local REPO_PATH="$3"
  if [[ -d "${REPO_PATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
    rm -rf "${REPO_PATH}"
  fi
  if [ ! -d "${REPO_PATH}" ] ; then
    pushd "${M3PATH}"
    git clone "${REPO_URL}" "${REPO_PATH}"
    popd
    pushd "${REPO_PATH}"
    git checkout "${REPO_BRANCH}"
    git pull -r || true
    popd
  fi
}

#
# Clone all needed repositories
#
function clone_repos() {
  mkdir -p "${M3PATH}"
  clone_repo "${BMOREPO}" "${BMOBRANCH}" "${BMOPATH}"
  clone_repo "${CAPM3REPO}" "${CAPM3BRANCH}" "${CAPM3PATH}"
  clone_repo "${IPAMREPO}" "${IPAMBRANCH}" "${IPAMPATH}"
  clone_repo "${CAPIREPO}" "${CAPIBRANCH}" "${CAPIPATH}"
}

# ------------------------------------
# BMO  and Ironic deployment functions
# ------------------------------------

#
# Modifies the images to use the ones built locally in the kustomization
# This is v1a3 specific for BMO, all versions for Ironic
#
function update_kustomization_images(){
  FILE_PATH=$1
  for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    # Strip the tag for image replacement
    OLD_IMAGE="${!OLD_IMAGE_VAR%:*}"
    sed -i -E "s $OLD_IMAGE$ $LOCAL_IMAGE g" "$FILE_PATH"
  done
  # Assign images from local image registry for kustomization
  for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    sed -i -E "s $IMAGE$ $LOCAL_IMAGE g" "$FILE_PATH"
  done
}

#
# Create the BMO deployment (used for v1a3 only)
#
function launch_baremetal_operator() {
  pushd "${BMOPATH}"

  # Deploy BMO using deploy.sh script

  # Update container images to use local ones
  cp "${BMOPATH}/deploy/operator/bmo.yaml" "${BMOPATH}/deploy/operator/bmo.yaml.orig"
  update_kustomization_images "${BMOPATH}/deploy/operator/bmo.yaml"

  # Update Configmap parameters with correct urls
  cp "${BMOPATH}/deploy/default/ironic_bmo_configmap.env" "${BMOPATH}/deploy/default/ironic_bmo_configmap.env.orig"
  cat << EOF | sudo tee "${BMOPATH}/deploy/default/ironic_bmo_configmap.env"
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
EOF

  # Deploy. Args: <deploy-BMO> <deploy-Ironic> <deploy-TLS> <deploy-Basic-Auth> <deploy-Keepalived>
  "${BMOPATH}/tools/deploy.sh" true false "${IRONIC_TLS_SETUP}" "${IRONIC_BASIC_AUTH}" true

  # Restore original files
  mv "${BMOPATH}/deploy/default/ironic_bmo_configmap.env.orig" "${BMOPATH}/deploy/default/ironic_bmo_configmap.env"
  mv "${BMOPATH}/deploy/operator/bmo.yaml.orig" "${BMOPATH}/deploy/operator/bmo.yaml"

  # If BMO should run locally, scale down the deployment and run BMO
  if [ "${BMO_RUN_LOCAL}" = true ]; then
    if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
      sudo mkdir -p /opt/metal3/certs/ca/
      cp "${IRONIC_CACERT_FILE}" /opt/metal3/certs/ca/crt
      if [ "${IRONIC_CACERT_FILE}" != "${IRONIC_INSPECTOR_CACERT_FILE}" ]; then
        cat "${IRONIC_INSPECTOR_CACERT_FILE}" >> /opt/metal3/certs/ca/crt
      fi
    fi
    if [ "${IRONIC_BASIC_AUTH}" == "true" ]; then
      sudo mkdir -p /opt/metal3/auth/ironic
      cp "${IRONIC_AUTH_DIR}ironic-username" /opt/metal3/auth/ironic/username
      cp "${IRONIC_AUTH_DIR}ironic-password" /opt/metal3/auth/ironic/password
      sudo mkdir -p /opt/metal3/auth/ironic-inspector
      cp "${IRONIC_AUTH_DIR}ironic-inspector-username" /opt/metal3/auth/ironic-inspector/username
      cp "${IRONIC_AUTH_DIR}ironic-inspector-password" /opt/metal3/auth/ironic-inspector/password
    fi

    export IRONIC_ENDPOINT=${IRONIC_URL}
    export IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}

    touch bmo.out.log
    touch bmo.err.log
    kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
    nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
  fi
  popd
}

#
# Modifies the images to use the ones built locally
# Updates the environment variables to refer to the images
# pushed to the local registry for caching.
#
function update_images(){
  for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    # Strip the tag for image replacement
    OLD_IMAGE="${!OLD_IMAGE_VAR%:*}"
    eval "$OLD_IMAGE_VAR"="$LOCAL_IMAGE"
    export "${OLD_IMAGE_VAR?}"
  done
  # Assign images from local image registry after update image
  # This allows to use cached images for faster downloads
  for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    eval "$IMAGE_VAR"="$LOCAL_IMAGE"
  done
}

#
# Launch Ironic locally for Kind and Tilt, in cluster for Minikube
#
function launch_ironic() {
  pushd "${BMOPATH}"

  if [ "${EPHEMERAL_CLUSTER}" != "minikube" ]; then
    update_images
    ${RUN_LOCAL_IRONIC_SCRIPT}
  else
    # Deploy Ironic using deploy.sh script

    # Update container images to use local ones
    cp "${BMOPATH}/ironic-deployment/ironic/ironic.yaml" "${BMOPATH}/ironic-deployment/ironic/ironic.yaml.orig"
    cp "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml" "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml.orig"
    update_kustomization_images "${BMOPATH}/ironic-deployment/ironic/ironic.yaml"
    update_kustomization_images "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml"

    # Update Configmap parameters with correct urls
    cp "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env" "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env.orig"
    cat << EOF | sudo tee "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env"
HTTP_PORT=6180
PROVISIONING_IP=${CLUSTER_PROVISIONING_IP}
PROVISIONING_CIDR=${PROVISIONING_CIDR}
PROVISIONING_INTERFACE=${CLUSTER_PROVISIONING_INTERFACE}
DHCP_RANGE=${CLUSTER_DHCP_RANGE}
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
CACHEURL=http://$IRONIC_HOST/images
IRONIC_FAST_TRACK=false
EOF
    # Deploy. Args: <deploy-BMO> <deploy-Ironic> <deploy-TLS> <deploy-Basic-Auth> <deploy-Keepalived>
    "${BMOPATH}/tools/deploy.sh" false true "${IRONIC_TLS_SETUP}" "${IRONIC_BASIC_AUTH}" true

    # Restore original files
    mv "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env.orig" "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env"
    mv "${BMOPATH}/ironic-deployment/ironic/ironic.yaml.orig" "${BMOPATH}/ironic-deployment/ironic/ironic.yaml"
    mv "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml.orig" "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml"

  fi
  popd
}

# ------------
# BMH Creation
# ------------

#
# Create the BMH CRs
#
function make_bm_hosts() {
  while read -r name address user password mac; do
    go run "${BMOPATH}"/cmd/make-bm-worker/main.go \
      -address "$address" \
      -password "$password" \
      -user "$user" \
      -boot-mac "$mac" \
      -boot-mode "legacy" \
      "$name"
  done
}

#
# Apply the BMH CRs
#
function apply_bm_hosts() {
  pushd "${BMOPATH}"
  list_nodes | make_bm_hosts > "${WORKING_DIR}/bmhosts_crs.yaml"
  if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
    kubectl apply -f "${WORKING_DIR}/bmhosts_crs.yaml" -n metal3
  fi
  popd
}

# --------------------------
# CAPM3 deployment functions
# --------------------------

#
# Update the imports for the CAPM3 deployment files
#
function update_capm3_imports(){
  pushd "${CAPM3PATH}"

  # Modify the kustomization imports to use local BMO repo instead of Github Master
  cp config/bmo/kustomization.yaml config/bmo/kustomization.yaml.orig
  FOLDERS="$(grep github.com/metal3-io/baremetal-operator/ "config/bmo/kustomization.yaml" | \
  awk '{ print $2 }' | sed -e 's#^github.com/metal3-io/baremetal-operator/##' -e 's/?ref=.*$//')"
  BMO_REAL_PATH="$(realpath --relative-to="${CAPM3PATH}/config/bmo" "${BMOPATH}")"
  for folder in $FOLDERS; do
    sed -i -e "s#github.com/metal3-io/baremetal-operator/${folder}?ref=.*#${BMO_REAL_PATH}/${folder}#" "config/bmo/kustomization.yaml"
  done

  # Render the IPAM components from local repo instead of using the released version
  make hack/tools/bin/kustomize
  ./hack/tools/bin/kustomize build "${IPAMPATH}/config/" > config/ipam/metal3-ipam-components.yaml
  sed -i -e "s#https://github.com/metal3-io/ip-address-manager/releases/download/v.*/ipam-components.yaml#metal3-ipam-components.yaml#" "config/ipam/kustomization.yaml"
  popd
}

#
# Update the images for the CAPM3 deployment file to use local ones
#
function update_component_image(){
  IMPORT=$1
  ORIG_IMAGE=$2
  # Split the image IMAGE_NAME AND IMAGE_TAG, if any tag exist
  TMP_IMAGE="${ORIG_IMAGE##*/}"
  TMP_IMAGE_NAME="${TMP_IMAGE%%:*}"
  TMP_IMAGE_TAG="${TMP_IMAGE##*:}"
  # Assign the image tag to latest if there is no tag in the image
  if [ "${TMP_IMAGE_NAME}" == "${TMP_IMAGE_TAG}" ]; then
    TMP_IMAGE_TAG="latest"
  fi

  if [ "${IMPORT}" == "CAPM3" ]; then
    export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
    export MANIFEST_TAG="${TMP_IMAGE_TAG}"
    make set-manifest-image
  elif [ "${IMPORT}" == "BMO" ]; then
    export MANIFEST_IMG_BMO="${REGISTRY}/localimages/$TMP_IMAGE_NAME"
    export MANIFEST_TAG_BMO="$TMP_IMAGE_TAG"
    make set-manifest-image-bmo
  elif [ "${IMPORT}" == "IPAM" ]; then
    export MANIFEST_IMG_IPAM="${REGISTRY}/localimages/$TMP_IMAGE_NAME"
    export MANIFEST_TAG_IPAM="$TMP_IMAGE_TAG"
    make set-manifest-image-ipam
  fi
}

#
# Update the clusterctl deployment files to use local repositories
#
function patch_clusterctl(){
  pushd "${CAPM3PATH}"
  mkdir -p "${HOME}"/.cluster-api
  touch "${HOME}"/.cluster-api/clusterctl.yaml

  # At this point the images variables have been updated with update_images
  # Reflect the change in components files
  update_component_image CAPM3 "${CAPM3_IMAGE}"

  if [ "${CAPM3_VERSION}" != "v1alpha3" ]; then
    update_component_image BMO "${BAREMETAL_OPERATOR_IMAGE}"
    update_component_image IPAM "${IPAM_IMAGE}"
    update_capm3_imports
  fi

  make release-manifests

  rm -rf "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  mkdir -p "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  cp out/*.yaml "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  popd
}

#
# Launch the cluster-api provider.
#
function launch_cluster_api_provider_metal3() {
  pushd "${CAPM3PATH}"

    # shellcheck disable=SC2153
  clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" \
    --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}"  -v5

  if [ "${CAPM3_RUN_LOCAL}" == true ]; then
    touch capm3.out.log
    touch capm3.err.log
    kubectl scale -n metal3 deployment.v1.apps capm3-controller-manager --replicas 0
    nohup make run >> capm3.out.log 2>> capm3.err.log &
  fi

  if [ "${BMO_RUN_LOCAL}" == true ] && [ "${CAPM3_VERSION}" != "v1alpha3" ]; then
    touch bmo.out.log
    touch bmo.err.log
    kubectl scale deployment capm3-metal3-baremetal-operator -n capm3-system --replicas=0
    nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
  fi

  popd
}

# -------------
# Miscellaneous
# -------------

function render_j2_config () {
  python3 -c 'import os; import sys; import jinja2; sys.stdout.write(jinja2.Template(sys.stdin.read()).render(env=os.environ))' < "${1}"
}

#
# Write out a clouds.yaml for this environment
#
function create_clouds_yaml() {
  # To bind this into the ironic-client container we need a directory
  mkdir -p "${SCRIPTDIR}"/_clouds_yaml
  if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
    cp "${IRONIC_CACERT_FILE}" "${SCRIPTDIR}"/_clouds_yaml/ironic-ca.crt
  fi
  render_j2_config "${SCRIPTDIR}"/clouds.yaml.j2 > _clouds_yaml/clouds.yaml
}

# ------------------------
# Management cluster infra
# ------------------------

#
# Start a KinD management cluster
#
function launch_kind() {
  cat <<EOF | sudo su -l -c "kind create cluster --name kind --image=kindest/node:${KUBERNETES_VERSION} --config=- " "$USER"
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${REGISTRY}"]
      endpoint = ["http://${REGISTRY}"]
EOF
}

#
# Create a management cluster
#
function start_management_cluster () {
  if [ "${EPHEMERAL_CLUSTER}" == "kind" ]; then
    launch_kind
  elif [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
    init_minikube

    sudo su -l -c 'minikube start' "${USER}"
    if [[ -n "${MINIKUBE_BMNET_V6_IP}" ]]; then
      sudo su -l -c "minikube ssh -- sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0" "${USER}"
      sudo su -l -c "minikube ssh -- sudo ip addr add $MINIKUBE_BMNET_V6_IP/64 dev eth3" "${USER}"
    fi
    if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
      sudo su -l -c 'minikube ssh "sudo ip -6 addr add '"$CLUSTER_PROVISIONING_IP/$PROVISIONING_CIDR"' dev eth2"' "${USER}"
    else
      sudo su -l -c "minikube ssh sudo brctl addbr $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
      sudo su -l -c "minikube ssh sudo ip link set $CLUSTER_PROVISIONING_INTERFACE up" "${USER}"
      sudo su -l -c "minikube ssh sudo brctl addif $CLUSTER_PROVISIONING_INTERFACE eth2" "${USER}"
      sudo su -l -c "minikube ssh sudo ip addr add $INITIAL_IRONICBRIDGE_IP/$PROVISIONING_CIDR dev $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
    fi
  fi
}

# -----------------------------
# Deploy the management cluster
# -----------------------------

clone_repos
create_clouds_yaml
if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  start_management_cluster
  kubectl create namespace metal3
  if [ "${CAPM3_VERSION}" == "v1alpha3" ]; then
    launch_baremetal_operator
  fi
fi

if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  patch_clusterctl
  launch_cluster_api_provider_metal3
  apply_bm_hosts
fi

launch_ironic
