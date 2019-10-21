#!/bin/bash

#replaces standard OVNKubernetes components with windows networking ready components and prepares the cluster for windows nodes 

#assumes access to kubectl and oc commands 

NETWORK_IMAGE=quay.io/jtanenba/ovn-windows:alphav1



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



#scales the network-operator to 0
oc scale deployment network-operator --replicas=0 -n openshift-network-operator


#patches the ovnkube-master to only deploy the master in the same place the master is currently deployed 
kubectl patch deployment ovnkube-master --patch '{"spec":{"template": {"spec":{"nodeName":"'$(oc get pods -n openshift-ovn-kubernetes -o wide | awk '/ovnkube-master/ {print $7}')'"}}}}' -n openshift-ovn-kubernetes



#sets  all the images in the master node to the windows networking enabled image 
kubectl set image deployments ovnkube-master \
   run-ovn-northd=${NETWORK_IMAGE} \
   nb-ovsdb=${NETWORK_IMAGE} \
   sb-ovsdb=${NETWORK_IMAGE} \
   ovnkube-master=${NETWORK_IMAGE} \
 -n openshift-ovn-kubernetes



#sets all the images in the worker nodes to the windows networking enabled image
kubectl set image daemonset/ovnkube-node \
    ovs-daemons=${NETWORK_IMAGE} \
    ovn-controller=${NETWORK_IMAGE} \
    ovn-node=${NETWORK_IMAGE} \
  -n openshift-ovn-kubernetes
