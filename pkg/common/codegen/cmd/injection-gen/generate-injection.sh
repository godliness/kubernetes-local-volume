#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# generate-groups generates everything for a project with external types only, e.g. a project based
# on CustomResourceDefinitions.

if [ "$#" -lt 4 ] || [ "${1}" == "--help" ]; then
  cat <<EOF
Usage: $(basename $0) <generators> <client-package> <apis-package> <groups-versions> ...

  <generators>        the generators comma separated to run (deepcopy,defaulter,client,lister,informer) or "all".
  <client-package>    the client package dir (e.g. github.com/example/project/pkg/clientset).
  <apis-package>      the external types dir (e.g. github.com/example/api or github.com/example/project/pkg/apis).
  <groups-versions>   the groups and their versions in the format "groupA:v1,v2 groupB:v1 groupC:v2", relative
                      to <api-package>.
  ...                 arbitrary flags passed to all generator binaries.


Examples:
  $(basename $0) all             github.com/example/project/pkg/client github.com/example/project/pkg/apis "foo:v1 bar:v1alpha1,v1beta1"
  $(basename $0) injection,foo   github.com/example/project/pkg/client github.com/example/project/pkg/apis "foo:v1 bar:v1alpha1,v1beta1"
EOF
  exit 0
fi

GENS="$1"
CLIENT_PKG="$2"
APIS_PKG="$3"
GROUPS_WITH_VERSIONS="$4"
shift 4

(
  # To support running this script from anywhere, we have to first cd into this directory
  # so we can install the tools.
  cd $(dirname "${0}")
  go install .
)

function codegen::join() { local IFS="$1"; shift; echo "$*"; }

# enumerate group versions
FQ_APIS=() # e.g. k8s.io/api/apps/v1
for GVs in ${GROUPS_WITH_VERSIONS}; do
  IFS=: read G Vs <<<"${GVs}"

  # enumerate versions
  for V in ${Vs//,/ }; do
    FQ_APIS+=(${APIS_PKG}/${G}/${V})
  done
done


if grep -qw "injection" <<<"${GENS}"; then
  if [[ -z "${OUTPUT_PKG:-}" ]]; then
    OUTPUT_PKG="${CLIENT_PKG}/injection"
  fi

  if [[ -z "${VERSIONED_CLIENTSET_PKG:-}" ]]; then
    VERSIONED_CLIENTSET_PKG="${CLIENT_PKG}/clientset/versioned"
  fi

  if [[ -z "${EXTERNAL_INFORMER_PKG:-}" ]]; then
    EXTERNAL_INFORMER_PKG="${CLIENT_PKG}/informers/externalversions"
  fi

  echo "Generating injection for ${GROUPS_WITH_VERSIONS} at ${OUTPUT_PKG}"

  # Clear old injection
  rm -rf ${OUTPUT_PKG}

  ${GOPATH}/bin/injection-gen \
    --input-dirs $(codegen::join , "${FQ_APIS[@]}") \
    --versioned-clientset-package ${VERSIONED_CLIENTSET_PKG} \
    --external-versions-informers-package ${EXTERNAL_INFORMER_PKG} \
    --output-package ${OUTPUT_PKG} \
    "$@"
fi

