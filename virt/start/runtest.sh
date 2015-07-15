#!/bin/bash

# Source the common test script helpers
. /usr/bin/rhts_environment.sh
. /usr/local/bin/rhts_virt_funcs.sh

result=PASS
value=0

# control where to log debug messages to:
# devnull = 1 : log to /dev/null
# devnull = 0 : log to file specified in ${DEBUGLOG}
devnull=0

# Create debug log
DEBUGLOG=`mktemp -p /mnt/testarea -t virtstart.XXXXXX`

# locking to avoid races
lck=$OUTPUTDIR/$(basename $0).lck

# Log a message to the ${DEBUGLOG} or to /dev/null
function DeBug ()
{
    local msg="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    if [ "$devnull" = "0" ]; then
	lockfile -r 1 $lck
	if [ "$?" = "0" ]; then
	    echo -n "${timestamp}: " >>$DEBUGLOG 2>&1
	    echo "${msg}" >>$DEBUGLOG 2>&1
	    rm -f $lck >/dev/null 2>&1
	fi
    else
	echo "${msg}" >/dev/null 2>&1
    fi
}

function SubmitLog ()
{
    LOG=$1
    rhts_submit_log -l $LOG
}

function SubmitVirtLogs () 
{
    # submit the relevant logfiles
    if iskvm; then 
       for kvmlog in $(find /var/log/libvirt/qemu/ -type f)
       do
           rhts_submit_log -l ${kvmlog}
       done
    else 
       for xenlog in $(find /var/log/xen/ -type f)
       do
         rhts_submit_log -l ${xenlog}
       done
       for dumps in $(find /var/lib/xen/dump -type f)
       do
         rhts_submit_log -l ${dumps}
       done
    fi
    
    rhts_submit_log -l ${DEBUGLOG}
    
    #submit dmesg
    dmesg > ./dmesg.txt
    rhts_submit_log -l ./dmesg.txt
    # Always submit the audit.log
    rhts_submit_log -l /var/log/audit/audit.log
    #submit libvirtd debug log...
    if [ -e /tmp/libvirtd_debug.log ]; then 
        rhts_submit_log -l /tmp/libvirtd_debug.log
        # clean the log for the next test
        echo "" > /tmp/libvirtd_debug.log
    fi
    
    
}

function is_libvirtd_running_el7 ()
{
	rpm -qa initscripts | grep "\.el7"
	if [ $? -eq 0 ]; then
		pgrep libvirtd > /dev/null
		if [ $? -ne 0 ]; then
			echo "libvirtd likely crashed - Bug 982969"
			systemctl restart libvirtd
			sleep 5
			return 1
		fi
	fi
	return 0
}

# - use remote URI if running on remote node else just run locally as usual.
if [ ! -z $RECIPE_ROLE_NODE ]; then
  if [ $RECIPE_ROLE_NODE != $HOSTNAME ];then
   export VIRSH_DEFAULT_CONNECT_URI=${VIRSH_DEFAULT_CONNECT_URI:-qemu+ssh://root@${RECIPE_ROLE_NODE}/system}
  fi
fi


if [[ -z $GUESTSTART_ARGS ]]; then
   get_guest_info.py | while IFS=$'\t' read guest_recipeid guest_name guest_mac \
	   guest_loc guest_ks guest_args guest_kernel_options; do
      if [ -z $guest_name ]; then
         echo "No guestname can be found"
         report_result ${TEST}_noguestname FAIL 1
         continue
      fi
      DeBug "guest name is : $guest_name "

      ## disable below for BZ #544397
      #if [ ! -f /tmp/${guest_name}_created ]; then
      #   echo "$guest_name doesn't seem to be installed properly "
      #   result=FAIL
      #   report_result $TEST/start_${guest_name} $result 0
      #   unset guest_name err
      #   continue
      #fi
      TRY=3
      i=0
      while (( $i < $TRY )) 
      do
	      if selinuxenabled; then
		 err=$(/usr/bin/runcon -t unconfined_t -- virsh start $guest_name 2>&1)
		 rc=$?
		 if [[ $rc != 0 ]]; then 
			if echo $err | grep "Domain not found: xenUnifiedDomainLookupByName"; then
				echo "xenUnifiedDomainLookupByName failed. This might be a false error"
				report_result ${TEST}_xenUnifiedDomainLookupByName WARN $i
				let "i=${i}+1"
				continue
			fi
			if ! is_libvirtd_running_el7; then
				echo "libvirtd is not running (el7), trying to restart"
				report_result ${TEST}_libvirtd_not_running WARN $i
				let "i=${i}+1"
				continue
			fi
			break
		else
			break
		fi
	      else
		 err=$(virsh start $guest_name 2>&1)
		 rc=$?
		 if [[ $rc != 0 ]]; then 
			if echo $err | grep "Domain not found: xenUnifiedDomainLookupByName"; then
				echo "xenUnifiedDomainLookupByName failed. This might be a false error"
				report_result ${TEST}_xenUnifiedDomainLookupByName WARN $i
				let "i=${i}+1"
				continue
			fi
			if ! is_libvirtd_running_el7; then
				echo "libvirtd is not running (el7), trying to restart"
				report_result ${TEST}_libvirtd_not_running WARN $i
				let "i=${i}+1"
				continue
			fi
			break
		else
			break
		fi
	      fi
      done
      if [[ ${rc} == 0 ]]; then
         echo "$guest_name started... "
         result=PASS
      else
         echo "$guest_name failed to start : "
         echo $err
         result=FAIL
         report_result $TEST/start_${guest_name} $result 0
         unset guest_name err
         continue
      fi
       
      virsh dumpxml $guest_name > ./${guest_name}.xml
      rhts_submit_log -l ./${guest_name}.xml
        
      minidom_guestname_resolution.py --recipeid $guest_recipeid
      report_result $TEST/start_${guest_name} $result 0
      
      unset guest_name err
   done
else
   for guest_name in $GUESTSTART_ARGS
   do
      if [[ -z $guest_name ]]; then
         echo "can't find a guestname with $guest"
         report_result $TEST/start_$guest FAIL 1
         continue
      fi
      if [ ! -f /tmp/${guest_name}_created ]; then
         echo "$guest_name doesn't seem to be installed properly "
         result=FAIL
         report_result $TEST/start_${guest_name} $result 0
         unset guest_name err
         continue
      fi
      TRY=3
      i=0
      while (( $i < $TRY )) 
      do
	      if selinuxenabled; then
		 err=$(/usr/bin/runcon -t unconfined_t -- virsh start $guest_name 2>&1)
		 rc=$?
		 if [[ $rc != 0 ]]; then 
			if echo $err | grep "Domain not found: xenUnifiedDomainLookupByName"; then
				echo "xenUnifiedDomainLookupByName failed. This might be a false error"
				report_result ${TEST}_xenUnifiedDomainLookupByName WARN $i
				let "i=${i}+1"
				continue
			fi
			if ! is_libvirtd_running_el7; then
				echo "libvirtd is not running (el7), trying to restart"
				report_result ${TEST}_libvirtd_not_running WARN $i
				let "i=${i}+1"
				continue
			fi
			break
		else
			break
		fi
	      else
		 err=$(virsh start $guest_name 2>&1)
		 rc=$?
		 if [[ $rc != 0 ]]; then 
			if echo $err | grep "Domain not found: xenUnifiedDomainLookupByName"; then
				echo "xenUnifiedDomainLookupByName failed. This might be a false error"
				report_result ${TEST}_xenUnifiedDomainLookupByName WARN $i
				let "i=${i}+1"
				continue
			fi
			if ! is_libvirtd_running_el7; then
				echo "libvirtd is not running (el7), trying to restart"
				report_result ${TEST}_libvirtd_not_running WARN $i
				let "i=${i}+1"
				continue
			fi
			break
		else
			break
		fi
	      fi
      done
      if [[ ${rc} == 0 ]]; then
         echo "$guest_name started"
         result=PASS
      else
         echo "$guest_name failed to start : "
         echo $err
         result=FAIL
         report_result $TEST/start_${guest_name} $result 0
         unset guest_name err
         continue
      fi

      report_result $TEST/start_${guest_name} $result 0

      unset guest_name err

   done
fi

# submit the relevant logfiles
# since we just did virsh start and got out of the way it's probably a good idea
# sleep for a while before submitting logs. 

sleep 120

# Submit virt-related logs
submitvirtlogs

exit 0

