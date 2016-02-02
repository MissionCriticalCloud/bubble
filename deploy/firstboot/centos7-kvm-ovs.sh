#!/bin/bash
# Configure KVM Hypervisor with openvswitch and STT (CentOS 7)
# Fred Neubauer / Remi Bergsma

# Bring the second nic down to avoid routing problems
ip link set dev eth1 down

### Settings ####
# BetaCloud pub vlan
VLANPUB=50

# Bubble NSX Ctrl
NSXMANAGER="192.168.22.83"

# Disable selinux (for now...)
setenforce permissive
sed -i "/SELINUX=enforcing/c\SELINUX=permissive" /etc/selinux/config

# Disable firewall (for now..)
systemctl stop firewall
systemctl disable firewalld

# Install dependencies for KVM on Cloudstack
sleep 5
yum -y install http://mirror.karneval.cz/pub/linux/fedora/epel/epel-release-latest-7.noarch.rpm
yum -y install qemu-kvm libvirt libvirt-python net-tools bridge-utils vconfig setroubleshoot virt-top virt-manager openssh-askpass wget vim
yum -y install http://jenkins.buildacloud.org/job/package-centos7-master/lastSuccessfulBuild/artifact/dist/rpmbuild/RPMS/x86_64/cloudstack-common-4.7.0-SNAPSHOT.el7.centos.x86_64.rpm
yum -y install http://jenkins.buildacloud.org/job/package-centos7-master/lastSuccessfulBuild/artifact/dist/rpmbuild/RPMS/x86_64/cloudstack-agent-4.7.0-SNAPSHOT.el7.centos.x86_64.rpm
yum --enablerepo=epel -y install sshpass

# Enable rpbind for NFS
systemctl enable rpcbind
systemctl start rpcbind

# NFS to mct box
mkdir -p /data
mount -t nfs 192.168.22.1:/data /data
echo "192.168.22.1:/data /data nfs rw,hard,intr,rsize=8192,wsize=8192,timeo=14 0 0" >> /etc/fstab

# Enable nesting
echo "options kvm_intel nested=1" >> /etc/modprobe.d/kvm-nested.conf

# Cloudstack agent.properties settings
cp -pr /etc/cloudstack/agent/agent.properties /etc/cloudstack/agent/agent.properties.orig

# Add these settings (before adding the host)
echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cloudstack/agent/agent.properties
echo "network.bridge.type=openvswitch" >> /etc/cloudstack/agent/agent.properties
echo "guest.cpu.mode=host-model" >> /etc/cloudstack/agent/agent.properties

# Set the logging to DEBUG
sed -i 's/INFO/DEBUG/g' /etc/cloudstack/agent/log4j-cloud.xml

# Libvirtd parameters for Cloudstack
echo 'listen_tls = 0' >> /etc/libvirt/libvirtd.conf
echo 'listen_tcp = 1' >> /etc/libvirt/libvirtd.conf
echo 'tcp_port = "16509"' >> /etc/libvirt/libvirtd.conf
echo 'mdns_adv = 0' >> /etc/libvirt/libvirtd.conf
echo 'auth_tcp = "none"' >> /etc/libvirt/libvirtd.conf

# qemu.conf parameters for Cloudstack
sed -i -e 's/\#vnc_listen.*$/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf

# Create new initrd to disable co-mounts
sed -i "/JoinControllers/c\JoinControllers=''" /etc/systemd/system.conf
new-kernel-pkg --mkinitrd --install `uname -r`

### OVS ###
# Rename builtin openvswitch module, add custom OVS package with STT support and start it
mv "/lib/modules/$(uname -r)/kernel/net/openvswitch/openvswitch.ko" "/lib/modules/$(uname -r)/kernel/net/openvswitch/openvswitch.org"
yum -y install "kernel-devel-$(uname -r)"
yum -y install http://mctadm1/openvswitch/openvswitch-dkms-2.4.1-1.el7.centos.x86_64.rpm
yum -y install http://mctadm1/openvswitch/openvswitch-2.4.1-1.el7.centos.x86_64.rpm

# Bridges
systemctl start openvswitch
echo "Creating bridges cloudbr0 and cloudbr1.."
ovs-vsctl add-br cloudbr0
ovs-vsctl add-br cloudbr1
ovs-vsctl add-br cloud0

# Get interfaces
IFACES=$(ls /sys/class/net | grep -E '^em|^eno|^eth|^p2' | tr '\n' ' ')

# Create Bond with them
echo "Creating bond with $IFACES"
ovs-vsctl add-bond cloudbr0 bond0 $IFACES

# Integration bridge
echo "Creating NVP integration bridge br-int"
ovs-vsctl -- --may-exist add-br br-int\
            -- br-set-external-id br-int bridge-id br-int\
            -- set bridge br-int other-config:disable-in-band=true\
            -- set bridge br-int fail-mode=secure

# Fake bridges
echo "Create fake bridges"
#ovs-vsctl -- add-br trans0 cloudbr0 $VLANTRANS
ovs-vsctl -- add-br trans0 cloudbr0
ovs-vsctl -- add-br pub0 cloudbr0 $VLANPUB

# Network configs
BRMAC=$(cat /sys/class/net/$(ls /sys/class/net | grep -E '^em|^eno|^eth|^p2' | tr '\n' ' ' | awk {'print $1'})/address)

# Physical interfaces
for i in $IFACES
  do echo "Configuring $i..."
  echo "DEVICE=$i
ONBOOT=yes
NETBOOT=yes
IPV6INIT=no
BOOTPROTO=none
NM_CONTROLLED=no
" > /etc/sysconfig/network-scripts/ifcfg-$i
done

# Config cloudbr0
echo "Configuring cloudbr0"
echo "DEVICE=\"cloudbr0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSBridge
BOOTPROTO=dhcp
HOTPLUG=no
MACADDR=$BRMAC
" > /etc/sysconfig/network-scripts/ifcfg-cloudbr0

# Config cloud0
echo "Configuring cloud0"
echo "DEVICE=\"cloud0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSBridge
IPADDR=169.254.0.1
NETMASK=255.255.0.0
BOOTPROTO=static
HOTPLUG=no
" > /etc/sysconfig/network-scripts/ifcfg-cloud0

# Config trans0
echo "Configuring trans0"
echo "DEVICE=\"trans0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSIntPort
BOOTPROTO=dhcp
HOTPLUG=no
#MACADDR=$BRMAC
" > /etc/sysconfig/network-scripts/ifcfg-trans0

# Config bond0
echo "Configuring bond0"
echo "DEVICE=\"bond0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSBond
OVS_BRIDGE=cloudbr0
BOOTPROTO=none
BOND_IFACES=\"$IFACES\"
#OVS_OPTIONS="bond_mode=balance-tcp lacp=active other_config:lacp-time=fast"
HOTPLUG=no
" > /etc/sysconfig/network-scripts/ifcfg-bond0

echo "Generate OVS certificates"
cd /etc/openvswitch
ovs-pki req ovsclient
ovs-pki self-sign ovsclient
ovs-vsctl -- --bootstrap set-ssl \
            "/etc/openvswitch/ovsclient-privkey.pem" "/etc/openvswitch/ovsclient-cert.pem"  \
            /etc/openvswitch/vswitchd.cacert

# NSX
echo "Point manager to NSX controller"
ovs-vsctl set-manager ssl:$NSXMANAGER:6632

### End OVS ###
ifup cloudbr0

# Reboot
reboot
