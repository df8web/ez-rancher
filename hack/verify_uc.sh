#!/usr/bin/env sh

DELIVERABLES=$1

# export KUBECONFIG
export KUBECONFIG=`pwd`/${DELIVERABLES}/kubeconfig_user

count=0
result=0
until [ $result -eq 3 ]
do
    result=$(kubectl get nodes 2> /dev/null | grep -c Ready)
    echo $result/3 nodes ready
    if [ $count -eq 100 ]; then
        break
    fi
    count=`expr $count + 1`
    sleep 10
done

