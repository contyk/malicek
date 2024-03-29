#!/bin/sh
if ! which curl jq >/dev/null 2>&1; then
    echo Missing dependencies.
    exit 1
fi

if [ ! -f ~/.malicek ]; then
    echo Malíček not configured.
    echo Define user and pass variables in ~/.malicek first.
    exit 2
fi

. ~/.malicek

cookies=/tmp/cookies_malicek.txt
endpoint=http://localhost:3000

if [ ! -f "${cookies}" ]; then
    curl \
        -c "${cookies}" \
        -d '{ "user": "'${user}'", "pass": "'${pass}'" }' \
        -H 'Content-Type: application/json' \
        -L \
        -s \
        "${endpoint}/login" \
        >/dev/null
fi

if [ -z "${2}" ]; then
    curl \
        -b "${cookies}" \
        -c "${cookies}" \
        -L \
        -s \
        "${endpoint}/${1}" \
        | jq
else
    curl \
        -b "${cookies}" \
        -c "${cookies}" \
        -d "${2}" \
        -H 'Content-Type: application/json' \
        -L \
        -s \
        "${endpoint}/${1}" \
        | jq
fi

if [ "${1}" = 'logout' ]; then
    rm -f "${cookies}"
fi
