#! /bin/bash
CLASSROOM_SERVER=192.168.100.236
IMAGES_DIR=/var/lib/libvirt/images
OFFICIAL_IMAGE=CentOS-7-x86_64-GenericCloud.qcow2
PASSWORD_FOR_VMS='9RPTT2I3RC/hdvGz'
VIRT_DOMAIN='patenke.com'

### Creamos las redes que usaremos en el ambiente.

cat > /tmp/oam.xml <<EOF
<network>
  <name>oam</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address="172.16.0.254" netmask="255.255.255.0"/>
  <ip address="192.0.2.254" netmask="255.255.255.0"/>
</network>
EOF

cat > /tmp/traffic.xml <<EOF
<network>
  <name>traffic</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address="192.168.0.1" netmask="255.255.255.0"/>
</network>
EOF

cat > /tmp/datacenter.xml <<EOF
<network>
  <name>datacenter</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address="10.1.100.0" netmask="255.255.255.0"/>
</network>
EOF

for NETWORK in oam traffic datacenter
do
  virsh net-define /tmp/${NETWORK}.xml
  virsh net-autostart ${NETWORK}
  virsh net-start ${NETWORK}
done

# Agregamos las reglas del firewall para el hipervisor
firewall-cmd --new-zone=virt --permanent
firewall-cmd --zone=virt --add-source=172.16.0.0/24 --permanent
firewall-cmd --zone=virt --add-source=192.0.2.0/24 --permanent
firewall-cmd --zone=virt --add-source=192.168.0.0/24 --permanent
firewall-cmd --zone=virt --add-source=10.1.100.0/24 --permanent
firewall-cmd --zone=virt --set-target=ACCEPT --permanent
firewall-cmd --reload


# Creamos las maquinas virtuales


# Definimos las interfaces fisicas que tendra el undercloud, deberia ser una hacia adentro del hipervisor y una que se use para aprovisionar posteriormente al overlcoud

cat > /tmp/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="none"
ONBOOT="no"
TYPE="Ethernet"
NM_CONTROLLED="no"
EOF

cat > /tmp/ifcfg-eth1 << EOF
DEVICE="eth1"
BOOTPROTO="none"
ONBOOT="yes"
TYPE="Ethernet"
IPADDR=192.168.0.2
NETMASK=255.255.255.0
GATEWAY=192.168.0.1
NM_CONTROLLED="no"
DNS1=8.8.8.8
EOF

# Definimos el /etc/hosts del undercloud
cat > /tmp/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

${CLASSROOM_SERVER}  hvm.patenke.com hvm
EOF

cd $IMAGES_DIR

qemu-img create -f qcow2 undercloud.qcow2 55G

virt-resize --expand /dev/sda1 ${OFFICIAL_IMAGE} undercloud.qcow2

virt-customize -a undercloud.qcow2 \
  --hostname undercloud.patenke.com \
  --root-password password:${PASSWORD_FOR_VMS} \
  --uninstall cloud-init \
  --copy-in /tmp/hosts:/etc/ \
  --copy-in /tmp/ifcfg-eth0:/etc/sysconfig/network-scripts/ \
  --copy-in /tmp/ifcfg-eth1:/etc/sysconfig/network-scripts/ \
  --selinux-relabel

virt-install --ram 8192 --vcpus 2 --os-variant centos7.0 \
  --disk path=${IMAGES_DIR}/undercloud.qcow2,device=disk,bus=virtio,format=qcow2 \
  --import \
  --network network:oam \
  --network network:traffic \
  --name undercloud \
  --vnc \
  --noautoconsole \
  --cpu host,+vmx

#### Creamos el disco en blanco para el overcloud

for VM in compute-node controller-node
do
qemu-img create -f qcow2 -o preallocation=metadata ${VM}.qcow2 10G
done

##### Creamos las maquinas virtuales para el overcloud, por limite de recursos asignaremos 16GB RAM al controller y 7GB RAM al Compute Node

virt-install --ram 16384 --vcpus 4 --os-variant centos7.0 \
  --disk path=${IMAGES_DIR}/controller-node.qcow2,device=disk,bus=virtio,format=qcow2 \
  --import \
  --network network:oam \
  --network network:traffic \
  --network network:datacenter \
  --vnc \
  --name controller-node \
  --noautoconsole \
  --cpu host,+vmx

virt-install --ram 7168 --vcpus 40 --os-variant centos7.0 \
  --disk path=${IMAGES_DIR}/compute-node.qcow2,device=disk,bus=virtio,format=qcow2 \
  --import \
  --network network:oam \
  --network network:traffic \
  --network network:datacenter \
  --vnc \
  --name compute-node \
  --noautoconsole \
  --cpu host,+vmx

############ El overcloud se instala inicialmente via IPMI, por lo que al ser un ambiente virtual, debemos simular el IPMI, con VBMC es posible hacerlo. VirtualBMC debe estar instalado. el paquete es python2-virtualbmc-1.4.0-2.el7.noarch

vbmc add undercloud --port 6230
vbmc add controller-node --port 6231
vbmc add compute-node --port 6232

############## Creamos el script para inicializar el VBMC

cat >/root/vbmc-start.sh <<EOF
vbmc start undercloud
vbmc start overcloud-controller
vbmc start overcloud-compute
EOF

chmod 755 /root/vbmc-start.sh


echo "Se ha creado el ambiente"

virsh list --all
virsh net-list
vbmc list

echo "Para iniciar controladores IPMI en el ambiente ejecutar /root/vbmc-start"
