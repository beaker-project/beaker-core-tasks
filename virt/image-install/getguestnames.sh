#!/bin/bash
#
# this script prints out a comma-delimited list of the name of the virtual
# guests that should be installed on this machine.
#

RESULT=""
for dir in /mnt/tests/distribution/virt/install/guests/* ; do
    guest_name=$(basename $dir)
    RESULT="${guest_name}"",""${RESULT}"
done
RESULT=${RESULT%,}
echo $RESULT
exit 0

