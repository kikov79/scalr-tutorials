#!/bin/bash
set -o errexit

# Used Variables:
#  CLUSTER_DNS


export DNS_REPLICAS=1

export DNS_DOMAIN=${CLUSTER_DOMAIN:-cluster.local} # specify in startup parameter `--cluster-domain` for containerized kubelet 
DEFAULT_SERVER_IP_DEFAULT="10.1.0.10"
export DNS_SERVER_IP=${CLUSTER_DNS-$DNS_SERVER_IP_DEFAULT}  # specify in startup parameter `--cluster-dns` for containerized kubelet 

MASTER_IP=$(szradm queryenv list-roles --format=json | python -c "import json,os,sys;
roles = json.load(sys.stdin);
for role in roles['roles']:
	if \"KUBERNETES\" in (role['alias'].decode('utf-8').upper()) and \"MASTER\" in (role['alias'].decode('utf-8').upper()):
		print role['hosts'][0]['internal-ip'];
")
echo "Configuring Kubernetes DNS"
export KUBE_SERVER=${MASTER_IP} 
echo " Master IP: ${KUBE_SERVER}"

if [ "$DNS_SERVER_IP" == "$KUBE_SERVER" ]; then
   echo "MASTER_IP and DNS_SERVER_IP match!"
else
	echo "Check for MASTER_IP (${MASTER_IP}) and DNS_SERVER_IP (${DNS_SERVER_IP}) difference"
fi

TMPDIR=$(mktemp -d)
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/skydns-rc.yaml.in -O ${TMPDIR}/skydns-rc.yaml.in
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/skydns-svc.yaml.in -O ${TMPDIR}/skydns-svc.yaml.in

sed -e "s/{{ pillar\['dns_replicas'\] }}/${DNS_REPLICAS}/g;s/{{ pillar\['dns_domain'\] }}/${DNS_DOMAIN}/g;s/{kube_server_url}/${KUBE_SERVER}/g;" ${TMPDIR}/skydns-rc.yaml.in > ${TMPDIR}/skydns-rc.yaml
sed -e "s/{{ pillar\['dns_server'\] }}/${DNS_SERVER_IP}/g" ${TMPDIR}/skydns-svc.yaml.in > ${TMPDIR}/skydns-svc.yaml

echo "Launching DNS Controller"
/kubectl --namespace=kube-system create -f ${TMPDIR}/skydns-rc.yaml
echo "Launching DNS Service"
/kubectl --namespace=kube-system create -f ${TMPDIR}/skydns-svc.yaml

