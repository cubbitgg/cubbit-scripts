#!/bin/bash

INGRESS_FILE_NAME=${INGRESS_FILE_NAME:-ingress-cubbit-scw-fr-default.bak}

for ingress in $(kubectl -n cubbit get ingress -o name  --no-headers); do
    echo ${ingress##*/}
    kubectl -n cubbit get ingress ${ingress##*/} -o yaml >> "${INGRESS_FILE_NAME}"
    echo "---" >> "${INGRESS_FILE_NAME}"
done