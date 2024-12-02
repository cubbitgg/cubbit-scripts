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

function usage() {
    echo "The parameters list:"
    echo "  --ns <namespace name>                           : Default <cubbit>               ; Use namespace for all k8s resources to retrieve and create"
    echo "  --help                                          : print this help"
}


while [ "$#" -gt 0 ]; do
  case "$1" in
    "--ns") NS_OVERRIDE="$2";shift;;
    "--help") usage; exit 3;;
    "--"*) echo "Undefined argument \"$1\"" 1>&2; usage; exit 3;;
  esac
  shift
done

NS="${NS_OVERRIDE:-cubbit}"


echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "> NS:                 $NS"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

echo " "
checkBin kubectl


echo " "
INGRESSES=()
echo "fetch ingress names with query"
for ingress in $(kubectl -n "$NS" get ingress -l "app.kubernetes.io/managed-by=efesto-operator" --no-headers -o name); do
    INGRESS_NAME=${ingress##*/}
    INGRESSES+=("$INGRESS_NAME")
done

echo " "
echo "I have been found ${#INGRESSES[@]} ingresses to convert in gateway-operator managed CR"
read -r -p "Do you wish to continue migration ? [y/N]: " ANSWER
case "$ANSWER" in
    [Yy])
      echo "proceding with script ..."
      ;;
    *)
      echo "exit ..."
      exit 0
      ;;
esac

read -r -p "Do you wish to save in backup.yaml actual ingress manifests ? [y/N]: " ANSWER
case "$ANSWER" in
    [Yy])
      echo "proceding with backup ..."
      echo "" > backup.yaml
      for INGRESS_NAME in "${INGRESSES[@]}"
      do
        echo 
        kubectl -n "$NS" get ingress "$INGRESS_NAME" -o yaml >> "backup.yaml"
        echo "---" >> backup.yaml
      done
      ;;
    *)
      echo "exit ..."
      exit 0
      ;;
esac

for INGRESS_NAME in "${INGRESSES[@]}"
do
  echo "processing patch ingress: $INGRESS_NAME"
  # patch the annotation app.kubernetes.io/managed-by to chnage value to 'gateway-operator'
  kubectl -n "$NS" patch ingress "$INGRESS_NAME" --type=merge -p '{"metadata":{"labels":{"app.kubernetes.io/managed-by":"gateway-operator"}}}'
done
