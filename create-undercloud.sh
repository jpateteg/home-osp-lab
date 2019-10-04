#!/bin/bash
UNDERCLOUD_IP=192.168.0.2
HVM_DEF_GW_OAM=172.16.0.254
UC_OAM_NET=172.16.0.0
UC_OAM_IP=172.16.0.1
# La interfaz local es la que se usara para aprovisionar el Overcloud, en nuestro ambiente dejamos ETH0 en blanco y aprovisionamos ETH1 como interfaz fisica, pero aprovisionaremos por la ETH0
UC_OAM_IF=eth0
UC_OAM_NMSK='24'
UC_PUBLIC_HOST=172.16.0.10
UC_ADMIN_HOST=172.16.0.11
HOST=undercloud
DOMAIN=patenke.com
GEN_CERT='True'
SCH_MAX_ATT=10
CURRENT_TRIPLEO_REPO='https://trunk.rdoproject.org/centos7/current/python2-tripleo-repos-0.0.1-0.20191001113300.9dba973.el7.noarch.rpm'
UC_MTU=1500

#Flujo de Instalacion del Undercloud, iniciamos en el HV, de forma local

# Ambiente
sh ./install-osp14-virt-undercloud.sh


# Creamos llave de ssh para entrar sin clave al undercloud
ssh-keygen

#Esperamos un tiempo prudente a que levante la maquina 

sleep 15

# Copiamos la llave al undercloud
ssh-copy-id root@${UNDERCLOUD_IP}
#Copiamos el resto del flujo al undercloud, donde debe continuar la instalacion

scp create-stack-user.sh root@${UNDERCLOUD_IP}:
# Stack User
ssh root@${UNDERCLOUD_IP} sh create-stack-user.sh 
ssh-copy-id stack@${UNDERCLOUD_IP}
ssh root@${UNDERCLOUD_IP} hostnamectl set-hostname ${HOST}.${DOMAIN}; 
ssh root@${UNDERCLOUD_IP }hostnamectl set-hostname --transient ${HOST}.${DOMAIN}
ssh root@${UNDERCLOUD_IP} yum install -y $CURRENT_TRIPLEO_REPO
ssh stack@${UNDERCLOUD_IP} sudo -E tripleo-repos -b rocky current
ssh stack@${UNDERCLOUD_IP} sudo -E tripleo-repos -b rocky current ceph
ssh stack@${UNDERCLOUD_IP} sudo yum install -y python-tripleoclient ceph-ansible

### Creamos Undercloud.conf basado en el ambiente virtual

echo "[DEFAULT]" > undercloud.conf
echo "undercloud_hostname = ${HOST}.${DOMAIN}" >> undercloud.conf
echo "local_interface = ${UC_OAM_IF}" >> undercloud.conf
echo "local_mtu = $UC_MTU" >> undercloud.conf
echo "local_ip = ${UC_OAM_IP}/${UC_OAM_NMSK}" >> undercloud.conf
echo "undercloud_public_host = ${UC_PUBLIC_HOST}" >> undercloud.conf
echo "undercloud_admin_host = ${UC_ADMIN_HOST}" >> undercloud.conf
echo "undercloud_service_certificate = " >> undercloud.conf
echo "generate_service_certificate = $GEN_CERT" >> undercloud.conf
echo "scheduler_max_attempts = $SCH_MAX_ATT" >> undercloud.conf

echo "" >> undercloud.conf

echo "[ctlplane-subnet]" >> undercloud.conf
echo "cidr = ${UC_OAM_NET}/${UC_OAM_NMSK}" >> undercloud.conf
echo "gateway = $HVM_DEF_GW_OAM" >> undercloud.conf
echo "dhcp_start = 172.16.0.20" >> undercloud.conf
echo "dhcp_end = 172.16.0.120" >> undercloud.conf
echo "inspection_iprange = 172.16.0.150,172.16.0.180" >> undercloud.conf
echo "masquerade = true" >> undercloud.conf


###### Copiamos el archivo de configuracion undercloud.conf al undercloud para empezar la instalacion

scp undercloud.conf stack@${UNDERCLOUD_IP}:

######## Instalamos PIP y Request (por algun motivo no vienen actualizados)
ssh stack@${UNDERCLOUD_IP} sudo yum -y install python-pip
ssh stack@${UNDERCLOUD_IP} sudo pip install  --upgrade pip
ssh stack@${UNDERCLOUD_IP} sudo pip install requests

ssh root@${UNDERCLOUD_IP} yum -y update
ssh root@${UNDERCLOUD_IP} reboot

