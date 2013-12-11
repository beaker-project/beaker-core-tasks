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

# workaround for BZ 731115
l_guest_name=$(echo $1 | tr [:upper:] [:lower:])
REPL_STR=$(cat << EOF
    <serial type='file'>\n
      <source path='/mnt/tests/distribution/virt/install/${l_guest_name}/logs/${l_guest_name}_console.log'/>\n
      <target port='0'/>\n
    </serial>\n
    <console type='file'>\n
      <source path='/mnt/tests/distribution/virt/install/${l_guest_name}/logs/${l_guest_name}_console.log'/>\n
      <target port='0'/>\n
    </console>
EOF
)

serialline=$(grep -n '<serial ' $1.xml | awk -F: '{print $1}')
let "serialline=${serialline}-1"
consoleline=$(grep -n '</console>' $1.xml | awk -F: '{print $1}')
let "consoleline=${consoleline}+1"
sed -n '1,'"${serialline}"'p' $1.xml > $1.xml.tmp
echo -e $REPL_STR >> $1.xml.tmp
sed -n ''"${consoleline}"',$p' $1.xml >> $1.xml.tmp

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
