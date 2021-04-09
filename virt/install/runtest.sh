#!/bin/bash

# Source the common test script helpers
. /usr/bin/rhts_environment.sh
. /usr/local/bin/rhts_virt_funcs.sh
. /usr/share/beakerlib/beakerlib.sh

result=PASS
value=0
kvm_num=0
home_basedir=0
# control where to log debug messages to:
# devnull = 1 : log to /dev/null
# devnull = 0 : log to file specified in ${DEBUGLOG}
devnull=0
mkdir -p /home/virtimages/VirtualMachines

# Create debug log
DEBUGLOG=`mktemp -p /mnt/testarea -t virtinstall.XXXXXX`

# locking to avoid races
lck=$OUTPUTDIR/$(basename $0).lck

# Log a message to the ${DEBUGLOG} or to /dev/null
function DeBug ()
{
    local msg="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    if [ "$devnull" = "0" ]; then
	    echo -n "${timestamp}: " >>$DEBUGLOG 2>&1
	    echo "${msg}" >>$DEBUGLOG 2>&1
    else
	echo "${msg}" >/dev/null 2>&1
    fi
}

function SelectKernel ()
{
    DeBug "Enter SelectKernel"
    VR=$1
    EXTRA=$2
    DeBug "VR=$VR EXTRA=$EXTRA"

    # If not version or Extra selected then choose the latest installed version
    if [ -z "$EXTRA" -a -z "$VR" ]; then
	DeBug "ERROR: missing args"
	return 1
    fi

    # Workaround for broken RT kernel spec file, part 1
    if [ "$EXTRA" = "rt" ]; then
	DeBug "EXTRA=$EXTRA"
	EXTRA=""
    fi

    # Workaround for broken RT kernel spec file, part 2
    if [ "$EXTRA" = "rt-vanilla" ]; then
	DeBug "EXTRA=$EXTRA"
	EXTRA="vanilla"
    fi

    # Workaround for broken RT kernel spec file, part 1
    if [ "$EXTRA" = "up" ]; then
	DeBug "EXTRA=$EXTRA"
	EXTRA=""
    fi

    echo "***** Attempting to switch boot kernel to ($VR$EXTRA) *****" | tee -a $OUTPUTFILE
    DeBug "Attempting to switch boot kernel to ($VR$EXTRA)"

    grub_file=/boot/grub/grub.conf

    if [ -f $grub_file ]; then
	DeBug "Using: $grub_file"
	COUNT=0
	DEFAULT=undefined
	for i in $(grep '^title' $grub_file | sed 's/.*(\(.*\)).*/\1/'); do
	    DeBug "COUNT=$COUNT VR=$VR EXTRA=$EXTRA i=$i"
	    if echo $i | egrep -e "${VR}.*${EXTRA}" ; then
		DEFAULT=$COUNT;
	    fi
	    COUNT=$(expr $COUNT + 1)
	done
	if [[ x"${DEFAULT}" != x"undefined" ]]; then
	    DeBug "DEFAULT=$DEFAULT"
	    /bin/ed -s $grub_file <<EOF
/default/
d
i
default=$DEFAULT
.
w
q
EOF
	fi
	DeBug "$grub_file"
	cat $grub_file | tee -a $DEBUGLOG
    fi

    elilo_file=/boot/efi/efi/redhat/elilo.conf

    if [ -f $elilo_file ]; then
	DeBug "Using: $elilo_file"
	DEFAULT=$(grep -A 2 "image=vmlinuz-$VR$EXTRA$" $elilo_file | awk -F= '/label=/ {print $2}')
	DeBug "DEFAULT=$DEFAULT"
	if [ -n "$DEFAULT" ]; then
	    DeBug "DEFAULT=$DEFAULT"
	    /bin/ed -s $elilo_file <<EOF
/default/
d
i
default=$DEFAULT
.
w
q
EOF
	fi
	DeBug "$elilo_file"
	cat $elilo_file | tee -a $DEBUGLOG
    fi

    yaboot_file=/boot/etc/yaboot.conf

    if [ -f $yaboot_file ] ; then
	DeBug "Using: $yaboot_file"
	grep vmlinuz $yaboot_file
	if [ $? -eq 0 ] ; then
	    VM=z
	else
	    VM=x
	fi
	DEFAULT=$(grep -A 1 "image=/vmlinu$VM-$VR$EXTRA" $yaboot_file | awk -F= '/label=/ {print $2}')
	DeBug "DEFAULT=$DEFAULT"
	if [ -n "$DEFAULT" ] ; then
	    sed -i 's/label=linux/label=orig-linux/g' $yaboot_file
	    sed -i 's/label='$DEFAULT'/label=linux/g' $yaboot_file
	    DeBug "DEFAULT=$DEFAULT"
	    grep -q label=linux $yaboot_file
	    if [ $? -ne 0 ] ; then
		sed -i 's/label=orig-linux/label=linux/g' $yaboot_file
		DeBug "Reverted back to original kernel"
	    fi
	fi
	DeBug "$yaboot_file"
	cat $yaboot_file | tee -a $DEBUGLOG
    fi

    zipl_file=/etc/zipl.conf

    if [ -f $zipl_file ] ; then
	DeBug "Using: $zipl_file"
	DEFAULT=$(grep "image=/boot/vmlinuz-$VR$EXTRA" $zipl_file | awk -Fvmlinuz- '/vmlinuz/ {printf "%.15s\n",$2}')
	DeBug "DEFAULT=$DEFAULT"
	if [ -n "$DEFAULT" ] ; then
	    DeBug "$VR$EXTRA"
	    tag=$(grep "\[$DEFAULT\]" $zipl_file)
	    DeBug "tag=$tag"
	    if [ -z "$tag" ] ; then
		DeBug "Setting it back to default"
		DEFAULT=linux
	    fi
	    /bin/ed -s $zipl_file <<EOF
/default=/
d
i
default=$DEFAULT
.
w
q
EOF
	    zipl
	fi
	DeBug "$zipl_file"
	cat $zipl_file | tee -a $DEBUGLOG
    fi

    sync
    sleep 5
    DeBug "Exit SelectKernel"
    return 0
}

function fallocate_files ()
{
    local cmdline="$*"
    local file_size=""
    local file_path=""

    if command -v fallocate > /dev/null; then
        echo "Have fallocate"
    else
        echo "Doesn't have fallocate"
        return
    fi

    # --lvm format doesn't need fallocate
    echo $cmdline | grep -- "--lvm" > /dev/null
    if [ $? -eq 0 ]; then
        return
    fi

    # --part format doesn't need fallocate
    echo $cmdline | grep -- "--part" > /dev/null
    if [ $? -eq 0 ]; then
        return
    fi

    # --disk format
    echo $cmdline | grep -- "--disk" > /dev/null
    if [ $? -eq 0 ]; then
        echo $cmdline | grep -o -- "--disk[= ]\S\+" > disks
        while read line; do
            file_path=`echo $line | grep -o "path=[^, ]\+" | sed 's/path=//'`
            file_size=`echo $line | grep -o "size=[^, ]\+" | sed 's/size=//'`
            if [ -n "$file_size" -a -n "$file_path" ]; then
                echo "fallocate -l${file_size}G $file_path"
                fallocate -l${file_size}G $file_path
                if [ $? -ne 0 ]; then
                    echo "fallocate failed, removing file: $file_path"
                    rm -f $file_path
                fi
            fi
        done < disks
    # -s/--file-size and -f and --file format
    else
        file_size=`echo $cmdline | grep -o -- "-s [0-9]\+" | awk '{print $2}'`
        if [ -z "$file_size" ]; then
            file_size=`echo $cmdline | grep -o -- "--file-size[= ][0-9]\+" | sed 's/--file-size[= ]//'`
        fi

        if [ -n "$file_size" ]; then
            file_path=`echo $cmdline | grep -o -- "-f \S\+" | awk '{print $2}'`
            if [ -z "$file_path" ]; then
                file_path=`echo $cmdline | grep -o -- "--file[= ]\S\+" | sed 's/--file[= ]//'`
            fi
        fi
        if [ -n "$file_size" -a -n "$file_path" ]; then
            echo "fallocate -l${file_size}G $file_path"
            fallocate -l${file_size}G $file_path
            if [ $? -ne 0 ]; then
                echo "fallocate failed, removing file: $file_path"
                rm -f $file_path
            fi
        fi
    fi
}

function setuprhel5consoles()
{
    local RESULT="PASS"
    local FAIL=0

    if ! cp zrhel5_write_consolelogs.initd /etc/init.d/zrhel5_write_consolelogs; then
       echo "Problem copying zrhel5_write_consolelogs.initd to initd dir"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! cp zrhel5_write_consolelogs.py /usr/local/bin/zrhel5_write_consolelogs; then
       echo "Problem copying zrhel5_write_consolelogs.py to /usr/local/bin"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi
    if ! chmod 755 /usr/local/bin/zrhel5_write_consolelogs; then
       echo "Problem with chmoding zrhel5_write_consolelogs"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! chkconfig --add zrhel5_write_consolelogs; then
       echo "problem with chkconfig --add zrhel5_write_consolelogs"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! chkconfig zrhel5_write_consolelogs on; then
       echo "problem with chkconfig zrhel5_write_consolelogs on"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    iptables -I INPUT -p tcp --dport 8000 -j ACCEPT
    iptables -I INPUT -p udp --dport 8000 -j ACCEPT
    sleep 1
    if ! service iptables save; then
       echo "Problem with service iptables save"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! cp -f iptables_after_libvirtd.initd /etc/init.d/iptables_after_libvirtd; then
       echo "Problem with copying iptables_after_libvirtd.initd"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! chkconfig --add iptables_after_libvirtd; then
       echo "problem with adding iptables_after_libvirtd"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! chkconfig iptables_after_libvirtd on; then
       echo "problem with chkconfig iptables_after_libvirtd on"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    if ! service iptables_after_libvirtd start; then
       echo "problem with service iptables_after_libvirtd start"
       RESULT="FAIL"
       let "FAIL=${FAIL}+1"
    fi

    echo "Status of iptables: " | tee -a $OUTPUTFILE
    service iptables status >> $OUTPUTFILE 2>&1
    service zrhel5_write_consolelogs start
    sleep 2
    echo "Status of rhel5_write_consoles:" | tee -a $OUTPUTFILE
    service zrhel5_write_consolelogs status >> $OUTPUTFILE 2>&1
    echo "Initial log output:" | tee -a $OUTPUTFILE
    cat /nohup.out | tee -a $OUTPUTFILE
    if [[ ${FAIL} -gt 0 ]]; then
       report_result ${TEST}_zrhel5_write_consolelogs WARN $FAIL
       return -1
    else
       report_result ${TEST}_zrhel5_write_consolelogs PASS 0
       return 0
    fi

}

function setupconsolelogs()
{
	local RESULT="PASS"
	local FAIL=0
	if ! gcc -g -Wall logguestconsoles.c -o logguestconsoles -lssl -lcrypto -lcurl $(xmlrpc-c-config client --libs) -lxmlrpc_util $(pkg-config libvirt --libs) $(xml2-config --cflags) $(xml2-config --libs); then
		echo "Problem with compiling logguestconsoles.c file"
		echo "Guest console logs won't be available"
		RESULT="FAIL"
		let "FAIL=${FAIL}+1"
	fi

	if ! cp logguestconsoles /usr/local/bin; then
		echo "Problem with copying logguestconsoles to /usr/local/bin"
		echo "Guest console logs won't be available"
		RESULT="FAIL"
		let "FAIL=${FAIL}+1"
	fi

	if ! cp logguestconsoles.initd /etc/init.d/logguestconsoles; then
		echo "problem with copying init script"
		RESULT="FAIL"
		let "FAIL=${FAIL}+1"
	fi

	if ! chkconfig --add logguestconsoles; then
		echo "problem with chkconfig --add logguestconsoles"
		RESULT="FAIL"
		let "FAIL=${FAIL}+1"
	fi

	# libvirt introduced rotating logs at the end of 2015
	# This breaks logguestconsoles, because it keeps checking fd
	# that is no longer getting any updates.
	grep -q "stdio_handler =" /etc/libvirt/qemu.conf
	if [ $? -eq 0 ]; then
		# comment any current setting
		sed -i 's/\(^stdio_handler =.*\)/#\1/' /etc/libvirt/qemu.conf
		# and use non-rotating logs
		echo 'stdio_handler = "file"' >> /etc/libvirt/qemu.conf
		restorecon /etc/libvirt/qemu.conf
		service libvirtd restart
	fi

	if [[ ${FAIL} -gt 0 ]]; then
		report_result ${TEST}_consolelogsetup WARN $FAIL
        	return 1
	else
		report_result ${TEST}_consolelogsetup PASS 0
        	return 0
	fi
}

function setuprhel5_xmlrpcc()
{
        local SRCRPM="xmlrpc-c.el5.src.rpm"
        local FAIL=0
        local OUTPUTLOG="./setuprhel5_xmlrpcc.log"

        if ! rpm -ivh ${LOOKASIDE}/${SRCRPM}; then
                echo "problem with rpm -ivh ${LOOKASIDE}/${SRCRPM}"
                FAIL=$(expr ${FAIL} + 1)
        fi

        exec 5>&1 6>&2
        exec >> ${OUTPUTLOG} 2>&1

        if ! rpmbuild -ba /usr/src/redhat/SPECS/xmlrpc-c.spec; then
                echo "problem with rpmbuild -ba /usr/src/redhat/SPECS/xmlrpc-c.spec"
                FAIL=$(expr ${FAIL} + 1)
        fi

        if ! rpm -Uvh /usr/src/redhat/RPMS/$(arch)/xmlrpc-c*.rpm; then
                echo "problem with rpm -Uvh /usr/src/redhat/RPMS/$(arch)/xmlrpc-c*.rpm"
                FAIL=$(expr ${FAIL} + 1)
        fi

        exec 1>&5 5>&-
        exec 2>&6 6>&-

        if [[ ${FAIL} -gt 0 ]]; then
                report_result ${TESTNAME}_setuprhel5_xmlrpcc FAIL 1
        else
                report_result ${TESTNAME}_setuprhel5_xmlrpcc PASS 0
        fi
        rhts_submit_log ${OUTPUTLOG}
}



function rename_current_ifcfg_config()
{
    if rlIsRHEL '>=9' ; then
        local cfg_file=/etc/NetworkManager/system-connections/${netdev}.nmconnection
        local ret=0
        if [ -e "$cfg_file" ]; then
            echo "Found $cfg_file, trying to rename" | tee -a $OUTPUTFILE
            cp -vf $cfg_file /etc/NetworkManager/system-connections/X${netdev}.nmconnection.orig >> $OUTPUTFILE
            ret=$?
        else
            ret=1
        fi
    else
        local cfg_file=/etc/sysconfig/network-scripts/ifcfg-$netdev
        local ret=0
        if [ -e "$cfg_file" ]; then
            echo "Found $cfg_file, trying to rename" | tee -a $OUTPUTFILE
            mv -vf $cfg_file /etc/sysconfig/network-scripts/Xifcfg-${netdev}.orig >> $OUTPUTFILE
            ret=$?
        else
            # Bug 845225 - interface name does not match ifcfg- config file name
            echo "Could not find $cfg_file, searching for one based on MAC" | tee -a $OUTPUTFILE
            local ifcfg_files=`grep -l "${mac}" /etc/sysconfig/network-scripts/ifcfg-*`
            echo "Matching config files: $ifcfg_files" | tee -a $OUTPUTFILE
            for cfg_file in $ifcfg_files; do
                bn=`basename $cfg_file`
                mv -vf $cfg_file /etc/sysconfig/network-scripts/X$bn.orig >> $OUTPUTFILE
                if [ $? -ne 0 ]; then
                    ret=1
                fi
            done
        fi
    fi
    return $ret
}

function isRHEL7()
{
    rpm -qa initscripts | grep -q "\.el7"
    return $?
}

# Bug 1292921 - [BUG] /etc/xen/scripts/block remove fails - causes loopback exhaustion
function workaround_bug1292921()
{
    if ! grep -q "options loop max_loop=" /etc/modprobe.conf; then
        echo "options loop max_loop=64" >> /etc/modprobe.conf
        if ! cat /proc/modules  | awk '{ print $1 }' | grep ^loop$; then
            rmmod loop
            modprobe loop
        fi
        # log it but don't warn or fail because of it.
        report_result bug1292921 PASS 0
    fi
}

# Bug 871800 - virt-install with option --vnc fails: qemu-kvm: Could not read keymap file: 'en-us'
function workaround_bug871800()
{
    yum list installed "qemu-kvm-common*"
    if [ $? -ne 0 ]; then
        echo "Bug 871800, qemu-kvm-common is not installed, trying to install.." | tee -a $OUTPUTFILE
        yum -y install "qemu-kvm-common*" >> $OUTPUTFILE 2>&1
        report_result bug871800 FAIL 1
    fi
}

# Bug 901542 - qemu doesn't depend on seabios-bin, resulting in error: "qemu: PC system firmware (pflash) must be a multiple of 0x1000"
function workaround_bug901542()
{
    uname -m | grep -q x86 || return
    yum list installed seabios-bin
    local ret2=$?
    if [ $ret2 -ne 0 ]; then
        echo "Bug 901542, seabios/seabios-bin is not installed, trying to install.." | tee -a $OUTPUTFILE
        yum -y install seabios seabios-bin >> $OUTPUTFILE 2>&1
        report_result bug901542 FAIL 1
    fi
}

# Bug 958860 - Could not access KVM kernel module: Permission denied
function workaround_bug958860()
{
    local rights=`stat --format=%a /dev/kvm | tail -c 4`
    if [ "${rights:0:1}" -lt "6" -o "${rights:1:1}" -lt "6" -o "${rights:2:1}" -lt "6" ]; then
        echo "Bug 958860 - Could not access KVM kernel module, chmod-ing to 0666" | tee -a $OUTPUTFILE
        chmod 666 /dev/kvm >> $OUTPUTFILE 2>&1
        report_result bug958860 FAIL 1
    fi
}

# Bug 957897 - service network start won't start network
function workaround_bug957897()
{
    if [ ! -e /etc/sysconfig/network ]; then
        echo "Bug 957897 - service network start won't start network, touching /etc/sysconfig/network" | tee -a $OUTPUTFILE
        touch /etc/sysconfig/network >> $OUTPUTFILE 2>&1
        restorecon /etc/sysconfig/network
        report_result bug957897 FAIL 1
    fi
}

function XENbridge ()
{
    Debug "Enter XENbridge"

    echo "" >> $OUTPUTFILE
    echo "***** INFO: RHEL5 configuring the XEN bridge with correct network device" >> $OUTPUTFILE

    local xen_netdev="$1"
    local xen_script="/etc/xen/scripts/network-xenbridge"
    local xen_config="/etc/xen/xend-config.sxp"
    local run_script="/etc/xen/scripts/network-bridge"

    # set the correct network device for the bridge
    local bridge=$(echo ${xen_netdev} | sed 's/^[^0-9]*//')
    local xen_bridge="xenbr${bridge}"

    # comment out the default script (network-script network-bridge)
    # add line to $xen_config file that will run the script required
    # to build the XEN bridge using the correct network device
    sed -i "s/^(network-script network-bridge)/## (network-script network-bridge)/" $xen_config
    sed -i "/^## (network-script network-bridge)/a (network-script 'network-xenbridge netdev=$xen_netdev bridge=$xen_bridge')" $xen_config

    # create script to build the XEN bridge with correct network device on boot
    cat >> $xen_script <<EOF
#!/bin/sh
# /etc/xen/scripts/network-xenbridge
# RHEL5 last network device up is default network device
/sbin/ifdown $xen_netdev
/sbin/ifup $xen_netdev
# Build the xen bridge
$run_script start netdev=$xen_netdev bridge=$xen_bridge
exit
EOF

    if [ ! -e $xen_script ]; then
        echo "" >> $OUTPUTFILE
        echo "***** FAIL: unable to create $xen_script" >> $OUTPUTFILE
        echo "" >> $OUTPUTFILE
        report_result ${TEST}_XENbridge FAIL
    fi

    # our script need be executable
    chmod +x $xen_script
    if [ "$?" -ne "0" ]; then
        echo "" >> $OUTPUTFILE
        echo "***** FAIL: chmod +x $xen_script" >> $OUTPUTFILE
        echo "" >> $OUTPUTFILE
        report_result ${TEST}_XENbridge FAIL
    fi

    # system is rebooted by design in main
    echo "***** configuration of XEN bridge complete" >> $OUTPUTFILE
    echo "***** reboot is required" >> $OUTPUTFILE

    Debug "Exit XENbridge"
}

function ConfirmXenNetDevices ()
{
    # RHEL5 brings up all the network devices and sets
    # the last network device to come up as the default.
    # ConfirmXenNetDevices:
    # Confirms the network installation device
    # is set as the default network device.
    # This is required for proper network bridging on XEN guests.

    DeBug "Enter ConfirmXenNetDevices"

    # run for RHEL5 only
    local rhel5_ver="2.6.18"
    local kernel_ver=`rpm -q --queryformat '%{version}\n' -qf /boot/config-$(uname -r)`

    if [ "$rhel5_ver" == "$kernel_ver" ]; then
        echo "" >> $OUTPUTFILE
        echo "***** INFO: RHEL5 verifying the the network installation device is set as the default network device" >> $OUTPUTFILE

        if [ ! -e /root/anaconda-ks.cfg ]; then
            echo "" >> $OUTPUTFILE
            echo "***** WARN: /root/anaconda-ks.cfg file is missing" >> $OUTPUTFILE
            echo "" >> $OUTPUTFILE
            report_result ${TEST}_ConfirmXenNetDevices WARN
        else
            echo "" >> $OUTPUTFILE
            echo "***** confirming system network installation device" >> $OUTPUTFILE
            echo "***** checking /root/anaconda-ks.cfg" >> $OUTPUTFILE
            local installdev=$(grep -oP "(?<=--device )[^ ]+" /root/anaconda-ks.cfg)
            # are you NULL
            if [ "x${installdev}" == "x" ]; then
                echo "" >> $OUTPUTFILE
                echo "***** WARN: unable to confirm system network installation device" >> $OUTPUTFILE
                report_result ${TEST}_ConfirmXenNetDevices WARN
            else
                echo "***** system network installation device = $installdev" >> $OUTPUTFILE
                echo "" >> $OUTPUTFILE
                echo "***** confirming system default network device" >> $OUTPUTFILE
                echo "***** checking route" >> $OUTPUTFILE
                # get systems current default network device
                local defaultdev=$(route | grep default | awk '{print $NF}')
                echo "***** default network device = $defaultdev" >> $OUTPUTFILE
                # confirm install and default network device are the same device
                if [ "$installdev" != "$defaultdev" ]; then
                    echo "" >> $OUTPUTFILE
                    echo "***** install and default network devices are not the same device" >> $OUTPUTFILE
                    echo "***** RHEL5 sets the last device that comes up to the default," >> $OUTPUTFILE
                    echo "***** its likely this system has multiple nics up on the same subnet" >> $OUTPUTFILE
                    echo "" >> $OUTPUTFILE
                    echo "***** setting $installdev to default network device and" >> $OUTPUTFILE
                    echo "***** rebuilding the xen bridge with $installdev" >> $OUTPUTFILE
                    # rebuild the xenbridge with $installdev for our testing
                    XENbridge $installdev
                else
                    echo "" >> $OUTPUTFILE
                    echo "***** system installation device and default network device = $defaultdev" >> $OUTPUTFILE
                    echo "" >> $OUTPUTFILE
                fi
            fi
        fi
    fi

    DeBug "Exit ConfirmXenNetDevices"
}

#
# ---------- Start Test -------------
#

# wordaround RHEL5 issues
if rlIsRHEL 5 && uname -r  | grep -q xen; then
    workaround_bug1292921
fi

# workaround RHEL7 issues
if isRHEL7; then
    workaround_bug871800
    workaround_bug901542
    workaround_bug958860
    workaround_bug957897
fi

chmod 755 *.initd
# if this a test/devel version, create the dirs/scripts other tests might rely on
if [[ x"$(pwd)" != "x/mnt/tests/distribution/virt/install" ]]; then
	mkdir -p /mnt/tests/distribution/virt/install
	cp get_guest_*.py /mnt/tests/distribution/virt/install
	chmod 755 /mnt/tests/distribution/virt/install/*
	perl -pi.bak -e "s#^args=\"\"#args=\"--testdir $(pwd)\"#g" zrhel5_write_consolelogs.initd
fi

# turn on libvirtd debugging log.
TurnOnLibvirtdLogging

## normally this test will run in selinux enforcing mode but sometimes we may
# want to run it in permissive mode to de bug selinux issues:
if [[ -n "${PERMISSIVE_MODE}" ]]; then
	setenforce Permissive
	if [[ $? -ne 0 ]] ; then
		echo "Problem with setting enforcing to permissive"
		report_result ${TEST}/selinux_permissive FAIL 1
		exit 0
	fi
	perl -pi.bak -e 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
fi

# Add in a variable to workaround virt-install and selinux brokeness
#  See BZ [Bug 475786] [RHEL5.3] SELinux AVC Denied: while trying to write to
#  /.virtinst/virt-install.log
if [ -z $HOME ] ; then
    export HOME=/root
fi

# for rhel5 , there is an issue with ntap-vader.corp autofs settings. So we'll do the workaround here..
# for more info , see RT#58580
# 02092011 UPDATE: same issue resurfaced for rhel6 on RDU boxen, so we'll do workaround for all
#   See: RT#101432
perl -pi.bak -e 's#/net\t-hosts#/net\tauto.net#g' /etc/auto.master
if ! service autofs restart; then
	echo "problem restarting autofs after editing /etc/auto.master"
	report_result ${TEST}_autofssetup FAIL 1
fi

# starting with rhel 5.4 we'll have both xen and kvm hypervisors shipped with the tree.
# This test will be used to install guests under both hypervisors hence it needs to
# identify what it is doing. @virtualization group pulls in packages/kernels for both
# hypervisors and by default kernel-xen is selected which means any guests installed will
# be xen guests. To allow testers to install kvm guestsi, --kvm argument in guest_args
# will be used. It will NOT be allowed to specify both xen or kvm guests. All guests must
# be of one hypervisor. The flow will be:
#
#    Check if this is rhel6 installation or not. If it is, then just assume all kvm guests
#      with or without --kvm indicators.
#
#    If this is rhel5 then, figure what type of guests there are
#     - Make sure that ALL guests are of the same type
#     - if kvm:
#          check the running kernel
#            if baremetal, move on
#            if xen, switch to baremetal kernel and rhts-reboot
#     - if xen:
#          check the running kernel
#            if not kernel-xen error out (it should be the default)
#            if xen, make changes to xend files and rhts-reboot
#     - install guests.
if ver=$(rpm -q --qf '%{version}\n' --whatprovides redhat-release | sed 's/[A-Za-z]*//g'); then
	if [[ ${ver%%.*} -ge 6 ]]; then
		kvm_num=1
	else
		# ensure that they all are either xen or kvm
        if ! kvm_num=$(./get_guest_info.py --kvm-num) ; then
			echo "can't mix up kvm and non-kvm guests. They all have to be kvm or nonkvm" >> $OUTPUTFILE
			report_result ${TEST}_wrongguestsetup FAIL 1
			submitvirtlogs
			exit 1
		fi
	fi
fi

# For some reason some f17 jobs didn't install expect
# workaround for it:
if ! rpm -q expect; then
	yum -y install expect
	if ! rpm -q expect; then
		echo "Can't find/install expect package"
		report_result ${TEST}_noExpectpkg FAIL 1
		exit 1
	fi
fi

# if this will be kvm guests' install make sure that correct kernel is running.
if [[ ${kvm_num} -gt 0 ]]; then
   if uname -r  | grep xen ; then
      xenkern=$(uname -r)
      basekern=${xenkern%"xen"}
      # if for whatever reason base kernel isn't installed, install it..
      if ! rpm -q kernel-${basekern}; then
         yum -y install kernel-${basekern} kvm
      fi
      # make sure that yum installed it..
      if ! rpm -q kvm; then
         echo "Can't find/install kvm" >> $OUTPUTFILE
         report_result ${TEST}_nokvm FAIL 1
         exit 1
      fi
      echo "this test seems to be for kvm guests, booting into vanilla kernel"
      SelectKernel ${basekern}
      echo "Rebooting into base kernel since this is kvm guest" >> $OUTPUTFILE
      report_result rhts-reboot PASS $REBOOTCOUNT
      rhts-reboot
   fi

   if [[ ${ver%%.*} -ge 6 ]]; then
      # for rhel6 & above we need to set up bridging and get network manager out
      # of the way...

      ## we need to configure/add bridge to establish bridged networking for
      ## kvm guests
      def_line=$(ip route list | grep ^default)
      defnum=$(perl -e 'for ($i=0; $i<$#ARGV; $i++ ) { if ($ARGV[$i] eq "dev" ) { $_ = $ARGV[ $i + 1 ]; if ( /^(\w*)(\d+)/ ) { print "$_ $2"; } } }' ${def_line} )
      actnum=$(echo ${defnum} | awk '{print $2}')
      netdev=$(echo ${defnum} | awk '{print $1}')
      vifnum=${vifnum:-$actnum}
      if [ -z ${vifnum} ]; then
         echo "Can't get the interface number "
         report_result ${TEST}_networksetup FAIL 1
         exit 1
      fi
      brdev="br${vifnum}"
      pdev="p${netdev}"
      mac=`ip link show ${netdev} | grep 'link\/ether' | sed -e 's/.*ether \(..:..:..:..:..:..\).*/\1/'`
      if [ -z ${mac} ]; then
         echo "Can't find the mac address"
         report_result ${TEST}_networksetupnomac FAIL 1
         exit 1
      fi
      echo "brdev: ${brdev} netdev: ${netdev} pdev: ${pdev} mac: ${mac} "

      rename_current_ifcfg_config
      if [[ $? -ne 0 ]]; then
         echo "Problem copying network config scripts"
         report_result ${TEST}_networksetup FAIL 1
         exit 1
      fi
      if rlIsRHEL '>=9' ; then

         nmcli conn add type bridge con-name $brdev ifname $brdev
         nmcli conn mod $brdev 802-3-ethernet.mac-address $mac ipv4.method auto ipv6.method auto connection.autoconnect yes
         nmcli conn mod $netdev master br1 connection.autoconnect yes
         nmcli conn mod $netdev connection.autoconnect yes

      else

         cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$netdev
DEVICE=$netdev
ONBOOT=yes
BRIDGE=$brdev
HWADDR=$mac
EOF

         cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$brdev
DEVICE=$brdev
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Bridge
DELAY=0
EOF
      fi

      if rlIsRHEL '<7' ; then
         service NetworkManager stop
         chkconfig NetworkManager off
         chkconfig network on
         service network restart
      elif rlIsRHEL '<9' ; then
         # Turn on NetworkManager which supports bridging on RHEL7
         systemctl start NetworkManager
         systemctl enable NetworkManager

         /sbin/ifup $brdev
         /sbin/ifup $netdev
         # check connectivity after the change
         connected=0
         tries=30
         while [ $connected -eq 0 -a $tries -gt 0 ]; do
            if rlIsRHEL '<=7.2' ; then
               ping -c 1 "$LAB_CONTROLLER" && connected=1 && break
            else
               ping -c 1 -4 "$LAB_CONTROLLER" && connected=1 && break
            fi
            sleep 1
            tries=$(( tries - 1 ))
         done
         if [ $connected -eq 0 ]; then
            echo "Problem while restoring network on $brdev"
            exit 1
         fi
      else
         # NetworkManager enabled by default
          nmcli conn down $netdev
          nmcli conn reload
          nmcli conn up $netdev
          nmcli conn up $brdev
      fi

      if [[ $? -ne 0 ]]; then
         echo "problem restarting network" | tee -a $OUTPUTFILE
         report_result ${TEST}_networksetup FAIL 1
         exit 1
      else
         echo "configured a bridge: $netdev "
      fi

      # when it's already set up, then get the bridge to use to
      # pass it on to virt-install
      def_line=$(ip route list | grep ^default)
      defnum=$(perl -e 'for ($i=0; $i<$#ARGV; $i++ ) { if ($ARGV[$i] eq "dev" ) { $_ = $ARGV[ $i + 1 ]; if ( /^(\w*)(\d+)/ ) { print "$_ $2"; } } }' ${def_line} )
      actnum=$(echo ${defnum} | awk '{print $2}')
      netdev=$(echo ${defnum} | awk '{print $1}')
      vifnum=${vifnum:-$actnum}
      if [ -z ${vifnum} ]; then
         echo "Can't get the interface number "
         report_result ${TEST}_networksetup FAIL 1
         exit 1
      fi
      brdev="br${vifnum}"

    else
         # we need to configure/add bridge to establish bridged networking for
         # kvm guests

         def_line=$(ip route list | grep ^default)
         defnum=$(perl -e 'for ($i=0; $i<$#ARGV; $i++ ) { if ($ARGV[$i] eq "dev" ) { $_ = $ARGV[ $i + 1 ]; if ( /^(\w*)(\d+)/ ) { print "$_ $2"; } } }' ${def_line} )
         actnum=$(echo ${defnum} | awk '{print $2}')
         netdev=$(echo ${defnum} | awk '{print $1}')
         vifnum=${vifnum:-$actnum}
         if [ -z ${vifnum} ]; then
            echo "Can't get the interface number "
            report_result ${TEST}_networksetup FAIL 1
            exit 1
         fi
         brdev="br${vifnum}"
         pdev="p${netdev}"
         mac=`ip link show ${netdev} | grep 'link\/ether' | sed -e 's/.*ether \(..:..:..:..:..:..\).*/\1/'`
         if [ -z ${mac} ]; then
            echo "Can't find the mac address"
            report_result ${TEST}_networksetupnomac FAIL 1
            exit 1
         fi
         echo "brdev: ${brdev} netdev: ${netdev} pdev: ${pdev} mac: ${mac} "

         rename_current_ifcfg_config
         if [[ $? -ne 0 ]]; then
            echo "Problem copying network config scripts"
            report_result ${TEST}_networksetup FAIL 1
            exit 1
         fi
         cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$netdev
DEVICE=$netdev
ONBOOT=yes
BRIDGE=$brdev
HWADDR=$mac
EOF

         cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$brdev
DEVICE=$brdev
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Bridge
DELAY=0
EOF


         service NetworkManager stop
         chkconfig NetworkManager off
         chkconfig network on
         service network restart
         if [[ $? -ne 0 ]]; then
            echo "problem restarting network"
            report_result ${TEST}_networksetup FAIL 1
            exit 1
         else
           echo "configured a bridge: $netdev "
         fi

   fi

   # see BZ# 749611
   if rpm -q kernel-xen; then
       echo "Removing kernel-xen because of BZ #749611"
       yum -y erase kernel-xen
       rhts-reboot
   fi

else # this is a xen install

   # turn on various logs in xend and restart xend
   if [[ $REBOOTCOUNT -eq 0 ]]; then
      perl -pi.bak -e 's/#*\(enable-dump\s+no\)/(enable-dump yes)/g' /etc/xen/xend-config.sxp
      perl -pi.bak -e 's/^#*XENCONSOLED_LOG_HYPERVISOR=no/XENCONSOLED_LOG_HYPERVISOR=yes/g;s/^#*XENCONSOLED_LOG_GUESTS=no/XENCONSOLED_LOG_GUESTS=yes/g;s/^#*XENCONSOLED_LOG_DIR=.*$/XENCONSOLED_LOG_DIR=\/var\/log\/xen\/console/g' /etc/sysconfig/xend

      echo "" >> $OUTPUTFILE
      echo "***** brctl before reboot" >> $OUTPUTFILE
      brctl show >> $OUTPUTFILE

      # RHEL5 confirm the default network device is correct
      # rebuild the xen bridge, if we are not using correct default
      ConfirmXenNetDevices

      echo "" >> $OUTPUTFILE
      echo "***** reboot needed to enable xen logging and confirm xen bridge" >> $OUTPUTFILE

      report_result rhts-reboot PASS $REBOOTCOUNT
      rhts-reboot
   else
      echo "" >> $OUTPUTFILE
      echo "***** reboot was successful" >> $OUTPUTFILE

      echo "" >> $OUTPUTFILE
      echo "***** brctl after reboot" >> $OUTPUTFILE
      brctl show >> $OUTPUTFILE

      # xen: make sure we pass  --bridge  into the command line for the xen guest installs
      bridge=$(ip route list | awk '/^default / { print $NF }' | sed 's/^[^0-9]*//')
      XENBR_ADD="--bridge=xenbr${bridge}"
   fi

   # are we running on a Xen kernel in domain 0 ?
   # (only report if RHTS tried running us on an unsuitable host)
   #
   if [ -d /proc -a ! -f /proc/xen/privcmd ] ; then
       DeBug "Don't think we are on a Dom0"
       echo "Don't think we are on a Dom0" >> $OUTPUTFILE
       report_result ${TEST} WARN 10
       exit 0
   fi
fi

## we need libvirt-devel, that might not be installed during installation time
if ! rpm -q libvirt-devel; then
    yum -y install libvirt-devel
    if ! rpm -q libvirt-devel; then
        echo "can't install libvirt-devel"
        echo "guest console logs might not work"
        report_result NO_libvirt-devel WARN 10
    fi
fi

echo "" >> $OUTPUTFILE
echo "***********************" >> $OUTPUTFILE
echo "* SELinux Status      *" >> $OUTPUTFILE
echo "***********************" >> $OUTPUTFILE
/usr/sbin/sestatus | tee -a $OUTPUTFILE
virtinst="./virtinstall.exp"

# we need to make vnc installs happy:
if pidof Xvfb; then
	killall Xvfb
fi
[ -e /tmp/.X1-lock ] && rm -rf /tmp/.X1-lock
# Xvfb in optional repo so it might not be installed.
if ! which Xvfb; then
	yum --enablerepo=beaker-optional* -y install xorg-x11-server-Xvfb
fi
Xvfb :1 -screen 0 1600x1200x24 -fbdir /tmp &
if [[ $? -ne 0 ]]; then
	echo "Xvfb has failed. If there are any graphical installation, they will fail"
	report_result ${TEST}_NoXvfb_NoGraphicalInst WARN 0
fi

export DISPLAY=:1

if [[ $REBOOTCOUNT -gt 1 ]]; then
   echo "Looks like dom0 rebooted during a guest install. Check console logs" >> $OUTPUTFILE
   report_result ${TEST}_dom0rebooted FAIL 99
   submitvirtlogs
   exit 0
fi

i=0
fail=0

if rlIsRHEL '>=8' ; then
   LOCATION="--location http"
fi

./get_guest_info.py $LOCATION > ./tmp.guests
echo "Guests info:" | tee -a $OUTPUTFILE
cat ./tmp.guests | tee -a $OUTPUTFILE

# go thru the guests and set up console sniff/upload
while IFS=$'\t' read guest_recipeid guest_name guest_mac guest_loc guest_ks \
	guest_args guest_kernel_options; do
   if ! mkdir -p $(pwd)/guests/${guest_name}/logs; then
      report_result ${TEST}_cant_create_dirs FAIL 10
   fi
   guest_con_logfile="$(pwd)/guests/${guest_name}/logs/${guest_name}_console.log"
   echo "$guest_con_logfile $guest_recipeid" >> /usr/local/etc/logguestconsoles.conf
   if [ ! -e $guest_con_logfile ]  ; then
      touch $guest_con_logfile
   fi
   chmod a+rw $guest_con_logfile
done < ./tmp.guests

# setup consolelogging
# logguestconsoles create files itself, so if qemu has issues with
# that in future (permissions/selinux), this needs to be started
# only after qemu creates those files
#
# on some rhel5 releases xmlrpc-c package doesn't exist, install it here
if rlIsRHEL 5.4 5.5 ; then
        setuprhel5_xmlrpcc
fi

if setupconsolelogs; then
   service logguestconsoles start
   sleep 2
   echo "Status of logguestconsoles:" | tee -a $OUTPUTFILE
   service logguestconsoles status >> $OUTPUTFILE 2>&1
   echo "Initial log output:" | tee -a $OUTPUTFILE
   cat /var/log/logguestconsoles.* | tee -a $OUTPUTFILE
fi

while IFS=$'\t' read guest_recipeid guest_name guest_mac guest_loc guest_ks \
	guest_args guest_kernel_options; do
   DeBug "guest is :
        guest_recipeid=$guest_recipeid
        guest_name=$guest_name
        guest_mac=$guest_mac
        guest_loc=$guest_loc
        guest_ks=$guest_ks
        guest_args=$guest_args
        guest_kernel_options=$guest_kernel_options"
   if [ -z "$guest_name" ] ; then
      echo "get_guest_info.py did not return a guest name"
      report_result ${TEST}_no_guestname FAIL 10
      exit 1
   fi
   if ! mkdir -p $(pwd)/guests/${guest_name}/logs || ! mkdir -p $(pwd)/guests/${guest_name}/iso; then
      echo "Problem creating $(pwd)/guests/${guest_name}/{logs,iso} dirs"
      report_result ${TEST}_cant_create_dirs FAIL 10
      exit 1
   fi
   if ! chmod -R 777 $(pwd)/guests/${guest_name}; then
      echo "problem with chmod -R 777 $(pwd)/guests/${guest_name}"
      report_result ${TEST}_chmod_issue FAIL  10
      exit 1
   fi

   if ! wget -q ${guest_ks} -O ./${guest_name}.ks ; then
      echo "Can't reach ${guest_ks} , exiting"
      report_result ${TEST}_KSunreachable FAIL 100
      exit 1
   fi

   if [ -n "$*" ]; then
      guest_args=$*
   fi

   # decide where to put the guest's image based on availability
   home_basedir=0
   var_lib_df=$(df /var/lib)
   var_lib_free=$(echo ${var_lib_df} | awk '{print $11}')
   home_df=$(df /home)
   home_free=$(echo ${home_df} | awk '{print $11}')
   if [[ ${home_free} -gt ${var_lib_free} ]]; then
      mkdir -p /home/virtimages/VirtualMachines
      home_basedir=1
   fi

   # Add correct  --bridge  to the command line for the xen guest installs
   CMDLINE="${XENBR_ADD} --name ${guest_name} --mac ${guest_mac} --location ${guest_loc} $guest_args --debug"
   EXTRA_ARGS=""
   if [[ ${kvm_num} -gt 0 ]]; then
      if uname -m | grep -q ppc; then
         console_config="console=tty0 console=hvc0"
      elif uname -m | grep -q aarch64; then
	 console_config=""
      else
         console_config="console=tty0 console=ttyS0,115200"
      fi
      EXTRA_ARGS="ks=$guest_ks serial $console_config"

      # disable vnc on ppc, spapr doesn't support graphics and stdout at the same time
      # we can't attach to any console: vnc is disabled, and serial console is file,
      # thus virsh console fails
      if uname -m | grep -q ppc; then
         CMDLINE="${CMDLINE} --nographics --noautoconsole --wait -1"
      elif uname -m | grep -q aarch64; then
         CMDLINE="${CMDLINE} --nographics --noautoconsole --wait -1"
      fi
   else
      ## the first 2 conditions are for fedora releases since they too can support xen guests.
      if grep -q -i fedora /etc/fedora-release; then
         EXTRA_ARGS="ks=$guest_ks serial"
         CMDLINE="${CMDLINE} --serial file,path=$(pwd)/guests/${guest_name}/logs/${guest_name}_console.log --serial pty --console pty"
         CMDLINE="${CMDLINE} --nographics"
      else
         EXTRA_ARGS="ks=$guest_ks"
      fi

   fi

   # kvm guest should have --accelerate and --os-variant=virtio26 by default.
   # --kvm switch shouldn't be passed on to virtinstall.exp
   if [[ ${kvm_num} -gt 0 ]]; then
      #get rid of --kvm
      CMDLINE=$( echo ${CMDLINE} | awk '{ for (i=1;i<=NF;i++) { if ( $i != "--kvm" ) printf "%s ", $i } }' )
      #add  --accelerate or --os-variant=virtio26 or both
      echo ${CMDLINE} | awk '{rc=0; for(i=1;i<=NF;i++) { if ( $i ~ /--accelerate*/ ) rc+=1; else if ( $i ~ /--os-variant=*/ )  rc += 2;  } exit rc }'
      rc=$?
      if [[ $rc -eq 0 ]]; then
         CMDLINE="${CMDLINE} --accelerate --os-variant=virtio26 "
      elif [[ $rc -eq 1 ]]; then
         CMDLINE="${CMDLINE} --accelerate "
      elif [[ $rc -eq 3 ]]; then
         CMDLINE="${CMDLINE} --os-variant=virtio26 "
     fi

     # qemu-kvm-rhev on ppc doesn't support default rtl8139 model name
     netdev_model=""
     if uname -m | grep -q ppc; then
         netdev_model=",model=virtio"
     fi
     # make an exception for given --network arg..
     # see BZ#821984
     GIVENNW=$(echo $CMDLINE | awk '{ for (i=1;i<=NF;i++) { if ( $i == "--network" ) { i+=1; printf "%s ", $i } else { continue; } } }')
     if [[ -z "${GIVENNW}" ]]; then
        CMDLINE="${CMDLINE} --ver6 --network bridge:${brdev}${netdev_model} "
     else
        CMDLINE=$(echo $CMDLINE | awk '{ for (i=1;i<=NF;i++) { if ( $i == "--network" ) { i+=1; continue; } else printf "%s ", $i } }')
        NWARG=""
        for opts in ${GIVENNW}
        do
            # skip adding brdev when using --network type=...
            # (the user probably knows what they are doing,
            # and adding bridge:... will interfere)
            if [[ "${opts}" == type=* || "${opts}" == *,type=* ]]; then
               NWARG="${NWARG} --network ${opts}"
            else
               NWARG="${NWARG} --network bridge:${brdev},${opts}"
            fi
        done

        EXTRA_ARGS="ksdevice=eth0 $EXTRA_ARGS"
        CMDLINE="${CMDLINE} --ver6 ${NWARG}"

     fi

     # beginning with rhel6 virt-install can take -serial option. automatically
     # append serial console args unless one is given already or unless --virttest is given
     if [[ ${ver%%.*} -ge 6 ]]; then
        echo ${CMDLINE} | awk '{rc=0; for(i=1;i<=NF;i++) { if ( $i == "--virttest" || $i  ~ /--serial*/) exit 1 } exit 0 }'
        rc=$?
        if [[ ${rc} -eq 0 ]]; then
            CMDLINE="$CMDLINE --serial file,path=$(pwd)/guests/${guest_name}/logs/${guest_name}_console.log --serial pty --console pty "
            # workaround for BZ: 731115
            l_guest_name=$(echo ${guest_name} | tr [:upper:] [:lower:])
            if [[ x"$guest_name" != x"$l_guest_name" ]]; then
               ln -sf $(pwd)/guests/${guest_name} $(pwd)/guests/${l_guest_name}
               if [[ $? -ne 0 ]]; then
                  echo "error with workaround for bz731115"
                  report_result ${TEST}_logdir_link FAIL 100
               fi
            fi
            # end of workaround for BZ 731115
            #
        fi
     fi
   fi

   # add all kernel options to virt-install command-line
   CMDLINE="${CMDLINE} --extra-args \"$EXTRA_ARGS $guest_kernel_options\""

   # temporary workaround for not having diskimage passed on to virt-install
   # see bz 729608
   echo ${CMDLINE} | awk '{rc=0; for(i=1;i<=NF;i++) { if ( $i ~ /--disk*/ || $i ~ /--file=/ || $i == "--file" || $i == "-f" ) rc+=1; } exit rc }'
   rc=$?
   if [[ ${rc} -eq 0 ]]; then
      if [[ ${kvm_num} -gt 0 ]]; then
        if [[ ${home_basedir} -eq 0 ]]; then
            CMDLINE="${CMDLINE} --file /var/lib/libvirt/images/${guest_name}.img "
        else
            CMDLINE="${CMDLINE} --file /home/virtimages/VirtualMachines/${guest_name}.img "
        fi
      else
        if [[ ${home_basedir} -eq 0 ]]; then
            CMDLINE="${CMDLINE} --file /var/lib/xen/images/${guest_name}.img "
        else
            CMDLINE="${CMDLINE} --file /home/virtimages/VirtualMachines/${guest_name}.img "
        fi
      fi
   fi
   # end the workaround for BZ 729608

   echo "Fallocating VM files: `date`" | tee -a $OUTPUTFILE
   fallocate_files ${CMDLINE} >> $OUTPUTFILE 2>&1
   echo "Fallocating VM files done: `date`" | tee -a $OUTPUTFILE

   # Tell Beaker the guest recipe has started.
   ./start_recipe.py $guest_recipeid

   DeBug "CMDLINE == $CMDLINE"
   echo "CMDLINE == $CMDLINE" >> $OUTPUTFILE
   DeBug "***** Start $virtinst ${CMDLINE} *****"
   echo  "***** Start $virtinst ${CMDLINE} *****" >> $OUTPUTFILE
   starttime=$(date +%s)
   echo "Start time: $starttime" >> $OUTPUTFILE
   if selinuxenabled; then
      eval /usr/bin/runcon -t unconfined_t -- $virtinst $CMDLINE 2>&1
   else
      eval $virtinst $CMDLINE 2>&1
   fi
   value=$?
   endtime=$(date +%s)
   echo "End time: $endtime" >> $OUTPUTFILE
   if [[ $value -eq 1 ]]; then
      echo "WARNING: install may or may not have failed. Check the guest" >> $OUTPUTFILE
      let "fail=${fail}+1"
      result=FAIL
      report_result ${TEST}/install_${guest_name} $result $value
   elif [[ $value -eq 14 ]]; then
      echo "Err No 14 workaround" >> $OUTPUTFILE
      let "fail=${fail}+1"
      result=WARN
      report_result ${TEST}/install_${guest_name} $result $value
   elif [[ $value -eq 33 ]]; then
      echo "libvirt error" >> $OUTPUTFILE
      let "fail=${fail}+1"
      result=FAIL
      report_result ${TEST}/install_${guest_name}_libvirterror $result $value
   elif [[ $value -eq 37 ]]; then
      echo "guest crashed" >> $OUTPUTFILE
      let "fail=${fail}+1"
      result=FAIL
      report_result ${TEST}/install_${guest_name}_guestcrash $result $value
   elif [[ $value -eq 38 ]]; then
      echo "no HVM support on the machine" >> $OUTPUTFILE
      let "fail=${fail}+1"
      result=FAIL
      report_result ${TEST}/install_${guest_name}_noHVMsupport $result $value
   elif [[ $value -ne 0 ]]; then
      echo "$virtinst FAILED" >> $OUTPUTFILE
      let "fail=${fail}+1"
      result=FAIL
      report_result ${TEST}/install_${guest_name} $result $value
   else
      result=PASS
      elapsed=$(expr $endtime - $starttime)
      echo "***** Finished $virtinst ${guest_name} in $elapsed seconds *****" >> $OUTPUTFILE
      report_result ${TEST}/install_${guest_name} $result $elapsed
   fi
   # ${guest_name}_install.log should be created by the virtinstall.exp script
   rhts_submit_log -l `pwd`/guests/${guest_name}/logs/${guest_name}_install.log
   # and for rhel6 and above we should have a console log.
   if [ -e `pwd`/guests/${guest_name}/logs/${guest_name}_console.log ]; then
	rhts_submit_log -l `pwd`/guests/${guest_name}/logs/${guest_name}_console.log
   fi
   # upload the guest's config file too.
   if [[ ${kvm_num} -lt 1 ]]; then
      rhts_submit_log -l /etc/xen/${guest_name}
   elif virsh dumpxml ${guest_name}; then
      virsh dumpxml ${guest_name} > ./guests/${guest_name}/logs/${guest_name}.xml
      rhts_submit_log -l ./guests/${guest_name}/logs/${guest_name}.xml
   fi
   let i="$i+1"
done < ./tmp.guests
if [[ $i -eq 0 ]]; then
   report_result ${TEST}/noguestinstall PASS 0
elif [[ ${fail} -eq 0 ]]; then
   report_result ${TEST} PASS 0
else
   report_result ${TEST} FAIL 1
fi

# turn on service for rhel5 console writing.
# This is after the guests are installed so that it won't try to steal console
# from the installation
if rlIsRHEL 5 && rlIsRHEL '>5.3' && [ -z "${NORHEL5CONSOLELOGS}" ]; then
    setuprhel5consoles
fi

# submit the relevant logfiles
submitvirtlogs
if [ -e /nohup.out ]; then
    rhts_submit_log -l /nohup.out
fi

exit 0
