#!/bin/bash
set -e

BSC_ERROR_CHECK_BIN=127

function errorMessage(){
  local _message="$1" _errorCode="$2"
  echo "$_message"
  exit "$_errorCode"
}

function checkBin() {
  local _binary="$1" _full_path

  echo "Checking binary '$_binary' ... "

  # Checks if the binary is available.
  _full_path=$( command -v "$_binary" )
  commandStatus=$?
  if [ $commandStatus -ne 0 ]; then
    errorMessage "Unable to find binary '$_binary'." $BSC_ERROR_CHECK_BIN
  else
    # Checks if the binary has "execute" permission.
    [ -x "$_full_path" ] && return 0

    errorMessage "Binary '$_binary' found but it does not have *execute* permission." $BSC_ERROR_CHECK_BIN
  fi
}

function checkSkipIngress() {
  local _ingress="$1"
  local _skip_list="$2"
  _skip=0
  for toSkip in $(echo "$_skip_list" | tr "," "\n");
  do
#    echo "toSkip $toSkip _ingress $_ingress"
    if [[ "$toSkip" == "$_ingress" ]] 
    then
      
      _skip=1
    fi
  done
  echo $_skip
}

function fetchTenantValueFromIngress(){
  local _ingress="$1"
  echo "fetch tenant values from ingress: $_ingress"
  local _body=""
  local _snippets=""
  _body=$(kubectl -n "$NS" get ingress "$_ingress" -o yaml)
  _snippets=$(echo "$_body" | yq '.metadata.annotations."nginx.ingress.kubernetes.io/configuration-snippet"')
  #echo "$snippets"
  IFS=';' read -ra _rows <<<"$_snippets"
  for _row in "${_rows[@]}";
  do
    _row=$(echo "$_row" | xargs)
    #echo "_row: '$_row'"
    if [[ "${_row}" == "proxy_set_header"* ]]; then
      IFS=' ' read -ra _elements <<<"$_row"
      #echo "${_elements[0]} ${_elements[1]} ${_elements[2]}"
      case ${_elements[1]} in
        x-cbt-tenant-name)
          TENANT_NAME=${_elements[2]}
          ;;
        x-cbt-tenant-id)
          TENANT_ID=${_elements[2]}
          ;;
      esac  
    fi
  done
}

function createTenantCR(){
  local _name=$1
  local _tenantCR=""
  _tenantCR=$(cat <<EOF
---
apiVersion: tenant.cubbit.io/v1alpha1
kind: Tenant
metadata:
  namespace: $NS
  name: $_name
spec:
  tenantName: $TENANT_NAME
  tenantId: $TENANT_ID
EOF
)
  echo "$_tenantCR"
}

function checkReadyTenantCR(){
  local _name=$1
  kubectl -n "${NS}" get tenant "$_name" -o yaml | yq '.status.conditions | map(select(.type == "Ready")) | .[0].status' || echo "False"
}

function usage() {
    echo "The parameters list:"
    echo "  --ns <namespace name>                           : Default <cubbit>               ; Use namespace for all k8s resources to retrieve and create"
    echo "  --domain <domain>                               : Default <cubbit.eu>            ; Use domain to extract tenant value from ingress name"
    echo "  --skip-ingresses <ingress-name1,ingress-name2>  : Default <empty>                ; Use ingress names (comma separated) to exclude from migration"
    echo "  --skip-wait                                     : Default wait enabled           ; Use to skip to wait for tenant CR ready condition"
    echo "  --help                                          : print this help"
}


while [ "$#" -gt 0 ]; do
  case "$1" in
    "--ns") NS_OVERRIDE="$2";shift;;
    "--domain") ROOT_DOMAIN_OVERRIDE="$2";shift;;
    "--skip-ingresses") SKIP_INGRESSES_OVERRIDE="$2";shift;;
    "--skip-wait") SKIP_WAIT_OVERRIDE="true";;
    "--help") usage; exit 3;;
    "--"*) echo "Undefined argument \"$1\"" 1>&2; usage; exit 3;;
  esac
  shift
done

NS="${NS_OVERRIDE:-cubbit}"
ROOT_DOMAIN="${ROOT_DOMAIN_OVERRIDE:-cubbit.eu}"
SKIP_INGRESSES="${SKIP_INGRESSES_OVERRIDE:-}"
SKIP_WAIT=${SKIP_WAIT_OVERRIDE:-false}


echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "> NS:                 $NS"
echo "> ROOT_DOMAIN:        $ROOT_DOMAIN"
echo "> SKIP_INGRESSES:     $SKIP_INGRESSES"
echo "> SKIP_WAIT:          $SKIP_WAIT"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

echo " "
#checkBin curl
checkBin yq
checkBin kubectl


echo " "
INGRESSES=()
for ingress in $(kubectl -n $NS get ingress --no-headers -o name); do
    # echo "eval ingress ${ingress} ${ingress##*/}"
    INGRESS_NAME=${ingress##*/}
    _skip=$(checkSkipIngress "$INGRESS_NAME" "$SKIP_INGRESSES")
    if [[ $_skip -eq 0 ]] && [[ $INGRESS_NAME == *"$ROOT_DOMAIN" ]]
    then
      INGRESSES+=("$INGRESS_NAME")
    else
      echo "skip $INGRESS_NAME"
    fi
done

echo " "
echo "I have been found ${#INGRESSES[@]} ingresses to convert in tenant CR"
for INGRESS_NAME in "${INGRESSES[@]}"
do
  TENANT_NAME=""
  TENANT_ID=""
  echo " "   
  echo "==========================================="
  echo "ingress name: $INGRESS_NAME"
  echo "==========================================="
  fetchTenantValueFromIngress "$INGRESS_NAME"
  echo "TENANT_NAME:'$TENANT_NAME' TENANT_ID:'$TENANT_ID'"

  TENANT_CR="$(createTenantCR "$INGRESS_NAME")"
  echo "$TENANT_CR" | kubectl apply -n "${NS}" -f - || echo "error tenant CR apply"
  #echo "$TENANT_CR"
  if [[ $SKIP_WAIT == "false"  ]]; then
    IS_READY="False"
    while [ "$IS_READY" == "False" ]
    do
      sleep 10
      IS_READY=$(checkReadyTenantCR "$INGRESS_NAME")     
      echo "check for Tenant CR $INGRESS_NAME ready: $IS_READY"
    done
    echo "Tenant CR $INGRESS_NAME ready!"
  fi
done
