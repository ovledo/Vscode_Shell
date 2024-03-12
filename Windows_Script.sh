#!/usr/bin/env bash

function wdckit () {
    for i in {1..5}; do
		for sn in $(wdckit s | grep -i -E "HUH721212AL5200|HUS726T6TAL5204|HUS728T8TAL5204|WUS721010AL5204" | awk '{print $8}'); do
			model=$(wdckit s |grep -i "$sn" | awk '{print $(NF-2)}' )
			if [ "$model" == "HUH721212AL5200" ]; then
				 FW_Code1=LEGNA3S0.bin
				 FW_Code2=LEGNA9Y0.bin
			elif [ "$model" == "HUS726T6TAL5204" ]; then
				 FW_Code1=VKGNC460.bin
				 FW_Code2=VKGNC9Y0.bin 
			elif [ "$model" == "HUS728T8TAL5204" ]; then
				 FW_Code1=V8GNC460.bin
				 FW_Code2=V8GNC9Y0.bin
			else
				 FW_Code1=VXGCC9C0.bin
				 FW_Code2=VXGCC9Y2.bin
			fi
			wdckit u --serial "${sn}" -f ./$FW_Code1  >wdckit_"${sn}"_"${i}"cycle_downgrade.log 
			sleep 30
			wdckit u --serial "${sn}" -f ./$FW_Code2  >wdckit_"${sn}"_"${i}"cycle_upgrade.log 
			sleep 30 
		done  
		wdckit_Count=$(ls -l wdckit_* | wc -l)
        
		Succeeded_Count=$(cat wdckit_* |grep -o successful |wc -l)
		if [ "$wdckit_Count" -eq "$Succeeded_Count" ]; then
		 echo  "This cycle true"
		 cd ..
		else
		 echo "The cycle_{$i} false"
		fi
	done
	echo -e "wdckit FW update has done.\n"
}

function Storcli () {
    for eidnum in $(storcli64 /c0 show | grep -i "PD LIST :" -A 20 | grep HDD | awk '{print $1}'); do
		eid=$(echo "$eidnum" | awk -F ":" '{print $1}')
		eidslot=$(echo "$eidnum" | awk -F ":" '{print $NF}')
		Model=$(storcli64 /c0 show | grep -i "PD LIST :" -A 20 | grep "$eidnum " | awk '{print $(NF-2)}')

		if [ "$Model" == "HUH721212AL5200" ]; then
				 FW_Code1=LEGNA3S0.bin
				 FW_Code2=LEGNA9Y0.bin
			elif [ "$Model" == "HUS726T6TAL5204" ]; then
				 FW_Code1=VKGNC460.bin
				 FW_Code2=VKGNC9Y0.bin 
			elif [ "$Model" == "HUS728T8TAL5204" ]; then
				 FW_Code1=V8GNC460.bin
				 FW_Code2=V8GNC9Y0.bin
			else
				 FW_Code1=VXGCC9C0.bin
				 FW_Code2=VXGCC9Y2.bin
			fi
		echo "-----------------------Do Slot_${eidslot} Storcli64 FW_update-----------------------"
		for i in {1..5}; do
			storcli64 /c0/e"$eid"/s"$eidslot" download src=./$FW_Code1 | tee -a storcli64_"${eid}"_"${eidslot}"_"${i}"downgrade.log 
			sleep 20
			storcli64 /c0/e"$eid"/s"$eidslot" download src=./$FW_Code2 | tee -a storcli64_"${eid}"_"${eidslot}"_"${i}"upgrade.log 
			sleep 20
			echo -e "This is Slot_${eidslot} ${i}th_cycle.\n "
		done
	done
}


if [ "$1" == wdckit ]; then
     wdckit
else
     Storcli
fi

