#!/bin/bash

#replaces standard OVNKubernetes components with windows networking ready components and prepares the cluster for windows nodes 

#assumes access to kubectl and oc commands


NETWORK_IMAGE=quay.io/jtanenba/ovn-windows:085e0cb
CNO_IMAGE=quay.io/jtanenba/cno-windows:alphav1


# allows editing to the cluster network operator
kubectl patch --type=json -p "\
- op: add
  path: /spec/overrides
  value: []
- op: add
  path: /spec/overrides/-
  value:
    kind: Deployment
    name: network-operator
    group: operator.openshift.io
    namespace: openshift-network-operator
    unmanaged: true
" clusterversion version

#Patch the  OVN_IMAGE and CNO_IMAGE in the cluster network operator
kubectl patch deployment network-operator --patch '{"spec":{"template":{"spec":{"image":"'${CNO_IMAGE}'","containers":[{"name":"network-operator","env":[{"name":"OVN_IMAGE","value":"'${NETWORK_IMAGE}'"}]}]}}}}' -n openshift-network-operator


oc delete deployments ovnkube-master -n openshift-ovn-kubernetes
oc delete daemonsets ovnkube-node -n openshift-ovn-kubernetes

#make sure the ovnkube-node daemonset and ovnkube-master deployment have synced
while [ "$(oc get daemonsets -n openshift-ovn-kubernetes 2>/dev/null | awk '/ovnkube-node/ {print $1}')" != "ovnkube-node" ]
do
  echo "Waiting for daemonset ovnkube-node to reconcile"
  sleep 4
done

while [ "$(oc get deployments -n openshift-ovn-kubernetes 2>/dev/null | awk '/ovnkube-master/ {print $1}')" != "ovnkube-master" ]
do
  echo "Wating for deployment ovnkube-master to reconcile"
  sleep 4
done

echo "ovnkube-master deployment and ovnkube-node daemonset reconciled"



while [ "$(oc get daemonsets -n openshift-ovn-kubernetes 2>/dev/null| awk '/ovnkube-node/ {if ($2 == $6) print "true"}')" != "true" ]
do
  echo "Waiting for network nodes to restart"
  sleep 4
done 

while [ "$(oc get deployment -n openshift-ovn-kubernetes 2>/dev/null| awk '/ovnkube-master/ {if ($4 == 1) print "true"}')" != "true" ]
do 
  echo "Waiting for network master to restart"
  sleep 4
done

echo "Master and node network pods are running"


oc delete pods -n openshift-dns --all
oc delete pods -n openshift-apiserver --all

echo "dns pods and apiserver pods restarting"
