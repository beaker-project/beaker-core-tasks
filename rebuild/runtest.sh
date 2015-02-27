#!/bin/bash

. /usr/bin/rhts_environment.sh
. /usr/share/beakerlib/beakerlib.sh

: ${MOCK_CONFIG_NAME:=distribution-rebuild}
: ${MOCK_CHROOT_SETUP_CMD:=install @buildsys-build}
: ${MOCK_TARGET_ARCH:=$(uname -m)}

function generate_mock_config() {
    cat >"/etc/mock/${MOCK_CONFIG_NAME}.cfg" <<EOF
config_opts['root'] = '${MOCK_CONFIG_NAME}'
config_opts['target_arch'] = '${MOCK_TARGET_ARCH}'
config_opts['chroot_setup_cmd'] = '${MOCK_CHROOT_SETUP_CMD}'
# ccache is of questionable benefit in this task and it isn't available in RHEL
config_opts['plugin_conf']['ccache_enable'] = False
config_opts['yum.conf'] = """
[main]
cachedir=/var/cache/yum
reposdir=/dev/null
retries=20
obsoletes=1
gpgcheck=0
assumeyes=1
EOF
    reponum=1
    for repo in ${MOCK_REPOS} ; do
        cat >>"/etc/mock/${MOCK_CONFIG_NAME}.cfg" <<EOF
[repo$reponum]
name=repo$reponum
baseurl=$repo
EOF
        reponum=$((reponum+1))
    done
    echo '"""' >>"/etc/mock/${MOCK_CONFIG_NAME}.cfg"
}

function should_skip_srpm() {
    local srpm="$1"
    if [ -n "$SKIP_NOARCH" ] ; then
        if ! rpm -q -p "$srpm" --qf '%{arch}\n' | grep -qv noarch ; then
            rlLogInfo "Skipping $srpm because it produces only noarch packages"
            return 0
        fi
    fi
    if [ -n "$SRPM_WHITELIST" ] ; then
        # if a whitelist is given, we skip anything *not* in the whitelist
        local in_whitelist=0
        for glob in $SRPM_WHITELIST ; do
            if [[ $(basename $srpm) == $glob ]] ; then
                in_whitelist=1
            fi
        done
        if [ $in_whitelist -ne 1 ] ; then
            rlLogInfo "Skipping $srpm because it did not match any pattern in the whitelist"
            return 0
        fi
    fi
    # skip anything in the blacklist
    for glob in $SRPM_BLACKLIST ; do
        if [[ $(basename $srpm) == $glob ]] ; then
            rlLogInfo "Skipping $srpm because it matched pattern '$glob' in the blacklist"
            return 0
        fi
    done
    return 1 # don't skip
}

rlJournalStart

rlPhaseStartSetup
    # fetch all SRPMs
    cat >source.conf <<EOF
[source]
name=source
baseurl=${SOURCE_REPO}
EOF
    rlAssert0 "Created reposync config for fetching SRPMs" $?
    mkdir -p srpms
    rlRun -c -l "reposync -c source.conf --repoid=source --source --newest-only -p srpms"

    # set up mock config for builds
    if [ -f "/etc/mock/${MOCK_CONFIG_NAME}.cfg" ] ; then
        rlLogInfo "Mock config for ${MOCK_CONFIG_NAME} exists, using it as is"
    else
        generate_mock_config
        rlAssert0 "Generated mock config ${MOCK_CONFIG_NAME}" $?
    fi

    # create unprivileged user for mock (it refuses to run as root)
    rlRun "useradd -m -U -G mock mockuser"
rlPhaseEnd

rlPhaseStartTest
    find srpms -name \*.src.rpm -print | sort | while read srpm ; do
        if should_skip_srpm "$srpm" ; then
            continue
        fi
        buildcmd="runuser -u mockuser -- /usr/bin/mock -r ${MOCK_CONFIG_NAME} --rebuild $srpm"
        if [ -n "$KEEP_RESULTS" ] ; then
            resultdir="results/$(rpm -q -p "$srpm" --qf '%{name}')"
            mkdir -p $resultdir
            chown mockuser $resultdir
            buildcmd+=" --resultdir ./$resultdir"
        else
            resultdir="/var/lib/mock/${MOCK_CONFIG_NAME}/result"
        fi
        rlRun "$buildcmd"
        if [ $? -eq 0 ] ; then
            result=PASS
        else
            result=FAIL
        fi
        rlReport "rebuild $(basename $srpm)" $result 0 "$resultdir/build.log"
    done
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
