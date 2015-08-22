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


# Don't change this. Set the Global Var
ETCD_VERSION_DEFAULT="2.0.12"
FLANNEL_NETWORK_DEFAULT="10.1.0.0/16"
KUBEVERSION_DEFAULT="v1.0.3"
CLUSTER_DNS_DEFAULT="10.1.0.10"
CLUSTER_DOMAIN_DEFAULT="cluster.local"

export DEBIAN_FRONTEND=noninteractive

# We'll need it
apt-get install -f bridge-utils

# Setup Docker-Bootstrap
echo "Executing Temporary Docker daemon"
sh -c 'docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null &'

# Set up Flannel on the master node
echo "Stopping Docker"
service docker stop
sleep 10

# Run Flannel
echo "Starting Flannel"
MASTER_IP=$(szradm queryenv list-roles --format=json | python -c "import json,os,sys;
roles = json.load(sys.stdin);
for role in roles['roles']:
	if \"KUBERNETES\" in (role['alias'].decode('utf-8').upper()) and \"MASTER\" in (role['alias'].decode('utf-8').upper()):
		print role['hosts'][0]['internal-ip'];
")
echo "Detected Master IP: ${MASTER_IP} "
if [ "x${MASTER_IP}" == "x" ]; then
   echo "  Master node not found. Is it running?"
   exit -1
fi
TOKEN=`docker -H unix:///var/run/docker-bootstrap.sock run -d --net=host --privileged -v /dev/net:/dev/net quay.io/coreos/flannel:0.5.0 /opt/bin/flanneld --etcd-endpoints=http://${MASTER_IP}:4001 | tail -n1`

sleep 10
echo "  Detected token: ${TOKEN}"
docker -H unix:///var/run/docker-bootstrap.sock exec ${TOKEN} cat /run/flannel/subnet.env > /etc/flannel_subnet.env
if [[ $? -eq 0 ]]; then
	echo " Flannel config loaded"
else
	echo " Flannel config failure. Check if MASTER is running. Last logs:"
    docker -H unix:///var/run/docker-bootstrap.sock logs ${TOKEN}
    exit $?
fi
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

# Start the kubernetes minion
echo "Starting kubernetes minion"
docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  gcr.io/google_containers/hyperkube:${KUBEVERSION-$KUBEVERSION_DEFAULT} /hyperkube kubelet --api-servers=http://${MASTER_IP}:8080 --v=2 --address=0.0.0.0 --enable-server --hostname-override=$(hostname -i) --cluster-dns=${CLUSTER_DNS-$CLUSTER_DNS_DEFAULT} --cluster-domain=${CLUSTER_DOMAIN-$CLUSTER_DOMAIN_DEFAULT}
echo "Starting kubernetes proxy"
docker run -d --net=host --privileged gcr.io/google_containers/hyperkube:${KUBEVERSION-$KUBEVERSION_DEFAULT} /hyperkube proxy --master=http://127.0.0.1:8080 --v=2

# Download kubectl
wget http://storage.googleapis.com/kubernetes-release/release/${KUBEVERSION-$KUBEVERSION_DEFAULT}/bin/linux/amd64/kubectl
chmod +x kubectl

#!/bin/bash
# Author: Francisco Gimeno 
# Date: 20150819
# Instructions from https://github.com/kubernetes/kubernetes/blob/master/docs/getting-started-guides/docker-multinode/master.md

# Used variables:
#   ETCD_VERSION: 2.0.12
#   FLANNEL_NETWORK: 10.1.0.0/16
#   KUBEVERSION: v1.0.3
#   CLUSTER_DNS: 10.1.0.10
#   CLUSTER_DOMAIN: cluster.local


# Don't change this. Set the Global Var
ETCD_VERSION_DEFAULT="2.0.12"
FLANNEL_NETWORK_DEFAULT="10.1.0.0/16"
KUBEVERSION_DEFAULT="v1.0.3"
CLUSTER_DNS_DEFAULT="10.1.0.10"
CLUSTER_DOMAIN_DEFAULT="cluster.local"

export DEBIAN_FRONTEND=noninteractive

# We'll need it
apt-get install -f bridge-utils

# Setup Docker-Bootstrap
echo "Executing Temporary Docker daemon"
sh -c 'docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null &'

# Set up Flannel on the master node
echo "Stopping Docker"
service docker stop
sleep 10

# Run Flannel
echo "Starting Flannel"
MASTER_IP=$(szradm queryenv list-roles --format=json | python -c "import json,os,sys;
roles = json.load(sys.stdin);
for role in roles['roles']:
	if \"KUBERNETES\" in (role['alias'].decode('utf-8').upper()) and \"MASTER\" in (role['alias'].decode('utf-8').upper()):
		print role['hosts'][0]['internal-ip'];
")
echo "Detected Master IP: ${MASTER_IP} "
if [ "x${MASTER_IP}" == "x" ]; then
   echo "  Master node not found. Is it running?"
   exit -1
fi
TOKEN=`docker -H unix:///var/run/docker-bootstrap.sock run -d --net=host --privileged -v /dev/net:/dev/net quay.io/coreos/flannel:0.5.0 /opt/bin/flanneld --etcd-endpoints=http://${MASTER_IP}:4001 | tail -n1`

sleep 10
echo "  Detected token: ${TOKEN}"
docker -H unix:///var/run/docker-bootstrap.sock exec ${TOKEN} cat /run/flannel/subnet.env > /etc/flannel_subnet.env
if [[ $? -eq 0 ]]; then
	echo " Flannel config loaded"
else
	echo " Flannel config failure. Check if MASTER is running. Last logs:"
    docker -H unix:///var/run/docker-bootstrap.sock logs ${TOKEN}
    exit $?
fi
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

# Start the kubernetes minion
echo "Starting kubernetes minion"
docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  gcr.io/google_containers/hyperkube:${KUBEVERSION-$KUBEVERSION_DEFAULT} /hyperkube kubelet --api-servers=http://${MASTER_IP}:8080 --v=2 --address=0.0.0.0 --enable-server --hostname-override=$(hostname -i) --cluster-dns=${CLUSTER_DNS-$CLUSTER_DNS_DEFAULT} --cluster-domain=${CLUSTER_DOMAIN-$CLUSTER_DOMAIN_DEFAULT}
echo "Starting kubernetes proxy"
docker run -d --net=host --privileged gcr.io/google_containers/hyperkube:${KUBEVERSION-$KUBEVERSION_DEFAULT} /hyperkube proxy --master=http://127.0.0.1:8080 --v=2

# Download kubectl
wget http://storage.googleapis.com/kubernetes-release/release/${KUBEVERSION-$KUBEVERSION_DEFAULT}/bin/linux/amd64/kubectl
chmod +x kubectl






