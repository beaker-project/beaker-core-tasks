#!/bin/sh

# Source the common test script helpers
. /usr/bin/rhts_environment.sh

if [ -n "$RSTRNT_JOBID" ]; then
    # Fill in legacy values
    export SUBMITTER=$RSTRNT_OWNER
    export JOBID=$RSTRNT_JOBID
    export RECIPEID=$RSTRNT_RECIPEID
    export DISTRO=$RSTRNT_OSDISTRO
    export ARCH=$RSTRNT_OSARCH
    export TEST=$RSTRNT_TASKNAME
    export TESTID=$RSTRNT_TASKID
    export REBOOTCOUNT=$RSTRNT_REBOOTCOUNT
    export LAB_CONTROLLER=$BEAKER_LAB_CONTROLLER
fi

cleanup()
{
    kill -9 $1
    exit 0
}

STOPRHTS()
{
    chkconfig rhts
    if [ $? -eq 0 ]; then
        /sbin/service rhts stop
    else
        /usr/bin/killall rhts-test-runner.sh
    fi
}

# Functions
RprtRslt()
{
    ONE=$1
    TWO=$2
    THREE=$3

    # File the results in the database
    report_result $ONE $TWO $THREE
}

MOTD()
{
    FILE=/etc/motd
    cp $FILE $FILE.orig
    if selinuxenabled &>/dev/null ; then
        restorecon $FILE.orig
    fi

    local admonition=
    if [ -n "$BEAKER_RESERVATION_POLICY_URL" ] ; then
        admonition="
 Please ensure that you adhere to the reservation policy
  for Beaker systems:
  ${BEAKER_RESERVATION_POLICY_URL}"
    fi

    cat <<END > $FILE
**  **  **  **  **  **  **  **  **  **  **  **  **  **  **  **  **  **
                 This System is reserved by $SUBMITTER.

 To return this system early. You can run the command: return2beaker.sh
  Ensure you have your logs off the system before returning to Beaker

 To extend your reservation time. You can run the command:
  extendtesttime.sh
 This is an interactive script. You will be prompted for how many
  hours you would like to extend the reservation.${admonition}

 You should verify the watchdog was updated succesfully after
  you extend your reservation.
  ${BEAKER}recipes/$RECIPEID

 For ssh, kvm, serial and power control operations please look here:
  ${BEAKER}view/$HOSTNAME

 For the default root password, see:
  ${BEAKER}prefs/

      Beaker Test information:
                         HOSTNAME=$HOSTNAME
                            JOBID=$JOBID
                         RECIPEID=$RECIPEID
                    RESULT_SERVER=$RESULT_SERVER
                           DISTRO=$DISTRO
                     ARCHITECTURE=$ARCH

      Job Whiteboard: $BEAKER_JOB_WHITEBOARD

      Recipe Whiteboard: $BEAKER_RECIPE_WHITEBOARD
**  **  **  **  **  **  **  **  **  **  **  **  **  **  **  **  **  **
END
}

RETURNSCRIPT()
{
    SCRIPT=/usr/bin/return2beaker.sh

    if [ -n "$RSTRNT_JOBID" ]; then
        echo "#!/bin/sh"          > $SCRIPT
        echo "killall runtest.sh" >> $SCRIPT
    else
        echo "#!/bin/sh"                           > $SCRIPT
        echo "export RESULT_SERVER=$RESULT_SERVER" >> $SCRIPT
        echo "export TESTID=$TESTID" >> $SCRIPT
        echo "/usr/bin/rhts-test-update $RESULT_SERVER $TESTID finish" >> $SCRIPT
        echo "touch /var/cache/rhts/$TESTID/done" >> $SCRIPT
    fi
    echo "/bin/echo Going on..." >> $SCRIPT
    rm -f /usr/bin/return2rhts.sh &> /dev/null || true
    ln -s $SCRIPT /usr/bin/return2rhts.sh &> /dev/null || true

    chmod 777 $SCRIPT
}

EXTENDTESTTIME()
{
SCRIPT2=/usr/bin/extendtesttime.sh

cat > $SCRIPT2 <<-EOF
#!/bin/sh

# Source the common test script helpers
. /usr/bin/rhts_environment.sh

howmany()
{
if [ -n "\$1" ]; then
  RESPONSE="\$1"
else
  echo "How many hours would you like to extend the reservation."
  echo "             Must be between 1 and 99                   "
  read RESPONSE
fi
validint "\$RESPONSE" 1 99
echo "Extending reservation time \$RESPONSE"
EXTRESTIME=\$(echo \$RESPONSE)h
}

validint()
{
# validate first field.
number="\$1"; min="\$2"; max="\$3"

if [ -z "\$number" ] ; then
echo "You didn't enter anything."
exit 1
fi

if [ "\${number%\${number#?}}" = "-" ] ; then # first char '-' ?
testvalue="\${number#?}" # all but first character
else
testvalue="\$number"
fi

nodigits="\$(echo \$testvalue | sed 's/[[:digit:]]//g')"

if [ ! -z "\$nodigits" ] ; then
echo "Invalid number format! Only digits, no commas, spaces, etc."
exit 1
fi

if [ ! -z "\$min" ] ; then
if [ "\$number" -lt "\$min" ] ; then
echo "Your value is too small: smallest acceptable value is \$min"
exit 1
fi
fi
if [ ! -z "\$max" ] ; then
if [ "\$number" -gt "\$max" ] ; then
echo "Your value is too big: largest acceptable value is \$max"
exit 1
fi
fi

return 0
}

howmany "\$1"

EOF


    if [ -n "$RSTRNT_JOBID" ]; then
cat >> $SCRIPT2 <<-EOF
export HOSTNAME=$HOSTNAME
export HARNESS_PREFIX=$HARNESS_PREFIX
export RSTRNT_RECIPE_URL=$RSTRNT_RECIPE_URL
rstrnt-adjust-watchdog \$EXTRESTIME
EOF
    else
cat >> $SCRIPT2 <<-EOF
export RESULT_SERVER=$RESULT_SERVER
export HOSTNAME=$HOSTNAME
export JOBID=$JOBID
export TEST=$TEST
export TESTID=$TESTID
export RECIPETESTID=$TESTID
rhts-test-checkin $RESULT_SERVER $HOSTNAME $JOBID $TEST \$EXTRESTIME $TESTID
logger -s "rhts-test-checkin $RESULT_SERVER $HOSTNAME $JOBID $TEST \$EXTRESTIME $TESTID"
report_result $TEST/extend-test-time PASS \$EXTRESTIME
EOF
    fi

chmod 777 $SCRIPT2
}

NOTIFY()
{
    if command -v systemctl >/dev/null ; then
        # Any of the following services could have been installed to satisfy
        # the "MTA" virtual provides. They all provide an implementation of
        # /usr/sbin/sendmail. So let's just try to start all of them
        # and we assume one will succeed.
        systemctl start postfix.service
        systemctl start exim.service
        systemctl start sendmail.service
        systemctl start opensmtpd.service
    else
        /sbin/service sendmail start
    fi
    local msg=$(mktemp)

cat > $msg <<-EOF
To: $SUBMITTER
Subject: [Beaker Machine Reserved] $HOSTNAME
X-Beaker-test: $TEST

EOF
    cat /etc/motd >>$msg
    cat $msg | sendmail -t
    \rm -f $msg
}

WATCHDOG()
{
    if [ -n "$RSTRNT_JOBID" ]; then
        rstrnt-adjust-watchdog $SLEEPTIME
    else
        rhts-test-checkin $RESULT_SERVER $HOSTNAME $JOBID $TEST $SLEEPTIME $TESTID
    fi
}

if [ -z "$RESERVETIME" ]; then
    SLEEPTIME=24h
else
    SLEEPTIME=$RESERVETIME
    # Verify the max amount of time a system can be reserved
    if [ $SLEEPTIME -gt 356400 ]; then
        RprtRslt $TEST/watchdog_exceeds_limit Warn $SLEEPTIME
	SLEEPTIME=356400
    fi
fi

if [ -n "$RESERVEBY" ]; then
    SUBMITTER=$RESERVEBY
fi

echo "***** Start of reservesys test *****" > $OUTPUTFILE

BUILD_()
{
    # build the /etc/motd file
    echo "***** Building /etc/motd *****" >> $OUTPUTFILE
    MOTD

    # send email to the submitter
    echo "***** Sending email to $SUBMITTER *****" >> $OUTPUTFILE
    NOTIFY

    # set the external watchdog timeout
    echo "***** Setting the external watchdog timeout *****" >> $OUTPUTFILE
    WATCHDOG

    # build /usr/bin/extendtesttime.sh script to allow user
    #  to extend the time time.
    echo "***** Building /usr/bin/extendtesttime.sh *****" >> $OUTPUTFILE
    EXTENDTESTTIME

    # build /usr/bin/return2beaker.sh script to allow user
    #  to return the system to Beaker early.
    echo "***** Building /usr/bin/return2beaker.sh *****" >> $OUTPUTFILE
    RETURNSCRIPT
}

if [ -n "$REBOOTCOUNT" ]; then
    if [ $REBOOTCOUNT -eq 0 ]; then
        if [ -n "$RESERVE_IF_FAIL" ]; then
            # beakerd only re-computes a recipe's overall result every 20 seconds. We 
            # need a delay here to ensure that the recipe result is up to date before 
            # we check it. Otherwise we might miss a Fail from the task right before 
            # this one (its result will remain New until beakerd computes it).
            sleep 40

            if command -v python3 >/dev/null; then
                python_command="python3"
            elif [ -f /usr/libexec/platform-python ] && /usr/libexec/platform-python --version 2>&1 | grep -q "Python 3" ; then
                python_command="/usr/libexec/platform-python"
            else
                python_command="python"
            fi

            $python_command recipe_status
            if [ $? -eq 0 ]; then
                RprtRslt $TEST/RESERVE_SKIP PASS 0
                exit 0
            fi
        fi
        BUILD_
        echo "***** End of reservesys test *****" >> $OUTPUTFILE
        RprtRslt $TEST PASS 0
    fi
fi


if [ -n "$RSTRNT_JOBID" ]; then
    # RSTRNT_JOBID is defined which means we are running in restraint
    # We stay running in restraint..
    # TODO: This should be replaced with clever logic like fetching current value of EWD and adjusting
    while (true); do
        sleep 5
    done
else
    # stop rhts service, So that reserve workflow works with test reboot support.
    STOPRHTS

    # harnesses other than beah may cause this script to nominally fail (e.g.
    # failing to stop rhts, since other harnesses may not have such a thing),
    # so we force the script to always return zero
    #
    # this means that including /distribution/reservesys in a recipe should
    # never change the overall result, even if helper commands that assume beah
    # as the harness fail
fi

exit 0
