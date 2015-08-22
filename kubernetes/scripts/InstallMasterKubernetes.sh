#!/bin/bash
set -o errexit
# Author: Francisco Gimeno 
# Date: 20150819
# Instructions from https://github.com/kubernetes/kubernetes/blob/master/docs/getting-started-guides/docker-multinode/master.md

# Used variables:
#   ETCD_VERSION: 2.0.12
#   FLANNEL_NETWORK: 10.1.0.0/16
#   KUBEVERSION: v1.0.3
#   CLUSTER_DNS: 10.1.0.10
#   CLUSTER_DOMAIN: cluster.local

export DEBIAN_FRONTEND=noninteractive


# Don't change this. Set the Global Var: CLUSTER_DNS
ETCD_VERSION_DEFAULT="2.0.12"
FLANNEL_NETWORK_DEFAULT="10.1.0.0/16"
KUBEVERSION_DEFAULT="v1.0.3"
CLUSTER_DNS_DEFAULT="10.1.0.10"
CLUSTER_DOMAIN_DEFAULT="cluster.local"

# We'll need it
apt-get install -f bridge-utils


# Setup Docker-Bootstrap
echo "Executing Temporary Docker daemon"
sh -c 'docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null &'

# Startup etcd for flannel and the API server to use
echo "Starting etcd"
sleep 10
docker -H unix:///var/run/docker-bootstrap.sock run --net=host -d gcr.io/google_containers/etcd:${ETCD_VERSION-$ETCD_VERSION_DEFAULT} /usr/local/bin/etcd --addr=127.0.0.1:4001 --bind-addr=0.0.0.0:4001 --data-dir=/var/etcd/data
sleep 10
docker -H unix:///var/run/docker-bootstrap.sock run --net=host gcr.io/google_containers/etcd:${ETCD_VERSION-$ETCD_VERSION_DEFAULT} etcdctl set /coreos.com/network/config '{ "Network": "'${FLANNEL_NETWORK-$FLANNEL_NETWORK_DEFAULT}'" }'

# Set up Flannel on the master node
echo "Stopping Docker"
service docker stop
sleep 10

# Run Flannel
echo "Starting Flannel"
TOKEN=`docker -H unix:///var/run/docker-bootstrap.sock run -d --net=host --privileged -v /dev/net:/dev/net quay.io/coreos/flannel:0.5.0 | tail -n1`
sleep 10
echo "  Detected token: ${TOKEN}"
docker -H unix:///var/run/docker-bootstrap.sock exec ${TOKEN} cat /run/flannel/subnet.env > /etc/flannel_subnet.env

# Edit the docker configuration
echo "Modifying docker configuration"
TMPFILE=`tempfile`
(cat /etc/default/docker /etc/flannel_subnet.env ; echo DOCKER_OPTS='"--bip=${FLANNEL_SUBNET} --mtu=${FLANNEL_MTU}"' ) > TMPFILE
mv -f TMPFILE /etc/default/docker

# Remove the existing Docker bridge
echo "Removing docker bridge: docker0"

if [[ $(/sbin/ifconfig -a | grep -q docker0) -eq 0 ]]; then
	/sbin/ifconfig docker0 down
	brctl delbr docker0
fi

# Start docker service
echo "Starting docker service"
service docker start

# Start the kubernetes master
echo "Starting kubernetes master"
docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  gcr.io/google_containers/hyperkube:${KUBEVERSION-$KUBEVERSION_DEFAULT} /hyperkube kubelet --api-servers=http://localhost:8080 --v=2 --address=0.0.0.0 --enable-server --hostname-override=127.0.0.1 --config=/etc/kubernetes/manifests-multi --cluster-dns=${CLUSTER_DNS-$CLUSTER_DNS_DEFAULT} --cluster-domain=${CLUSTER_DOMAIN-$CLUSTER_DOMAIN_DEFAULT}
echo "Starting kubernetes proxy"
docker run -d --net=host --privileged gcr.io/google_containers/hyperkube:${KUBEVERSION-$KUBEVERSION_DEFAULT} /hyperkube proxy --master=http://127.0.0.1:8080 --v=2

# Download kubectl
wget http://storage.googleapis.com/kubernetes-release/release/v1.0.3/bin/linux/amd64/kubectl
chmod +x /kubectl


# Install UI
sleep 10 
echo "Installing kube-ui"
CURDIR=`pwd`
TMPDIR=`mktemp -d`
cd ${TMPDIR}
wget https://raw.githubusercontent.com/kubernetes/kubernetes/22b8197a4a48ffca07784cee35d870872f1e69a8/cluster/addons/kube-ui/kube-ui-svc.yaml
wget https://raw.githubusercontent.com/kubernetes/kubernetes/22b8197a4a48ffca07784cee35d870872f1e69a8/cluster/addons/kube-ui/kube-ui-rc.yaml
/kubectl --namespace=kube-system create -f ${TMPDIR}/kube-ui-rc.yaml
/kubectl --namespace=kube-system create -f ${TMPDIR}/kube-ui-svc.yaml
cd ${CURDIR}

MASTER_IP=`ifconfig eth0 | grep "inet addr" | awk -F: '{ print $2 }' | awk '{ print $1 }'`
echo " Kube-UI access: http://${MASTER_IP}:8080/ui "
echo "Installation of Kubernetes Master done"

