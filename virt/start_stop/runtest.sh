#!/bin/sh

# Source the common test script helpers
. /usr/bin/rhts_environment.sh
. /usr/local/bin/rhts_virt_funcs.sh

result=PASS
value=0
set -x
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

# we need virtual machine names with GUESTS which includes all
# VMs or START_GUESTS which can specify particular guests..
if [[ -z $GUESTS && -z $GUESTSTARTSTOP_ARGS ]]; then 
   echo "Can't find GUESTS or GUESTSTARTSTOP_ARGS variable.. this should not happen"
#   result=FAIL
#   report_result $TEST/start_guests $result 1
#   exit 1
fi

# use timeout value iff VIRTEST_TIMEOUT is given 
if [[ -z ${VIRTEST_TIMEOUT} ]]; then 
	export timeout=""
else
	export timeout=${VIRTEST_TIMEOUT}
fi

if [[ -z $GUESTSTARTSTOP_ARGS ]]; then
   ../install/get_guest_info.py > ./tmp.guests
   echo "Guests info:" | tee -a $OUTPUTFILE
   cat ./tmp.guests | tee -a $OUTPUTFILE
   while read -r guest_recipeid guest_name guest_mac guest_loc guest_ks guest_args ; do
      if [ -z $guest_name ]; then
         echo "No guestname can be found"
         report_result ${TEST}_noguestname FAIL 1
         continue
      fi
      DeBug "guest name is : $guest_name "
      fqdn=$(../install/get_guest_fqdn.py $guest_recipeid)

      ## disable below for BZ #544397
      #if [ ! -f /tmp/${guest_name}_created ]; then
      #   echo "$guest_name doesn't seem to be installed properly "
      #   unset guest_name err
      #   continue
      #fi


      if selinuxenabled; then
         err=$(/usr/bin/runcon -t unconfined_t -- virsh start $guest_name 2>&1)
         rc=$?
      else
         err=$(virsh start $guest_name 2>&1)
         rc=$?
      fi
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

      sleep 5
      if wait4guest $guest_recipeid $timeout; then 
         result=PASS
      else 
         echo "$guest_name  failed to start up in time"
         result=FAIL
         report_result $TEST/start_${guest_name} $result 0
         unset guest_name err
         continue
      fi

      # now stop it...
      if selinuxenabled; then
         err=$(/usr/bin/runcon -t unconfined_t -- virsh shutdown $guest_name 2>&1)
         rc=$?
      else
         err=$(virsh shutdown $guest_name 2>&1)
         rc=$?
      fi
      if [[ ${rc} == 0 ]]; then
         echo "$guest_name stopped... "
         result=PASS
      else
         echo "$guest_name failed to stop : "
         echo $err
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi
      
      sleep 5
      if wait4shutdown $guest_name $timeout; then 
         result=PASS
      else 
         echo "$guest_name  failed to shutdown in time"
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi
      
      report_result $TEST/start_stop_${guest_name} $result 0
      
      unset guest_name err
   done < ./tmp.guests
else
   for guest_name in $GUESTSTARTSTOP_ARGS
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

      if selinuxenabled; then
         err=$(/usr/bin/runcon -t unconfined_t -- virsh start $guest_name 2>&1)
         rc=$?
      else
         err=$(virsh start $guest_name 2>&1)
         rc=$?
      fi
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
      
      
      sleep 5
      if wait4guest $fqdn $timeout; then 
         result=PASS
      else 
         echo "$guest_name  failed to start up in time"
         result=FAIL
         report_result $TEST/start_${guest_name} $result 0
         unset guest_name err
         continue
      fi

      # now stop it...
      if selinuxenabled; then
         err=$(/usr/bin/runcon -t unconfined_t -- virsh shutdown $guest_name 2>&1)
         rc=$?
      else
         err=$(virsh shutdown $guest_name 2>&1)
         rc=$?
      fi
      if [[ ${rc} == 0 ]]; then
         echo "$guest_name stopped... "
         result=PASS
      else
         echo "$guest_name failed to stop : "
         echo $err
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi
      
      sleep 5
      if wait4shutdown $guest_name $timeout; then 
         result=PASS
      else 
         echo "$guest_name  failed to shutdown in time"
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi
      
      report_result $TEST/start_stop_${guest_name} $result 0

      unset guest_name err
   done
fi

#submit logs...
# 
submitvirtlogs
exit 0

