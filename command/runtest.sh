#!/bin/sh

# Source the common test script helpers                                       
. /usr/bin/rhts_environment.sh

# Setup Shell options.
set -o xtrace -o pipefail

echo "- start of test." | tee -a "${OUTPUTFILE}"
echo "- run command:" | tee -a "${OUTPUTFILE}"
echo "- eval ${TESTARGS:-${CMDS_TO_RUN}}" | tee -a "${OUTPUTFILE}"

eval ${TESTARGS:-${CMDS_TO_RUN}} | tee -a "${OUTPUTFILE}"
code=${PIPESTATUS[0]}
if [ ${code} -ne 0 ]; then
    echo "- fail: unexpected error code ${code}." |
     tee -a "${OUTPUTFILE}"
    result="FAIL"
else
    echo "- pass: the command returns 0." |
     tee -a "${OUTPUTFILE}"
    result="PASS"
fi

echo "- end of test." | tee -a "${OUTPUTFILE}"
report_result "${TEST}" "${result}" "${code}"
exit 0
