#!/bin/bash

#查询并显示系统盘

bootdisk=$(df -h | grep -i boot | awk '{print $1}' | grep -iE "/dev/sd" | sed 's/[0-9]//g' | sort -u | awk -F "/" '{print $NF}')
if test -z "$bootdisk"; then
	bootdisk=$(df -h | grep -i boot | awk '{print $1}' | grep -iE "/dev/nvme" | sed 's/p[0-9]//g' | sort -u | awk -F "/" '{print $NF}')
	echo -e "\n\nos disk os $bootdisk\n\n"
else
	echo -e "\n\nos disk os $bootdisk\n\n"
fi

function SmartInfo_log() {

	Controller_Status=$(storcli64 /c0 show | grep Status | awk '{print $NF}')
	Device_Status=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep HDD | awk '{print $3}' | sort -u)

	# if [ "$Controller_Status" = "Success" ]; then
	# 	if [ "$Device_Status" = "JBOD" ]; then
	# 		for hdd in $(lsscsi | grep -i sd | grep -vw "$bootdisk" | awk -F "/" '{print $NF}'); do
	# 			sn=$(smartctl -a -x /dev/"$hdd" |grep -i "serial" |awk '{print $NF}')
	# 			smartctl -a -x /dev/"$hdd" >smart_"$1"_"$hdd"_"$sn".log
	# 		done
	# 	else
	# 		dev=$(smartctl --scan | grep /dev/bud | awk '{print $1}' | uniq)
	# 		for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
	# 			sn=$(smartctl -a -x -d "$hdd" "$dev" |grep -i "serial" |awk '{print $NF}')
	# 			smartctl -a -x -d "$hdd" "$dev" >smart_"$1"_"$hdd"_"$sn".log
	# 		done
	# 	fi
	# else
	# 	for hdd in $(lsscsi | grep -i sd | grep -vw "$bootdisk" | awk -F "/" '{print $NF}'); do
	# 		sn=$(smartctl -a -x /dev/"$hdd" |grep -i "serial" |awk '{print $NF}')
	# 		smartctl -a -x /dev/"$hdd" >smart_"$1"_"$hdd"_"$sn".log
	# 	done
	# fi

	if [ "$Controller_Status" = "Success" ] && [ "$Device_Status" != "JBOD" ]; then
		dev=$(smartctl --scan | grep /dev/bud | awk '{print $1}' | uniq)
		for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
			sn=$(smartctl -a -x -d "$hdd" "$dev" | grep -i "serial" | awk '{print $NF}')
			smartctl -a -x -d "$hdd" "$dev" >smart_"$1"_"$hdd"_"$sn".log
			$hdd >>HDD_Slot.log
		done
	else
		for hdd in $(lsscsi | grep -i sd | grep -vw "$bootdisk" | awk -F "/" '{print $NF}'); do
			sn=$(smartctl -a -x /dev/"$hdd" | grep -i "serial" | awk '{print $NF}')
			smartctl -a -x /dev/"$hdd" >smart_"$1"_"$hdd"_"$sn".log
			$hdd >>HDD_Slot.log
		done
	fi

	mkdir smart_"$1"

	#198为"UNC"关键词
	echo -e "SN\n\nSLOT 1    3    5    7    10   194  198  199  health ICRC" >"$1".log

	while read hdd; do
		sn=$(grep "Serial Number:" smart_"$1"_"$hdd"_*.log | awk '{print $NF}')
		health=$(grep -i health smart_"$1"_"$hdd"_"$sn".log | awk '{if ($NF == "PASSED") print "pass";else print "failed"}')
		read_error=$(grep "Raw_Read_Error_Rate" smart_"$1"_"$hdd"_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
		spin=$(grep "Spin_Up_Time" smart_"$1"_"$hdd"_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
		reall=$(grep "Reallocated_Sector_Ct" smart_"$1"_"$hdd"_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
		seek=$(grep "Seek_Error_Rate" smart_"$1"_"$hdd"_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
		spin_Retry_Count=$(grep "Spin_Retry_Count" smart_"$1"_"$hdd"_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
		tem=$(grep "Temperature_Celsius" smart_"$1"_"$hdd"_"$sn".log | awk '{if($(NF-2) <= 60) print "pass";else print "failed"}')
		offline=$(grep "Offline_Uncorrectable" smart_"$1"_"$hdd"_"$sn".log | awk '{if($NF == 0) print "pass";else print "failed"}')
		udma=$(grep "UDMA_CRC_Error_Count" smart_"$1"_"$hdd"_"$sn".log | awk '{if($NF == 0) print "pass";else print "failed"}')
		icrc=$(grep -i "ICRC" smart_"$1"_"$hdd"_"$sn".log | awk '{print $3}')
		echo -e "$sn\n\n$slot  $read_error $spin $reall $seek $spin_Retry_Count $tem $offline $udma $health   $icrc" >>"$1".log
	done <HDD_Slot.log
	mv smart_"$1"_* smart_"$1"
}

if [ -d "smart_before" ]; then
	echo -e "\ncreate after_smart;and check hdd\n"
	SmartInfo_log after

	for sn in $(cat before.log | sed 1d | awk '{print $1}'); do

		slot_before=$(awk '$1=="'$sn'" {print $2}' before.log)
		icrc_before=$(awk '$1=="'$sn'" {print $NF}' before.log)
		UDMA_before=$(awk '$1=="'$sn'"{print $10}' before.log)
		sn_after=$(awk '$1=="'$sn'" {print $1}' after.log)

		if [ "$sn_after" == "$sn" ]; then
			echo "**********$sn is exiting ,not lost,check pass***************" >>result.log

			slot_after=$(cat after.log | awk '$1=="'$sn'" {print $2}')
			if [ "$slot_after" == $slot_before ]; then
				echo " $sn slot ch098 eck pass.slot is $slot_after" >>result.log
			else
				echo " $sn slot check failed. slot is $slot_after" >>result.log
			fi

			Raw_Read_Error_Rate=$(cat after.log | awk '$1=="'$sn'" {print $3}')
			echo " $sn check Raw_Read_Error_Rate is $Raw_Read_Error_Rate" >>result.log

			Spin_Up_Time=$(cat after.log | awk '$1=="'$sn'" {print $4}')
			echo " $sn check Spin_Up_Time is $Spin_Up_Time" >>result.log

			Reallocated_Sector_Ct=$(cat after.log | awk '$1=="'$sn'" {print $5}')
			echo " $sn check Reallocated_Sector_Ct is $Reallocated_Sector_Ct" >>result.log

			Seek_Error_Rate=$(cat after.log | awk '$1=="'$sn'" {print $6}')
			echo " $sn check Seek_Error_Rate is $Seek_Error_Rate" >>result.log

			Spin_Retry_Count=$(cat after.log | awk '$1=="'$sn'" {print $7}')
			echo " $sn check Spin_Retry_Count is $Spin_Retry_Count" >>result.log

			Temperature_Celsius=$(cat after.log | awk '$1=="'$sn'" {print $8}')
			echo " $sn check Temperature_Celsius is $Temperature_Celsius" >>result.log

			Offline_Uncorrectable=$(cat after.log | awk '$1=="'$sn'" {print $9}')
			echo " $sn check Offline_Uncorrectable is $Offline_Uncorrectable" >>result.log

			health=$(cat after.log | awk '$1=="'$sn'" {print $11}')
			echo " $sn  check health is $health" >>result.log

			icrc_after=$(cat after.log | awk '$1=="'$sn'" {print $NF}')
			if [ "$icrc_after" == $icrc_before ]; then
				echo " $sn ICRC check pass. ICRC IS $icrc_after" >>result.log
			else
				echo " $sn ICRC check failed. ICRC is $icrc_after" >>result.log
			fi
			UDMA_after=$(cat after.log | awk '$1=="'$sn'" {print $10}')
			if [ "$UDMA_after" == "$UDMA_before" ]; then
				echo " $sn UDMA check pass. UDMA_before is $UDMA_before UDMA_after is $UDMA_after" >>result.log
			else
				echo " $sn UDMA check failed. UDMA_before is $UDMA_before UDMA_after is $UDMA_after" >>result.log
			fi
		else
			echo " $sn is lost,check failed" >>result.log
		fi

	done

	cat result.log | grep -i failed >failed.log
	mkdir result
	mv *.log result

else
	echo "create before_smart;and collect hdd"
	SmartInfo_log before

fi