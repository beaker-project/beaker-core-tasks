#!/bin/sh

if [[ $# != 1 ]]; then 
	echo "Usage: $0 [guestname] "
	exit 1
fi

# if the guest isn't shutdown, shut it down.. try at least 2 times
guestup=0
i=0
while (( $i < 2 )) ; 
do 
	if virsh list | grep -w $1; then 
		guestup=1
		if ! virsh shutdown $1 ; then
			echo "problem with virsh shutdown $1"
			exit 1
		fi
		sleep 90
	fi
	let "i=${i}+1"	
done
		
if virsh list | grep -w $1; then 
	echo "the guest can't be brought down"
	exit 1
fi

if ! virsh dumpxml $1 > $1.xml ; then 
	echo "problem with virsh dumpxml $1"
	exit 1
fi

sed -n '
# if the first line copy the pattern to the hold buffer
1h
# if not the first line then append the pattern to the hold buffer
1!H
# if the last line then ...
$ {
        # copy from the hold to the pattern buffer
        g
        # do the search and replace
#    <serial type='pty'>
#      <target port='0'/>
#    </serial>
#    <console type='pty'>
#      <target port='0'/>
#    </console>
#
        s/<serial type='\''file'\''>.*<\/console>/<serial type='\''pty'\''>\
      <target port='\''0'\''\/>\
    <\/serial>\
    <console type='\''pty'\''>\
      <target port='\''0'\''\/>\
    <\/console>/g
        # print
        p
}
' $1.xml > $1.xml.tmp ;

#redefine the guest with the edited xml
if ! virsh define ./$1.xml.tmp; then 
	echo "problem with virsh define ./$1.xml.tmp"
	exit 1
fi

if [[ ${guestup} == 1 ]]; then 
	if ! virsh start $1; then 
		echo "problem restarting guest $1 "
		exit 1
	fi
	# give it some time to start up.
	sleep 90

	if ! virsh list | grep -w $1 ; then 
		echo "guest doesn't seem to be up after restart"
		exit 1
	fi
fi
