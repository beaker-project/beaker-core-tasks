# This file will contain the general functions that might be useful to various
# virtualization testings. The file will sit in /usr/local/bin/ directory and will be
# intended to be sourced in by the tests utilizing this.

# function isxen:
# return 0 if we're running in a xen hypervisor , return 1 if not
function isxen {
	if uname -r | grep -q xen; then 
		return 0
	else
		return 1
	fi
}

# function iskvm:
# return 0 if we're running in a kvm hypervisor , return 1 if not
function iskvm {
	if lsmod | grep -q kvm; then 
		return 0
	else 
		return 1
	fi
}

# function isparavirt:
# return 0 if the $guest is paravirt
function isparavirt {

	if [[ $# != 1 ]]; then 
		echo "Need a guest name as an argument"
		return 1;
	fi

	if virsh dumpxml $1 | grep -q '>hvm<'; then 
		return 1
	else
		return 0
	fi

}

# function ishvm
# return 0 if $guest is hvm, 1 if it's not.
function ishvm {

	if [[ $# != 1 ]]; then 
		echo "Need a guest name as an argument"
		return 1;
	fi

	if virsh dumpxml $1 | grep -q '>hvm<'; then 
		return 0
	else
		return 1
	fi

}
# function setvirttestargs :
# most virt testing scripts need to have guestnames to work with. This can be
# provided either at the workflow, or it can be determined during the testtime.
# If it's the latter, the test will run on each and every guest in order. The
# guest arguments will be separated with pipe sign , |  
function setvirttestargs {

	if [[ -z ${VIRT_TESTARGS} ]]; then 
                for dir in /mnt/tests/distribution/virt/install/guests/* ; do
                        guest_name=$(basename $dir)
			if [[ -z ${VIRT_TESTARGS} ]]; then
				VIRT_TESTARGS="${guest_name}"
			else
				VIRT_TESTARGS="${VIRT_TESTARGS}|${guest_name}"
			fi
		done
	fi

	echo ${VIRT_TESTARGS}
	export VIRT_TESTARGS="${VIRT_TESTARGS}"
	return 0
	

}

# function submitvirtlogs
# submits the logs to rhts based on what hypervisor is running
function submitvirtlogs {

    if iskvm; then 
       for kvmlog in $(find /var/log/libvirt/qemu/ -type f |  tr '\n' "${IFS}")
       do
           rhts_submit_log -l ${kvmlog}
       done
    else 
       for xenlog in $(find /var/log/xen/ -type f |  tr '\n' "${IFS}")
       do
         rhts_submit_log -l ${xenlog}
       done
       for dumps in $(find /var/lib/xen/dump -type f |  tr '\n' "${IFS}")
       do
         thefile=$(basename $dumps)
         if ! scp.exp -u netdump -p netdump -h $DUMPSERVER -t 3600 -f ${thefile}  -F /var/crash/${JOBID}_${RECIPEID}_${thefile}; then
            echo "problem with scp-ing $thefile "
         else
             echo "$thefile has been loaded up to netdump server, please investigate"
         fi
       done
    fi

    # submit libvirtd debug log if requested
    if [ -n "$LIBVIRTD_DEBUG" -a -e /var/tmp/libvirtd_debug.log ] ; then
        rhts_submit_log -l /var/tmp/libvirtd_debug.log
        # clean the log for the next test
        echo "" > /var/tmp/libvirtd_debug.log
    fi

    if setvirttestargs; then 
    
       if [[ x"${VIRT_TESTARGS}" != "x" ]]; then 
          OLDIFS=${IFS}
          IFS="|"
          for guestname in $VIRT_TESTARGS
          do
             if [ -d $(pwd)/guests/${guestname}/logs ]; then
		unset IFS
                for file in $(ls $(pwd)/guests/${guestname}/logs)
                do
                   rhts_submit_log -l $(pwd)/guests/${guestname}/logs/${file}
                done
		IFS="|"
             fi
          done
	  IFS=${OLDIFS}
       fi

    fi
    #submit dmesg
    dmesg > ./dmesg.txt
    rhts_submit_log -l ./dmesg.txt
    # Always submit the audit.log
    rhts_submit_log -l /var/log/audit/audit.log

}
	
function TurnOnLibvirtdLogging() 
{
    if alias | grep cp=; then
       unalias cp
    fi
    cp -f /etc/libvirt/libvirtd.conf /etc/libvirt/libvirtd.conf.orig
    echo 'log_filters="1:libvirt 1:util 1:qemu"' >> /etc/libvirt/libvirtd.conf
    echo 'log_outputs="1:file:/var/tmp/libvirtd_debug.log"' >> /etc/libvirt/libvirtd.conf

    if ! service libvirtd restart; then 
	echo "There was a problem restarting libvirtd!!!" 
    fi
}


function TurnOffLibvirtdLogging() 
{

    perl -pi.bak -e 's/^log_.*$//g' /etc/libvirt/libvirtd.conf
  
    if ! service libvirtd restart; then 
	echo "There was a problem restarting libvirtd!!!" 
    fi
}
