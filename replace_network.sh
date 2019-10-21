#!/bin/bash

#replaces standard OVNKubernetes components with windows networking ready components and prepares the cluster for windows nodes 

#assumes access to kubectl and oc commands


NETWORK_IMAGE=quay.io/jtanenba/ovn-windows:alphav1
CNO_IMAGE=quay.io/jtanenba/cno-windows:alphav1

MASTER_NODE=$(oc get pods -n openshift-ovn-kubernetes -o wide | awk '/ovnkube-master/ {print $7}')

#echo $MASTER_NODE

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

#need to cycle in the new CNO to apply a series of changes to the deployments and such...
kubectl set image deployments network-operator network-operator=${CNO_IMAGE} -n openshift-network-operator

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

#scales the network-operator to 0
oc scale deployment network-operator --replicas=0 -n openshift-network-operator


#patches the ovnkube-master to only deploy the master in the same place the master is currently deployed 
#kubectl patch deployment ovnkube-master --patch '{"spec":{"template": {"spec":{"nodeName":"'$(oc get pods -n openshift-ovn-kubernetes -o wide | awk '/ovnkube-master/ {print $7}')'"}}}}' -n openshift-ovn-kubernetes
kubectl patch deployment ovnkube-master --patch '{"spec":{"template": {"spec":{"nodeName":"'${MASTER_NODE}'"}}}}' -n openshift-ovn-kubernetes



#sets  all the images in the master node to the windows networking enabled image 
kubectl set image deployments ovnkube-master \
   northd=${NETWORK_IMAGE} \
   nbdb=${NETWORK_IMAGE} \
   sbdb=${NETWORK_IMAGE} \
   ovnkube-master=${NETWORK_IMAGE} \
 -n openshift-ovn-kubernetes



#sets all the images in the worker nodes to the windows networking enabled image
kubectl set image daemonset/ovnkube-node \
    ovs-daemons=${NETWORK_IMAGE} \
    ovn-controller=${NETWORK_IMAGE} \
    ovnkube-node=${NETWORK_IMAGE} \
  -n openshift-ovn-kubernetes
