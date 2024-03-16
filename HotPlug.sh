#!/usr/bin/env bash

#开始HotPlug(mount Device),并进行检查;(此时硬盘状态已为JBOD并且所有分区及内容全部删除)
#wipefs -af /dev/sd*

for Clear in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}'); do
     wipefs -af "$Clear"
     sleep 5s
done
echo -e "\nClear all log and mkdir Begin test\n"

#脚本所在路径为Dir_pre
Dir_Pre=$(pwd)
mkdir -p /"$Dir_Pre"/4_5_Hot_Swap
cd /"$Dir_Pre"/4_5_Hot_Swap || exit

####----------系统变量----------###
Raid_Status=$(storcli64 /c0 show | grep -i "PD List" -A 20 | grep EID:Slt -A 15 | grep -v '^-*$' | sed '1d' | awk '{for(i=1;i<NF;i++) {if ( $i == "SATA" || $i == "SAS" ) print $i}}' | uniq)
AHCI_Status=$(wdckit s | grep Port -A 10 | awk '{print $3}' | grep -v '^-*$' | sed 1d | uniq)
Controller_Status=$(storcli64 /c0 show | grep Status | awk '{print $NF}')
Device_Status=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep HDD | awk '{print $3}' | sort -u)
Device_Type=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep HDD | awk '{print $NF}' | sort -u)
System_num=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -c HDD)

####----------确认系统盘----------###
bootdisk=$(df -h | grep -i boot | awk '{print $1}' | grep -iE "/dev/sd" | sed 's/[0-9]//g' | sort -u | awk -F "/" '{print $NF}')
if test -z "$bootdisk"; then
     bootdisk=$(df -h | grep -i boot | awk '{print $1}' | grep -iE "/dev/nvme" | sed 's/p[0-9]//g' | sort -u | awk -F "/" '{print $NF}')
     echo "os disk is $bootdisk"
else
     echo "os disk is $bootdisk"
fi

####----------调用SmartInfo----------###

function SmartInfo() {
     function SmartInfo_SATA() {

          function SmartInfo_log() {

               if [ "$Controller_Status" = "Success" ] && [[ "$Device_Status" != "JBOD" && "$Device_Type" != "JBOD" ]]; then
                    dev=$(smartctl --scan | grep /dev/bus | awk '{print $1}' | uniq)
                    for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
                         sn=$(smartctl -a -x -d "$hdd" "$dev" | grep -i "serial" | awk '{print $NF}')
                         smartctl -a -x -d "$hdd" "$dev" >smart_"$1"_"$hdd"_"$sn".log
                         if [ "$1" = "before" ]; then
                              echo "$hdd" >>HDD_Slot.log
                         fi
                    done
               else
                    for hdd in $(lsscsi | grep -i sd | grep -vw "$bootdisk" | awk -F "/" '{print $NF}'); do
                         sn=$(smartctl -a -x /dev/"$hdd" | grep -i "serial" | awk '{print $NF}')
                         smartctl -a -x /dev/"$hdd" >smart_"$1"_"$hdd"_"$sn".log
                         if [ "$1" = "before" ]; then
                              echo "$hdd" >> HDD_Slot.log
                         fi
                    done
               fi

               mkdir smart_"$1"

               #198为"UNC"关键词
               echo "SN  SLOT  1  3  5  7  10  194  198  199  health ICRC" >"$1".log

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
                    udma=$(grep "UDMA_CRC_Error_Count" smart_"$1"_"$hdd"_"$sn".log | awk '{print $NF}')
                    icrc=$(grep -i "ICRC" smart_"$1"_"$hdd"_"$sn".log | awk '{print $3}')
                    echo "$sn $hdd  $read_error $spin $reall $seek $spin_Retry_Count $tem $offline $udma $health   $icrc" >>"$1".log
               done <HDD_Slot.log

               column -t "$1".log >transit.log
               cat transit.log >"$1".log

               mv smart_"$1"_* smart_"$1"
          }

          if [ -d "smart_before" ]; then
               echo "Collect Smart_after and Compare with before"
               SmartInfo_log after

               for sn in $(cat before.log | sed 1d | awk '{print $1}'); do

                    slot_before=$(awk '$1=="'$sn'" {print $2}' before.log)
                    icrc_before=$(awk '$1=="'$sn'" {print $NF}' before.log)
                    UDMA_before=$(awk '$1=="'$sn'"{print $10}' before.log)
                    sn_after=$(awk '$1=="'$sn'" {print $1}' after.log)

                    if [ "$sn_after" == "$sn" ]; then
                         echo -e "\n----------$sn is exiting ,not lost,check pass----------\n" >>result.log

                         slot_after=$(awk '$1=="'$sn'" {print $2}' after.log)
                         if [ "$slot_after" == "$slot_before" ]; then
                              echo " $sn slot ch098 eck pass.slot is $slot_after" >>result.log
                         else
                              echo " $sn slot check failed. slot is $slot_after" >>result.log
                         fi

                         Raw_Read_Error_Rate=$(awk '$1=="'$sn'" {print $3}' after.log)
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

          else
               echo -e "Collect Smart_before\n"
               SmartInfo_log before

          fi

     }

     function SmartInfo_SAS() {

          function SmartInfo_log() {

               if [ "$Controller_Status" = "Success" ] && [[ "$Device_Status" != "JBOD" && "$Device_Type" != "JBOD" ]]; then
                    dev=$(smartctl --scan | grep /dev/bus | awk '{print $1}' | uniq)
                    for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
                         sn=$(smartctl -a -x -d "$hdd" "$dev" | grep -i "serial" | awk '{print $NF}')
                         smartctl -a -x -d "$hdd" "$dev" >smart_"$1"_"$hdd"_"$sn".log
                         if [ "$1" = "before" ]; then
                              echo "$hdd" >>HDD_Slot.log
                         fi
                    done
               else
                    for hdd in $(lsscsi | grep -i sd | grep -vw "$bootdisk" | awk -F "/" '{print $NF}'); do
                         sn=$(smartctl -a -x /dev/"$hdd" | grep -i "serial" | awk '{print $NF}')
                         smartctl -a -x /dev/"$hdd" >smart_"$1"_"$hdd"_"$sn".log
                         if [ "$1" = "before" ]; then
                              echo "$hdd" >>HDD_Slot.log
                         fi
                    done
               fi

               mkdir smart_"$1"

               echo -e "SN  SLOT Temp Read_error Write_error Elements Healthy DWORD1  \tDWORD2  " >"$1".log

               while read hdd; do
                    smartctl -a -x /dev/"$hdd" >"${1}"_"${hdd}"_"${sn}".log
                    mv "${1}"_"${hdd}"_"${sn}".log smart_"$1"
                    tem=$(grep "Current Drive Temperature" smart_"$1"_"$hdd"_"$sn".log | awk '{if($(NF-1) <= 60) print "pass";else print "failed"}')
                    Readerror=$(grep "Error counter log:" -A 10 smart_"$1"_"$hdd"_"$sn".log | grep "read:" | awk '{if($NF <= 0) print "pass";else print "failed"}')
                    Writeerror=$(grep "Error counter log:" -A 10 smart_"$1"_"$hdd"_"$sn".log | grep "write:" | awk '{if($NF == 0) print "pass";else print "failed"}')
                    Elements=$(grep "Elements in grown defect list:" smart_"$1"_"$hdd"_"$sn".log | awk '{if ($NF == 0) print "pass";else print "failed"}')
                    Healthy=$(grep "SMART Health Status:" smart_"$1"_"$hdd"_"$sn".log | awk '{if ($NF == "OK") print "pass";else print "failed"}')
                    DWORD1=$(grep "Invalid DWORD count" smart_"$1"_"$hdd"_"$sn".log | sed 2,2d | awk '{print $NF}')
                    DWORD2=$(grep "Invalid DWORD count" smart_"$1"_"$hdd"_"$sn".log | sed 1,1d | awk '{print $NF}')
                    echo -e "$sn   $hdd  $tem $Readerror       $Writeerror        $Elements     $Healthy    $DWORD1  \t\t\t$DWORD2  " >>"$1".log

               done <HDD_Slot.log

               column -t "$1".log >transit.log
               cat transit.log >"$1".log

               mv smart_"$1"_* smart_"$1"
          }

          if [ -d "smart_before" ]; then
               echo "create after_smart;and check hdd"
               SmartInfo_log after

               for sn in $(awk '{print $1}' before.log | sed 1d); do
                    slot_before=$(awk '$1=="'$sn'" {print $2}' before.log)
                    DWORD1_before=$(awk '$1=="'$sn'" {print $(NF-1)}' before.log)
                    DWORD2_before=$(awk '$1=="'$sn'"  {print  $NF}' before.log)
                    sn_after=$(awk '$1=="'$sn'" {print $1}' after.log)

                    if [ "$sn_after" == "$sn" ]; then
                         echo -e "\n----------$sn is exiting ,not lost,check pass----------\n" >>result.log

                         slot_after=$(awk '$1=="'$sn'" {print $2}' after.log)
                         if [ "$slot_after" == "$slot_before" ]; then
                              echo " $sn slot check pass.slot is $slot_after" >>result.log
                         else
                              echo " $sn slot check failed. slot is $slot_after" >>result.log
                         fi

                         Current_Drive_Temp=$(awk '$1=="'$sn'" {print $3}' after.log)
                         echo " $sn check Current_Drive_Temp is $Current_Drive_Temp" >>result.log

                         Read_Total_Uncorrected_Errors=$(awk '$1== "'$sn'" {print $4}' after.log)
                         echo " $sn check Read_Total_Uncorrected_Errors is $Read_Total_Uncorrected_Errors" >>result.log

                         Write_Total_Uncorrected_Errors=$(awk '$1=="'$sn'" {print $5}' after.log)
                         echo " $sn check Write_Total_Uncorrected_Errors $Write_Total_Uncorrected_Errors" >>result.log

                         Elements_in_grown_defect_list=$(awk '$1=="'$sn'" {print $6}' after.log)
                         echo " $sn check Elements_in_grown_defect_list is $Elements_in_grown_defect_list" >>result.log

                         health=$(awk '$1=="'$sn'" {print $7}' after.log)
                         echo " $sn  check health is $health" >>result.log

                         Invalid_DWORD_Count1=$(awk '$1=="'$sn'" {print $8}' after.log)
                         echo " $sn check Invalid_DWORD_Count1_before is $Invalid_DWORD_Count1" >>result.log

                         Invalid_DWORD_Count2=$(awk '$1=="'$sn'" {print $9}' after.log)
                         echo " $sn check Invalid_DWORD_Count2_before is $Invalid_DWORD_Count2" >>result.log

                         DWORD1_after=$(awk '$1=="'$sn'" {print $(NF-1)}' after.log)
                         DWORD2_after=$(awk '$1=="'$sn'" {print $(NF)}' after.log)
                         if [ "$DWORD1_after" -lt "$((DWORD1_before + 200))" ]; then
                              echo " $sn Invalid_DWORD_Count1 check pass. Invalid_DWORD_Count1_after IS $DWORD1_after" >>result.log
                         else
                              echo " $sn Invalid_DWORD_Count1 check failed. Invalid_DWORD_Count1_before is $DWORD1_before; Invalid_DWORD_Count1_after is  IS $DWORD1_after" >>result.log
                         fi
                         if [ "$DWORD2_after" -lt "$((DWORD2_before + 200))" ]; then
                              echo " $sn Invalid_DWORD_Count2 check pass. Invalid_DWORD_Count2_after IS $DWORD2_after" >>result.log
                         else
                              echo " $sn Invalid_DWORD_Count2 check failed. DWORD2_before is $DWORD2_before; Invalid_DWORD_Count2_after is  IS $DWORD2_after" >>result.log
                         fi

                    else
                         echo " $sn is lost,check failed" >>result.log
                    fi
               done

          else
               echo "create before_smart;and collect hdd"
               SmartInfo_log before

          fi
     }

     if [ "$Raid_Status" = "SATA" ] || [ "$AHCI_Status" = "SATA" ]; then
          SmartInfo_SATA
     else
          SmartInfo_SAS
     fi

     if [ -d "smart_after" ]; then
          grep -i failed result.log >failed.log
          mkdir result
          mv before.log result
          mv after.log result
          mv failed.log result
          mv result.log result
     fi
}

###------------FIO任务-----------###
function FIO_Block() {

     mkdir -p /"$Cur_Dir"/"$1"
     cd /"$Cur_Dir"/"$1" || exit

     mkdir -p 1M_{SW,SR} 4K_{RR,RW}

     ls /sys/block/ | grep sd | grep -v "$bootdisk" >block

     num=$(wc -l block)
     echo -e "\nTotal $num Device in the system\n"

     while read line; do
          echo "[${line}_seq_write_1M]" >>1M_SW/jobfile_sw
          echo "filename=/dev/$line" >>1M_SW/jobfile_sw

          echo "[${line}_seq_read_1M]" >>1M_SR/jobfile_sr
          echo "filename=/dev/${line}" >>1M_SR/jobfile_sr

          echo "[${line}_randwrite_4k]" >>4K_RW/jobfile_rw
          echo "filename=/dev/${line}" >>4K_RW/jobfile_rw

          echo "[${line}_randread_4k]" >>4K_RR/jobfile_rr
          echo "filename=/dev/${line}" >>4K_RR/jobfile_rr
     done <block

     echo -e "\n----------Do Sequential Write----------\n"
     cd 1M_SW || exit
     fio jobfile_sw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=write --bs=1M --output=1M_seqW.log --log_avg_msec=1000 --write_iops_log=1M_seqW_iops.log --write_lat_log=1M_seqW_lat.log &
     sleep 450s
     cd ..

     echo -e "\n----------Do Sequential Read----------\n"
     cd 1M_SR || exit
     fio jobfile_sr --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=read --bs=1M --output=1M_seqR.log --log_avg_msec=1000 --write_iops_log=1M_seqR_iops.log --write_lat_log=1M_seqR_lat.log &
     sleep 450s
     cd ..

     echo -e "\n----------Do Random Write----------\n"
     cd 4K_RW || exit
     fio jobfile_rw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=64 --rw=randwrite --bs=4k --output=4K_randW.log --log_avg_msec=1000 --write_iops_log=4K_randW_iops.log --write_lat_log=4K_randW_lat.log &
     sleep 450s
     cd ..

     echo -e "\n----------Do Random Read----------\n"
     cd 4K_RR || exit
     fio jobfile_rr --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=64 --rw=randread --bs=4k --output=4K_randR.log --log_avg_msec=1000 --write_iops_log=4K_randR_iops.log --write_lat_log=4K_randR_lat.log &
     sleep 450s
     cd ..

     echo -e "\nFinish $1 FIO task.\n"
     sleep 30s

     cd ..

}

###----------收集系统信息---------###
function System_log() {
     if [ "$1" -eq 0 ]; then
          dmesg -C
          sleep 5s
          echo >/var/log/messages
          sleep 5s
          ipmitool sel clear
          sleep 5s
     elif [ "$1" -eq 1 ]; then
          dmesg >dmesg.log
          sleep 5s
          cat /var/log/messages >messages.log
          sleep 5s
          ipmitool sel list >sel.log
          sleep 5s
     fi

}

###----------覆盖有无IO的热插拔测试---------###
function Hot_Swap() {

     System_log 0
     SmartInfo
     sleep 5s

     #进行不带IO的热插拔测试，创建相关文件夹并在其中测试
     function Swap_NoneIO() {
          mkdir -p /"$Dir_Pre"/4_5_Hot_Swap/NoneIO
          cd /"$Dir_Pre"/4_5_Hot_Swap/NoneIO || exit

          echo -e "\nDo Swap_NoneIO first\n"
          sleep 5s

          #记录最初始的硬盘状态
          echo -e "[ $(date "+%F %T") ]\n\n" >>process.log
          lsblk | tee -a process.log

          #对奇数号硬盘进行分区并对分区1进行格式化
          for Test_Device in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}' | awk 'NR%2 ==1'); do
               parted /dev/"$Test_Device" mktable gpt
               sleep 5s
               parted -a opt /dev/"$Test_Device" mkpart primary ext4 4096s 10GB
               sleep 5s
               parted -a opt /dev/"$Test_Device" mkpart primary ext4 10GB 100%
               sleep 5s

               #输出lsblk，检查是否成功分区，如果成功分区，则对其格式化
               for Test_Device_num in $(lsblk | awk '{print $1}' | sed 1d | sed '/'$bootdisk'/d' | sed '/cl/d' | grep "$Test_Device" | wc -l); do
                    if [ "$Test_Device_num" -eq "3" ]; then
                         echo -e "\n$Test_Device partition successful\n"
                    else
                         echo -e "\n$Test_Device Fail\n"
                         partition_status=0
                    fi
               done

               if [ "$partition_status" -eq "0" ]; then
                    echo -e "\nManually change status\n"
                    sleep 300s
               else
                    echo -e "\npartition successful and Format the Device\n"
               fi

               mkfs -t ext4 /dev/"$Test_Device"1
               sleep 5s

          done

          #第一次输出lsblk，为分区之后的盘符，所有盘符在线，并且已分区
          echo -e "\n[ $(date "+%F %T") ]\n\n" >>process.log
          lsblk | tee -a process.log

          #开始进行热插拔操作，对每块盘挂载后生成文件以及MD5校验码
          for Test_Device in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}' | awk 'NR%2 ==1'); do
               mount /dev/"$Test_Device"1 /mnt
               dd if=/dev/urandom of=/mnt/test bs=1M count=1000 | tee -a process.log
               sleep 5s

               cd /mnt || exit
               echo -e "\nDo md5 check\n"
               sleep 5s
               md5sum test >test.md5
               sleep 5s

               cd /"$Dir_Pre"/4_5_Hot_Swap/NoneIO || exit
               umount /mnt
               echo -e "\n\numount the Device Please swap the $Test_Device\n"
               sleep 20s

               #拔出硬盘并在键盘输入，判定是否拔出硬盘
               read -r -p "Have the Device been removed? [Y/n] " input

               case $input in
               [yY][eE][sS] | [yY])
                    echo -e "The Device been removed,wait to collect data\n"
                    ;;

               [nN][oO] | [nN])
                    echo "Device need to removed"
                    exit 1
                    ;;

               *)
                    echo "Invalid input..."
                    exit 1
                    ;;
               esac

               #将硬盘拔出，并使用lsblk将其记录
               echo -e "\n\n[ $(date "+%F %T") ]\n\n" >>process.log
               lsblk | tee -a process.log

               #当把硬盘插入后，等待系统识别硬盘，然后记录此时系统内硬盘
               echo -e "\n\n Please Insert  drives\n"
               sleep 20s

               read -r -p "Have the Device been Inserted? [Y/n] " input

               case $input in
               [yY][eE][sS] | [yY])
                    echo -e "The Device been Inserted,wait to collect data\n"
                    sleep 20s
                    ;;

               [nN][oO] | [nN])
                    echo "some drives need to Insert"
                    exit 1
                    ;;

               *)
                    echo "Invalid input..."
                    exit 1
                    ;;
               esac

               sleep 20s
               echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
               lsblk | tee -a process.log

               #判定是否所有的硬盘均在线，若硬盘在线，重新挂载，并检查md5校验码,否则重新进行测试
               Online_num=$(wdckit s | grep -vw "$bootdisk" | grep "/dev/sd" | wc -l)
               if [ "$Online_num" = "$System_num" ]; then
                    mount /dev/"$Test_Device"1 /mnt
                    echo -e "\nThe Device was Identified\n"
               else
                    echo -e "\nThe Device wasn't Identified,restart test\n"
                    exit 1
               fi

               #进入/mnt文件夹，对比md5校验码，并回到Swap_NoneIO文件夹，取消挂载，开始下一块硬盘

               cd /mnt || exit
               md5sum -c test.md5 >>/"$Dir_Pre"/4_5_Hot_Swap/NoneIO/process.log
               sleep 5s
               cd /"$Dir_Pre"/4_5_Hot_Swap/NoneIO || exit
               umount /mnt
               sleep 5s
          done
     }

     Swap_NoneIO

     function Swap_IO() {
          mkdir -p /"$Dir_Pre"/4_5_Hot_Swap/IO
          cd /"$Dir_Pre"/4_5_Hot_Swap/IO || exit

          echo -e "\nDo Swap_IO\n"
          sleep 5s

          #记录最初始的硬盘状态
          echo -e "[ $(date "+%F %T") ]\n\n" >>process.log
          lsblk | tee -a process.log

          #奇数号硬盘在Swap_NoneIO时已分区格式化完成，现在对其重新挂载及生成相关文件
          #开始进行热插拔操作，对每块盘挂载后生成文件以及MD5校验码

          for Test_Device in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}' | awk 'NR%2 ==1'); do
               mkdir -p /mnt/"$Test_Device"
               mount /dev/"$Test_Device"1 /mnt/"$Test_Device"
               dd if=/dev/urandom of=/mnt/"$Test_Device"/test_IO bs=1M count=1000 
               sleep 5s

               cd /mnt/"$Test_Device" || exit
               md5sum test_IO >test_IO.md5

               cd /"$Dir_Pre"/4_5_Hot_Swap/IO || exit
               umount /mnt/"$Test_Device"
               sleep 5s

               #对分区2以及其他待测盘进行IO，等待IO起来，拔测试盘
               mkdir -p /"$Dir_Pre"/4_5_Hot_Swap/IO/"$Test_Device"
               cd /"$Dir_Pre"/4_5_Hot_Swap/IO/"$Test_Device" || exit

               ls /sys/block/ | grep sd | grep -v "$bootdisk" | sed '/'$Test_Device'/d' >block

               while read line; do
                    echo "[${line}_randwrite_4k]" >>jobfile_rw
                    echo "filename=/dev/$line" >>jobfile_rw
               done <block

               fio jobfile_rw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=4 --iodepth=64 --rw=randwrite --bs=4k --log_avg_msec=1000 >4k_RW.log &

               fio --ioengine=libaio --norandommap --thread --direct=1 --name=test --ramp_time=60 --runtime=300 --time_based --numjobs=4 --iodepth=64 --filename=/dev/"$Test_Device" --rw=randwrite --bs=4k >4k_"$Test_Device".log &

               sleep 60s
               iostat -x 5 >> iostat_all.log &
               sleep 60s

               #等待60s，性能区域稳定，将测试硬盘拔出，其他硬盘此时应仍在测试中
               echo -e "\n\nSwap $Test_Device\n\n"
               sleep 30s

               #拔出硬盘并在键盘输入，判定是否拔出硬盘
               read -r -p "Have the Device been removed? [Y/n] " input

               case $input in
               [yY][eE][sS] | [yY])
                    echo -e "The Device been removed,wait to collect data\n"
                    ;;

               [nN][oO] | [nN])
                    echo "Device need to removed"
                    exit 1
                    ;;

               *)
                    echo "Invalid input..."
                    exit 1
                    ;;
               esac

               #将硬盘拔出，并使用lsblk将其记录
               echo -e "\n\n[ $(date "+%F %T") ]\n\n" >>process.log
               lsblk | tee -a process.log

               #当把硬盘插入后，等待系统识别硬盘，然后记录此时系统内硬盘
               echo -e "\n\n Please Insert  drives\n"
               sleep 20s

               read -r -p "Have the Device been Inserted? [Y/n] " input

               case $input in
               [yY][eE][sS] | [yY])
                    echo -e "The Device been Inserted,wait to collect data\n"
                    sleep 20s
                    ;;

               [nN][oO] | [nN])
                    echo "some drives need to Insert"
                    exit 1
                    ;;

               *)
                    echo "Invalid input..."
                    exit 1
                    ;;
               esac

               sleep 20s
               echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
               lsblk | tee -a process.log

               #判定是否所有的硬盘均在线，若硬盘在线，重新挂载，并检查md5校验码,否则重新进行测试
               Online_num=$(wdckit s | grep "/dev/sd" | grep -vw "$bootdisk" | wc -l)
               if [ "$Online_num" = "$System_num" ]; then
                    echo -e "\nThe Device was Identified\n"
                    mount /dev/"$Test_Device"1 /mnt/"$Test_Device"
               else
                    echo -e "\nThe Device wasn't Identified,restart test\n"
                    exit 1
               fi

               #进入/mnt文件夹，对比md5校验码，并回到Swap_NoneIO文件夹，取消挂载，开始下一块硬盘
               cd /mnt/"$Test_Device" || exit
               md5sum -c test_IO.md5 >>/"$Dir_Pre"/4_5_Hot_Swap/IO/process.log
               sleep 5s
               cd /"$Dir_Pre"/4_5_Hot_Swap/IO || exit
               umount /mnt
               killall fio
               sleep 3s
               killall iostat
          done
     }

     Swap_IO

     ###-----------完成热插拔以后，收集Smart和系统log----------###
     cd /"$Dir_Pre"/4_5_Hot_Swap || exit
     SmartInfo
     sleep 10s
     System_log 1

}

function Hotplug_Raid() {

     mkdir -p /"$Dir_Pre"/Raid
     cd /"$Dir_Pre"/Raid || exit
     Cur_Dir=$(pwd)

     System_log 0

     SmartInfo

     #判定是否有Virtual disk
     Virtural_num=$(storcli64 /c0/vall show | grep -i "Virtual Drives :" -A 15 | grep -i "raid" | awk '{print $2}')
     if [ ! -n "$Virtural_num" ]; then
          echo -e "\nNo Virtural disk,build raid\n"
     else
          echo -e "\nexist virtural disk.delete\n"
          storcli64 /c0/vall delete force
          storcli64 /c0/fall delete
          sleep 30s
     fi

     #创建raid1
     storcli64 /c0/eall/sall set good force
     sleep 10s
     Status=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | awk '{print $3}' | uniq)

     if [ "$Status" = "UGood" ]; then
          echo "UG Mode Success"
     else
          echo "check Devices Status,Can't Build Raid1"
          exit 0
     fi

     for ((EID_index = 1; EID_index < 10; EID_index++)); do
          EID_String=$(storcli /c0 show | grep -i "pd list" -A 15 | grep -i eid | awk '{print $'$EID_index'}')

          if [ "$EID_String" = "EID:Slt" ]; then
               EID=$(storcli /c0 show | grep -i "pd list" -A 15 | grep -i tb | awk '{print $'$EID_index'}' | awk -F ":" '{print $1}' | uniq)
               break
          else
               echo "EID not {$EID_index}th,find the next "
          fi
     done

     for Capacity in $(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | awk '{print $5}' | sort -n | uniq); do
          Slot_num=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep -c "$Capacity")
          if [ "$Slot_num" -eq 2 ]; then
               Slot_1=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep "$Capacity" | awk '{print $1}' | awk -F ":" '{print $2}' | sed -n '1p')
               Slot_2=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep "$Capacity" | awk '{print $1}' | awk -F ":" '{print $2}' | sed -n '2p')
               storcli64 /c0 add vd type=raid1 drive="$EID":"$Slot_1","$Slot_2"
               sleep 10s
          elif [ "$Slot_num" -gt 3 ]; then
               i=1
               j=2
               while [ "$j" -le "$Slot_num" ]; do
                    Slot_1=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep "$Capacity" | awk '{print $1}' | awk -F ":" '{print $2}' | sed -n "$i"p)
                    Slot_2=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep "$Capacity" | awk '{print $1}' | awk -F ":" '{print $2}' | sed -n "$j"p)

                    storcli64 /c0 add vd type=raid1 drive="$EID":"$Slot_1","$Slot_2"
                    sleep 5s

                    i=$((i+2))
                    j=$((j+2))
               done
          fi

     done

     #重复查询是否成功建立raid1

     Status=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | awk '{print $3}' | uniq)
     if [ "$Status" = "Onln" ]; then
          echo -e "\nAll Device finish Raid1\n"
          sleep 10s
     else
          echo -e "\nRaid1 build fail"
          exit 0
     fi

     #开启第一次FIO，记录FIO数据并在结束后，开启第二次FIO

     FIO_Block First_FIO

     #重新建立一个文件夹，并运行任一fio，性能稳定后将盘拔出

     echo -e "\n----------Do Fio keep performance----------\n"

     mkdir -p /"$Cur_Dir"/Second_FIO
     cd Second_FIO || exit
     cp "$Cur_Dir"/First_FIO/1M_SR/jobfile_sr /"$Cur_Dir"/Second_FIO
     fio jobfile_sr --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=read --bs=1M >>Second_FIO.log &
     sleep 220s
     cd ..

     #提示插拔盘并识别,将硬盘拔出和插入过程记录
     #记录未拔出硬盘时间/硬盘数量
     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
     wdckit s | tee -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log

     echo -e "\nCollect All Devices data,ready to swap Devices\n"
     echo -e "\n----------Please Swap the disk and Check later----------\n"
     sleep 30s

     #拔出硬盘并在键盘输入，判定是否拔出所有硬盘
     read -r -p "Have all the drives been removed? [Y/n] " input

     case $input in
     [yY][eE][sS] | [yY])
          echo -e "all the drives been removed,wait to collect data\n"
          ;;

     [nN][oO] | [nN])
          echo "some drives need to removed"
          exit 1
          ;;

     *)
          echo "Invalid input..."
          exit 1
          ;;
     esac

     #记录拔出硬盘时间，以及此时系统硬盘记录
     sleep 15s
     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
     wdckit s | tee -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log
     echo -e "\nRemoved Devices,record system disks"

     #当把硬盘插入后，等待系统识别硬盘，然后记录此时系统内硬盘
     echo -e "\n Please Insert  drives\n"
     sleep 20s

     read -r -p "Have all the drives been Inserted? [Y/n] " input

     case $input in
     [yY][eE][sS] | [yY])
          echo -e "all the drives been Inserted,wait to collect data\n"
          sleep 20s
          ;;

     [nN][oO] | [nN])
          echo "some drives need to Insert"
          exit 1
          ;;

     *)
          echo "Invalid input..."
          exit 1
          ;;
     esac

     sleep 20s
     echo -e "\nCheck whether the devices is being rebuilt\n"

     #判定此时系统是否识别硬盘及正在rebuild
     #当硬盘状态为rebuild且raid状态为dgrd时为正确状态

     Virtual_Status=$(storcli64 /c0/vall show | grep -i "rwtd" | awk '{print $3}' | sort -u)
     Device_StatusNums=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i "rbld" | wc -l)
     System_Raidnum=$(("$System_num" / 2))

     if [ "$Virtual_Status" = "Dgrd" ] && [ "$Device_StatusNums" = "$System_Raidnum" ]; then
          echo "Devices are doing rebuilding"
     else
          echo "Devices are Status false,can't rebuild raid1.Test Failure"
          exit 0
     fi

     #记录此时硬盘正在rebuild

     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
     wdckit s | te e -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log

     sleep 15s

     echo -e "\n\nDevice is being rebuilding\n"

     while [ "$Virtual_Status" = "Dgrd" ]; do
          sleep 1800s
          Virtual_Status=$(storcli64 /c0/vall show | grep -i "rwtd" | awk '{print $3}' | sort -u | grep -v Optl)
     done

     sleep 300s
     echo -e "\nFinish Rebuild,Prepare Collect Log\n"

     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
     wdckit s | tee -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log

     FIO_Block Third

     sleep 60s
     storcli64 /c0/vall delete 
     storcli64 /c0/eall/sall set jbod
     sleep 5s
     
     SmartInfo
     System_log 1

     echo -e "\n\nFinish Hot_Raid\n\n"
}

function heat_exchange() {
     mkdir -p /"$Dir_Pre"/6_heat_exchange
     cd /"$Dir_Pre"/6_heat_exchange || exit

     echo -e "\nStart Heat Exchange Test\n"

     SmartInfo
     System_log 0

     for heat_exchange_Time in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}' | awk 'NR%2 ==1');do
          i=1
          echo -e "\nThis is ${i}th Hot Plug\n"
          sleep 10s

          echo -e "\n\n[ $(date "+%F %T") ]\n\n" >>process.log
          lsblk | tee -a process.log
          sleep 3s

          echo -e "\n\nPlease swap the $heat_exchange_Time\n"
          sleep 20s

          read -r -p "Have the Device been removed? [Y/n] " input

          case $input in
          [yY][eE][sS] | [yY])
               echo -e "The Device been removed,wait to collect data\n"
               ;;

          [nN][oO] | [nN])
               echo "Device need to removed"
               exit 1
               ;;

          *)
               echo "Invalid input..."
               exit 1
               ;;
          esac

          #将硬盘拔出，并使用lsblk将其记录
          sleep 15s
          echo -e "\n\n[ $(date "+%F %T") ]\n\n" >>process.log
          lsblk | tee -a process.log

          #当把硬盘插入后，等待系统识别硬盘，然后记录此时系统内硬盘
          echo -e "\n\n Please Insert  drives\n"
          sleep 30s

          read -r -p "Have the Device been Inserted? [Y/n] " input

          case $input in
          [yY][eE][sS] | [yY])
               echo -e "The Device been Inserted,wait to collect data\n"
               sleep 30s
               ;;

          [nN][oO] | [nN])
               echo "some drives need to Insert"
               exit 1
               ;;

          *)
               echo "Invalid input..."
               exit 1
               ;;
          esac

          sleep 30s
          System_HDDnum=$(lsblk | grep -c sd)
          if [ "$System_HDDnum" -eq "$System_num" ]; then
               echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
               lsblk | tee -a process.log
          else
               echo -e "\nHeat Exchange Test Fail,can't Identify all slot.\n"
               exit 0
          fi

          i=$((i+1))
     done

     echo "Please Exchange Device"
     sleep 20s
     echo "Please Exchange Device"
     sleep 30s

     SmartInfo
     System_log 1

     echo -e "\n\nTest finish,Do Hot_add Manual"
}

Hot_Swap

Hotplug_Raid

###----判定前两项是否结束，手动开始热交换----###

read -r -p "Finish Other test and begin heat_exchange [Y/n] ？" input

          case $input in
          [yY][eE][sS] | [yY])
               echo -e "The Other test finish and begin heat_exchange \n"
               heat_exchange
               ;;

          [nN][oO] | [nN])
               echo "Wait manual test"
               exit 1
               ;;

          *)
               echo "Invalid input..."
               exit 1
               ;;
          esac


