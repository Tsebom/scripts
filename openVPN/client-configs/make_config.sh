#!/bin/bash

# First argument: Client identifier

KEY_DIR=~/client-configs/keys # В данной директории должен лежать файлы ca.crt, <CLIENT_NAMES>.key, <CLIENTS_NAMES>.crt 
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf # В файле заменить SERVER_IP_ADDRESS на ip свего сервера

cat ${BASE_CONFIG} \
    <(echo -e '\n<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/${1}.key \
    <(echo -e '</key>') \
    > ${OUTPUT_DIR}/${1}.ovpn