#!/usr/bin/env bash

NSX_CONTROLLER_NODE=$1

echo "Note: Waiting for the VM to boot..."
while ! ping -c1 ${NSX_CONTROLLER_NODE} &>/dev/null; do :; done

echo "Note: Ping result for ${NSX_CONTROLLER_NODE}"
ping -c1 ${NSX_CONTROLLER_NODE}

echo "Note: wait until we can SSH to the controller node."
while ! nmap -Pn -p22 ${NSX_CONTROLLER_NODE} | grep "22/tcp open" 2>&1 > /dev/null; do sleep 1; done

SSH_OPTIONS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "Note: Cleaning controller node."
sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_CONTROLLER_NODE} clear everything force
sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_CONTROLLER_NODE} restart system force

echo "Note: wait until we can SSH to the controller node."
while ! nmap -Pn -p22 ${NSX_CONTROLLER_NODE} | grep "22/tcp open" 2>&1 > /dev/null; do sleep 1; done

sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_CONTROLLER_NODE} set network interface breth0 ip config static $(dig +short ${NSX_CONTROLLER_NODE}) 255.255.255.0
