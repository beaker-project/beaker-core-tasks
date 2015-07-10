#!/bin/sh

# Copyright (c) 2006 Red Hat, Inc. All rights reserved. This copyrighted material 
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Bill Peck, Gurhan Ozen

. /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh

if [ -z "$HOSTNAME" ]; then
    hostname=$(hostname)
else
    hostname=$HOSTNAME
fi
if [ -z "$server" ]; then
    server="http://$LAB_CONTROLLER:8000/server"
fi

rlJournalStart
    rlPhaseStartSetup
        # kvm modules not available on all architectures
        rlRun "modprobe kvm" 0,1
	rlRun "modprobe kvm_amd" 0,1
	rlRun "modprobe kvm_intel" 0,1
        # sg module may not be loaded by default, but lshw relies on /dev/sg*
        # device nodes for scanning SCSI devices
        # https://bugzilla.redhat.com/show_bug.cgi?id=1193817
        rlRun "modprobe sg" 0,1
        rlRun "yum -y install beaker-system-scan"
	rlAssertRpm "beaker-system-scan"
    rlPhaseEnd

    rlPhaseStartTest
        if [ -n "$INVENTORY_DEBUG" ] ; then
            rlRun -l "beaker-system-scan -d >inventory.out"
            rlFileSubmit inventory.out
        else
            rlRun -l "beaker-system-scan --server $server -h $hostname"
        fi
    rlPhaseEnd

    rlPhaseStart WARN check_virt_enabled
        #https://bugzilla.redhat.com/show_bug.cgi?id=738881
        if journalctl --dmesg &>/dev/null ; then
            # systemd journal
            if journalctl --dmesg | grep "kvm: disabled by bios" ; then
                kvm_disabled=1
            fi
        else
            # syslog
            if grep "kvm: disabled by bios" /var/log/messages ; then
                kvm_disabled=1
            fi
        fi
        if [ -n "$kvm_disabled" ] ; then
            rlFail "Kernel reports that KVM is disabled. Check BIOS/firmware settings to ensure virt CPU features are enabled."
        fi
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
