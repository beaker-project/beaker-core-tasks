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
DEBUGLOG=`mktemp -p /mnt/testarea -t virtstop.XXXXXX`

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

# - use remote URI if running on remote node else just run locally as usual.
if [ ! -z $RECIPE_ROLE_NODE ]; then
  if [ $RECIPE_ROLE_NODE != $HOSTNAME ];then
   export VIRSH_DEFAULT_CONNECT_URI=${VIRSH_DEFAULT_CONNECT_URI:-qemu+ssh://root@${RECIPE_ROLE_NODE}/system}
  fi
fi

# if we are not specified any guests, shut them all down...
if [[ -z $GUESTSHUT_ARGS ]]; then
   ../install/get_guest_info.py | while IFS=$'\t' read guest_recipeid guest_name \
	   guest_mac guest_loc guest_ks guest_args guest_kernel_options; do
      if [ -z $guest_name ]; then
         echo "No guestname can be found"
         report_result ${TEST}_noguestname FAIL 1
         continue
      fi
      DeBug "guest name is : $guest_name "

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
         echo "$guest_name failed to shutdown."
         echo $err
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi

      report_result $TEST/stop_${guest_name} $result 0
      unset guest_name err
   done

else 
   for guest_name in $GUESTSHUT_ARGS
   do
      if [[ -z $guest_name ]]; then
         echo "can't find a guestname with $guest"
         report_result $TEST/stop_$guest FAIL 1
         continue
      fi

      if [ ! -f /tmp/${guest_name}_created ]; then
         echo "$guest_name doesn't seem to be installed properly "
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi

      if selinuxenabled; then
         err=$(/usr/bin/runcon -t unconfined_t -- virsh shutdown $guest_name 2>&1)
         rc=$?
      else
         err=$(virsh shutdown $guest_name 2>&1)
         rc=$?
      fi
      if [[ ${rc} == 0 ]]; then
         echo "$guest_name is shutting down"
         result=PASS
      else
         echo "$guest_name failed to shutdown"
         echo $err
         result=FAIL
         report_result $TEST/stop_${guest_name} $result 0
         unset guest_name err
         continue
      fi

      report_result $TEST/stop_${guest_name} $result 0

      unset guest_name err

   done
fi

# submit the relevant logfiles
# since we just did virsh start and got out of the way it's probably a good idea
# sleep for a while before submitting logs. 

sleep 120

submitvirtlogs

exit 0
