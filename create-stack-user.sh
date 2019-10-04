#!/bin/bash
STACK_PASSWD='adminadmin'
echo "Creando Usuario Stack"
useradd stack
echo "Colocando el password de Stack"
echo "$STACK_PASSWD" | passwd --stdin stack
echo "Colocamos a stack en sudoers"
echo "stack ALL=(root) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/stack
sudo chmod 0440 /etc/sudoers.d/stack

