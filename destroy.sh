#!/bin/bash

############ Destruir las Instancias
#

for i in $(virsh list --all | grep '^ [0-9]' | awk '{print $1}') ; do virsh destroy $i; done

############ Undefine las instancias

for i in $(virsh list --all | awk '{print $2}' | egrep -v 'Name|^$'); do virsh undefine $i; done

############ Borramos las redes

for i in datacenter traffic oam; do virsh net-destroy $i; virsh net-undefine $i; done


############ Limpiamos las entradas del FW
if firewall-cmd --get-active-zones | grep -q virt
then
  firewall-cmd --delete-zone=virt --permanent
  firewall-cmd --reload
fi

vbmc delete undercloud
vbmc delete overcloud-compute
vbmc delete overcloud-controller
