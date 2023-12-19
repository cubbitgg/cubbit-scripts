#!/bin/bash
NS=efesto-operator-system

for ingress in $(kubectl -n ${NS} get ingress -o name  --no-headers); do
    #echo ${ingress##*/}
    kubectl -n ${NS} get ingress ${ingress##*/} -o yaml | grep -q "gods3"
    if (( "$?" == 0 )) ; then    
      echo "${ingress##*/}"
    fi
done