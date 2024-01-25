#!/usr/bin/env bash

####----------确认系统盘----------###
bootdisk=$(df -h | grep -i boot | awk '{print $1}' | grep -iE "/dev/sd" | sed 's/[0-9]//g' | sort -u | awk -F "/" '{print $NF}')
if test -z "$bootdisk"; then
     bootdisk=$(df -h | grep -i boot | awk '{print $1}' | grep -iE "/dev/nvme" | sed 's/p[0-9]//g' | sort -u | awk -F "/" '{print $NF}')
     echo "os disk is $bootdisk"
else
     echo "os disk is $bootdisk"
fi

#开始HotPlug(mount Device),并进行检查;(此时硬盘状态已为JBOD并且所有分区及内容全部删除)
#wipefs -af /dev/sd*

for Clear in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}'); do
     wipefs -af "$Clear"
     sleep 5s
done

echo -e "\nClear all log and mkdir Begin test\n"

Dir_Pre=$(pwd)

mkdir -p /"$Dir_Pre"/Hot_Swap
cd /"$Dir_Pre"/Hot_Swap || exit
System_num=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i jbod | wc -l)

###----------覆盖有无IO的热插拔测试---------###
function Hot_Swap() {

     #清除系统信息并收集Smart log
     dmesg -C
     sleep 5s
     echo >/var/log/messages
     sleep 5s
     ipmitool sel clear
     sleep 5s

     #在整个热插拔测试前，做smart信息收集，在带IO的结束后进行第二次收集，目录在Hot_Swap下
     function SmartInfo_before_Swap() {
          #判定是SATA盘还是SAS盘，收集不同的数据
          echo -e "\n----------Create folder to collect smart_before----------\n"

          function Smartbefore_SAS() {
               mkdir smart_before
               echo -e "SN         SLOT Temp Read_error Write_error Elements Healthy DWORD1  \tDWORD2  " >before.log
               for hdd in $(lsscsi | grep -i sd | grep -vw "$bootdisk" | awk -F "/" '{print $NF}'); do
                    sn=$(smartctl -a -x /dev/"${hdd}" | grep -i "Serial Number:" | awk '{print $NF}')
                    smartctl -a -x /dev/"$hdd" >smart_before_"$sn".log
                    tem=$(grep "Current Drive Temperature" smart_before_"$sn".log | awk '{if($(NF-1) <= 60) print "pass";else print "failed"}')
                    Readerror=$(grep "Error counter log:" -A 10 smart_before_"$sn".log | grep "read:" | awk '{if($NF <= 0) print "pass";else print "failed"}')
                    Writeerror=$(grep "Error counter log:" -A 10 smart_before_"$sn".log | grep "write:" | awk '{if($NF == 0) print "pass";else print "failed"}')
                    Elements=$(grep "Elements in grown defect list:" smart_before_"$sn".log | awk '{if ($NF == 0) print "pass";else print "failed"}')
                    Healthy=$(grep "SMART Health Status:" smart_before_"$sn".log | awk '{if ($NF == "OK") print "pass";else print "failed"}')
                    DWORD1=$(grep "Invalid DWORD count" smart_before_"$sn".log | sed 2,2d | awk '{print $NF}')
                    DWORD2=$(grep "Invalid DWORD count" smart_before_"$sn".log | sed 1,1d | awk '{print $NF}')
                    echo -e "$sn   $hdd  $tem $Readerror       $Writeerror        $Elements     $Healthy    $DWORD1  \t\t\t$DWORD2  " >>before.log
               done
          }

          function Smartbefore_SATA() {
               mkdir smart_before
               echo -e "SN       SLOT 1    3    5    7    10   194  198  199  health ICRC" >before.log
               for hdd in $(wdckit s | grep -i sd | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}'); do
                    sn=$(smartctl -a -x /dev/"$hdd" | grep -i "Serial Number:" | awk '{print $NF}')
                    smartctl -a -x /dev/"$hdd" >smart_before_"$sn".log
                    health=$(cat smart_before_"$sn"*.log | grep -i health | awk '{if ($NF == "PASSED") print "pass";else print "failed"}')
                    icrc=$(cat smart_before_"$sn"*.log | grep "ICRC" | awk '{print $3}')
                    read_error=$(cat smart_before_"$sn"*.log | grep "Raw_Read_Error_Rate" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    spin=$(cat smart_before_"$sn"*.log | grep "Spin_Up_Time" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    reall=$(cat smart_before_"$sn"*.log | grep "Reallocated_Sector_Ct" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    seek=$(cat smart_before_"$sn"*.log | grep "Seek_Error_Rate" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    spin_Retry_Count=$(cat smart_before_"$sn"*.log | grep "Spin_Retry_Count" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    tem=$(cat smart_before_"$sn"*.log | grep "Temperature_Celsius" | awk '{if($(NF-2) <= 60) print "pass";else print "failed"}')
                    offline=$(cat smart_before_"$sn"*.log | grep "Offline_Uncorrectable" | awk '{if($NF == 0) print "pass";else print "failed"}')
                    udma=$(cat smart_before_"$sn"*.log | grep "UDMA_CRC_Error_Count" | awk '{if($NF == 0) print "pass";else print "failed"}')
                    echo "$sn $hdd  $read_error $spin $reall $seek $spin_Retry_Count $tem $offline $udma $health   $icrc" >>before.log
               done
          }

          Port=$(wdckit s | grep -i "tb" | awk '{print $3}')
          if [ "$Port" = "SAS" ]; then
               Smartbefore_SAS
               echo -e "\nCollect SAS Smart_Info\n"
          else
               Smartbefore_SATA
               echo -e "\nCollect SATA Smart_Info\n"
          fi

     }

     SmartInfo_before_Swap
     sleep 5s
     echo -e "\n----------Finish SmartInfo_before Collect----------\n"

     #进行不带IO的热插拔测试，创建相关文件夹并在其中测试
     function Swap_NoneIO() {
          mkdir -p /"$Dir_Pre"/Hot_Swap/NoneIO
          cd /"$Dir_Pre"/Hot_Swap/NoneIO || exit

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

               cd /"$Dir_Pre"/Hot_Swap/NoneIO || exit
               umount /mnt
               echo -e "\n\numount the Device Please swap the $Test_Device\n"
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
               md5sum -c test.md5 >>/"$Dir_Pre"/Hot_Swap/NoneIO/process.log
               sleep 5s
               cd /"$Dir_Pre"/Hot_Swap/NoneIO || exit
               umount /mnt
               sleep 10s
          done
     }

     Swap_NoneIO

     function Swap_IO() {
          mkdir -p /"$Dir_Pre"/Hot_Swap/IO
          cd /"$Dir_Pre"/Hot_Swap/IO || exit

          echo -e "\nDo Swap_IO\n"
          sleep 5s

          #记录最初始的硬盘状态
          echo -e "[ $(date "+%F %T") ]\n\n" >>process.log
          lsblk | tee -a process.log

          #奇数号硬盘在Swap_NoneIO时已分区格式化完成，现在对其重新挂载及生成相关文件
          #开始进行热插拔操作，对每块盘挂载后生成文件以及MD5校验码

          for Test_Device in $(wdckit s | grep -i "/dev/sd" | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}' | awk 'NR%2 ==1'); do
               mount /dev/"$Test_Device"1 /mnt
               dd if=/dev/urandom of=/mnt/test bs=1M count=1000 | tee -a process.log
               sleep 5s

               cd /mnt || exit
               md5sum test >test.md5

               cd /"$Dir_Pre"/Hot_Swap/IO || exit
               umount /mnt
               echo -e "\n\numount the Device,Ready Start Fio\n"
               sleep 30s

               #对分区2以及其他待测盘进行IO，等待IO起来，拔测试盘
               mkdir -p /"$Dir_Pre"/Hot_Swap/IO/"$Test_Device"
               cd /"$Dir_Pre"/Hot_Swap/IO/"$Test_Device" || exit

               ls /sys/block/ | grep sd | grep -v "$bootdisk" | sed '/'$Test_Device'/d' >block

               while read line; do
                    echo "[${line}_randwrite_4k]" >>jobfile_rw
                    echo "filename=/dev/$line" >>jobfile_rw
               done <block

               fio jobfile_rw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=4 --iodepth=64 --rw=randwrite --bs=4k --log_avg_msec=1000 >4k_RW.log &

               fio --ioengine=libaio --norandommap --thread --direct=1 --name=test --ramp_time=60 --runtime=300 --time_based --numjobs=4 --iodepth=64 --filename=/dev/"$Test_Device" --rw=randwrite --bs=4k>4k_"$Test_Device".log  &
               
               sleep 60s
               iostat -x 5 >iosta_all.log &
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
               echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
               lsblk | tee -a process.log

               #判定是否所有的硬盘均在线，若硬盘在线，重新挂载，并检查md5校验码,否则重新进行测试
               Online_num=$(wdckit s | grep "/dev/sd" | grep -vw "$bootdisk" | wc -l)
               if [ "$Online_num" = "$System_num" ]; then
                    echo -e "\nThe Device was Identified\n"
                    mount /dev/"$Test_Device"1 /mnt
               else
                    echo -e "\nThe Device wasn't Identified,restart test\n"
                    exit 1
               fi

               #进入/mnt文件夹，对比md5校验码，并回到Swap_NoneIO文件夹，取消挂载，开始下一块硬盘
               cd /mnt || exit
               md5sum -c test.md5 >>/"$Dir_Pre"/Hot_Swap/IO/process.log
               sleep 5s
               cd /"$Dir_Pre"/Hot_Swap/IO || exit
               umount /mnt
               killall fio
               sleep 3s
               killall iostat
          done
     }

     Swap_IO

     ###-----------完成热插拔以后，收集Smart和系统log----------###
     function SmartInfo_after_Swap() {
          #判定是SATA盘还是SAS盘，收集不同的数据
          echo -e "\n----------Create folder to collect smart_before----------\n"

          function Smartafter_SAS() {
               mkdir smart_after
               echo -e "SN         SLOT Temp Read_error Write_error Elements Healthy DWORD1  \tDWORD2  " >after.log
               for sn in $(wdckit s | grep "SAS" | awk '{print $8}'); do
                    hdd=$(wdckit s | grep "$sn" | awk '{print $2}' | awk -F '/' '{print $NF}')
                    smartctl -a -x /dev/"$hdd" >smart_after_"$sn".log
                    tem=$(grep "Current Drive Temperature" smart_after_"$sn".log | awk '{if($(NF-1) <= 60) print "pass";else print "failed"}')
                    Readerror=$(grep "Error counter log:" -A 10 smart_after_"$sn".log | grep "read:" | awk '{if($NF <= 0) print "pass";else print "failed"}')
                    Writeerror=$(grep "Error counter log:" -A 10 smart_after_"$sn".log | grep "write:" | awk '{if($NF == 0) print "pass";else print "failed"}')
                    Elements=$(grep "Elements in grown defect list:" smart_after_"$sn".log | awk '{if ($NF == 0) print "pass";else print "failed"}')
                    Healthy=$(grep "SMART Health Status:" smart_after_"$sn".log | awk '{if ($NF == "OK") print "pass";else print "failed"}')
                    DWORD1=$(grep "Invalid DWORD count" smart_after_"${sn}".log | sed 2,2d | awk '{print $NF}')
                    DWORD2=$(grep "Invalid DWORD count" smart_after_"${sn}".log | sed 1,1d | awk '{print $NF}')
                    echo -e "$sn   $hdd  $tem $Readerror       $Writeerror        $Elements     $Healthy    $DWORD1  \t\t\t$DWORD2  " >>after.log
               done

               for sn in $(awk '{print $1}' before.log | sed 1d); do
                    slot_before=$(awk '$1=="'$sn'" {print $2}' before.log)
                    DWORD1_before=$(awk '$1=="'$sn'" {print $(NF-1)}' before.log)
                    DWORD2_before=$(awk '$1=="'$sn'"  {print  $NF}' before.log)
                    sn_after=$(awk '$1=="'$sn'" {print $1}' after.log)

                    if [ "$sn_after" == "$sn" ]; then
                         echo "**********$sn is exiting ,not lost,check pass***************" >>result.log

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
          }

          function Smartafter_SATA() {
               mkdir smart_after
               echo -e "SN       SLOT 1    3    5    7    10   194  198  199  health ICRC" >after.log

               for hdd in $(wdckit s | grep -i sd | grep -vw "$bootdisk" | awk '{print $2}' | awk -F "/" '{print $3}'); do
                    sn=$(smartctl -a -x /dev/"$hdd" | grep -i "Serial Number:" | awk '{print $NF}')
                    smartctl -a -x /dev/"$hdd" >smart_after_"$sn".log
                    health=$(grep -i "health" smart_after_"$sn".log | awk '{if ($NF == "PASSED") print "pass";else print "failed"}')
                    icrc=$(grep "ICRC" smart_after_"$sn".log | awk '{print $3}')
                    read_error=$(grep "Raw_Read_Error_Rate" smart_after_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
                    spin=$(grep "Spin_Up_Time" smart_after_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
                    reall=$(grep "Reallocated_Sector_Ct" smart_after_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
                    seek=$(grep "Seek_Error_Rate" smart_after_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
                    spin_Retry_Count=$(grep "Spin_Retry_Count" smart_after_"$sn".log | awk '{if($4 > $6) print "pass";else print "failed"}')
                    tem=$(grep "Temperature_Celsius" smart_after_"$sn".log | awk '{if($(NF-2) <= 60) print "pass";else print "failed"}')
                    offline=$(grep "Offline_Uncorrectable" smart_after_"$sn".log | awk '{if($NF == 0) print "pass";else print "failed"}')
                    udma=$(grep "UDMA_CRC_Error_Count" smart_after_"$sn".log | awk '{if($NF == 0) print "pass";else print "failed"}')

                    echo "$sn $hdd  $read_error $spin $reall $seek $spin_Retry_Count $tem $offline $udma $health   $icrc" >>after.log
               done

               echo -e "Smart_after collection completed,then compare with smart_before.\n "

               for sn in $(cat before.log | sed 1d | awk '{print $1}'); do
                    slot_before=$(cat before.log | awk '$1=="'$sn'" {print $2}')
                    icrc_before=$(cat before.log | awk '$1=="'$sn'" {print $NF}')
                    UDMA_before=$(cat before.log | awk '$1=="'$sn'"{print $10}')
                    sn_after=$(cat after.log | awk '$1=="'$sn'" {print $1}')

                    if [ "$sn_after" == "$sn" ]; then
                         echo "**********$sn is exiting ,not lost,check pass***************" >>result.log

                         slot_after=$(cat after.log | awk '$1=="'$sn'" {print $2}')
                         if [ "$slot_after" == $slot_before ]; then
                              echo " $sn slot ch098 eck pass.slot is $slot_after" >>result.log
                         else
                              echo " $sn slot check failed. slot is $slot_after" >>result.log
                         fi

                         # echo "check 1 3 5 7 10 194 198 199 health"
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

                         #echo "check ICRC"
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
          }

          Port=$(wdckit s | grep -i "tb" | awk '{print $3}')
          if [ "$Port" = "SAS" ]; then
               Smartafter_SAS
               echo -e "\nCollect SAS Smart_Info\n"
          else
               Smartafter_SATA
               echo -e "\nCollect SATA Smart_Info\n"
          fi

          echo -e "\n----------Finish SmartInfo_after Collect and Compare----------\n"

     }

     cd /"$Dir_Pre"/Hot_Swap || exit
     SmartInfo_after_Swap

     grep -i failed result.log >failed.log
     mkdir result
     mv before.log result
     mv after.log result
     mv failed.log result
     mv result.log result

     mv smart_before_*.log smart_before
     mv smart_after_*.log smart_after

     sleep 10s

     ###-----SmartInfo收集完成，收集系统信息-----###
     dmesg >dmesg.log
     sleep 5s
     cat /var/log/messages >messages.log
     sleep 5s
     ipmitool sel list >sel.log
     sleep 5s

}

function Hotplug_Raid() {

     function SmartInfo_before_Raid() {

          #判定是SATA盘还是SAS盘，收集不同的数据
          echo -e "\n----------Create folder to collect smart_before----------\n"

          function Smart_SAS() {
               mkdir smart_before
               echo -e "SN         SLOT Temp Read_error Write_error Elements Healthy DWORD1  \tDWORD2  " >before.log
               for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
                    dev=$(smartctl --scan | awk '{print $1}' | uniq)
                    sn=$(smartctl -a -d "$hdd" "$dev" | grep -i "Serial number:" | awk '{print $NF}')
                    rpm=$(smartctl -a -d "$hdd" "$dev" | grep "Rotation Rate:" | awk '{print $NF}')
                    if [ "$rpm" != "rpm" ]; then
                         echo " $sn is ssd"
                    else
                         smartctl -a -d "$hdd" "$dev" >smart_before_"$sn".log
                         tem=$(grep "Current Drive Temperature" smart_before_"sn".log | awk '{if($(NF-1) <= 60) print "pass";else print "failed"}')
                         Readerror=$(grep "Error counter log:" -A 10 smart_before_"$sn".log | grep "read:" | awk '{if($NF <= 0) print "pass";else print "failed"}')
                         Writeerror=$(grep "Error counter log:" -A 10 smart_before_"$sn".log | grep "write:" | awk '{if($NF == 0) print "pass";else print "failed"}')
                         Elements=$(grep "Elements in grown defect list:" smart_before_"$sn".log | awk '{if ($NF == 0) print "pass";else print "failed"}')
                         Healthy=$(grep "SMART Health Status:" smart_before_"$sn".log | awk '{if ($NF == "OK") print "pass";else print "failed"}')
                         DWORD1=$(grep "Invalid DWORD count" smart_before_"$sn".log | sed 2,2d | awk '{print $NF}')
                         DWORD2=$(grep "Invalid DWORD count" smart_before_"$sn".log | sed 1,1d | awk '{print $NF}')
                         echo -e "$sn   $hdd  $tem $Readerror       $Writeerror        $Elements     $Healthy    $DWORD1  \t\t\t$DWORD2  " >>before.log
                    fi
               done
          }

          function Smart_SATA() {
               mkdir smart_before
               echo "SN       SLOT 1    3    5    7    10   194  198  199  health ICRC" >before.log
               for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
                    dev=$(smartctl --scan | awk '{print $1}' | uniq)
                    sn=$(smartctl -a -d "$hdd" "$dev" | grep -i "Serial number:" | awk '{print $NF}')
                    rpm=$(smartctl -a -d "$hdd" "$dev" | grep "Rotation Rate:" | awk '{print $NF}')
                    if [ "$rpm" != "rpm" ]; then
                         echo " $sn is ssd"
                    else
                         smartctl -a -d "$hdd" "$dev" >before_"${hdd}"_"${sn}".log
                         mv before_"${hdd}"_"${sn}".log smart_before
                         health=$(cat smart_before/before_"${hdd}"*.log | grep -i health | awk '{if ($NF == "PASSED") print "pass";else print "failed"}')
                         icrc=$(cat smart_before/before_"${hdd}"*.log | grep "ICRC" | awk '{print $3}')
                         read_error=$(cat smart_before/before_"${hdd}"*.log | grep "Raw_Read_Error_Rate" | awk '{if($4 > $6) print "pass";else print "failed"}')
                         spin=$(cat smart_before/before_"${hdd}"*.log | grep "Spin_Up_Time" | awk '{if($4 > $6) print "pass";else print "failed"}')
                         reall=$(cat smart_before/before_"${hdd}"*.log | grep "Reallocated_Sector_Ct" | awk '{if($4 > $6) print "pass";else print "failed"}')
                         seek=$(cat smart_before/before_"${hdd}"*.log | grep "Seek_Error_Rate" | awk '{if($4 > $6) print "pass";else print "failed"}')
                         spin_Retry_Count=$(cat smart_before/before_"${hdd}"*.log | grep "Spin_Retry_Count" | awk '{if($4 > $6) print "pass";else print "failed"}')
                         tem=$(cat smart_before/before_"${hdd}"*.log | grep "Temperature_Celsius" | awk '{if($(NF-2) <= 60) print "pass";else print "failed"}')
                         offline=$(cat smart_before/before_"${hdd}"*.log | grep "Offline_Uncorrectable" | awk '{if($NF == 0) print "pass";else print "failed"}')
                         udma=$(cat smart_before/before_"${hdd}"*.log | grep "UDMA_CRC_Error_Count" | awk '{if($NF == 0) print "pass";else print "failed"}')
                         echo "$sn $hdd  $read_error $spin $reall $seek $spin_Retry_Count $tem $offline $udma $health   $icrc" >>before.log
                    fi
               done
          }

          Port=$(wdckit s | grep -i "tb" | awk '{print $3}')
          if [ "$Port" = "SAS" ]; then
               Smart_SAS
               echo -e "\nCollect SAS Smart_Info\n"
          else
               Smart_SATA
               echo -e "\nCollect SATA Smart_Info\n"
          fi

          echo -e "\n----------Finish SmartInfo_before Collect----------\n"

     }

     mkdir -p /"$Dir_Pre"/Raid
     cd /"$Dir_Pre"/Raid || exit
     SmartInfo_before_Raid

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

     #清除系统信息并收集Smart log
     dmesg -C
     sleep 5s
     echo >/var/log/messages
     sleep 5s
     ipmitool sel clear
     sleep 5s

     #创建raid1
     storcli64 /c0/eall/sall set good force
     sleep 10s
     Status=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | awk '{print $3}' | uniq)

     if [ "$Status" = "UGood" ]; then
          echo "UG Mode Success"
     else
          echo "check Devices Status"
          exit 0
     fi

     for ((EID_index = 1; EID_index < 10; EID_index++)); do
          EID_String=$(storcli /c0 show | grep -i "pd list" -A 15 | grep -i eid | awk '{print $'$EID_index' }')

          if [ "$EID_String" = "EID:Slt" ]; then
               EID=$(storcli /c0 show | grep -i "pd list" -A 15 | grep -i tb | awk '{print $'$EID_index'}' | awk -F ":" '{print $1}' | uniq)
               break
          else
               echo "EID not {$EID_index}th,find the next"
          fi
     done

     for Capacity in $(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | awk '{print $5}' | sort -n | uniq); do
          Slot_1=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep "$Capacity" | awk '{print $1}' | awk -F ":" '{print $2}' | sed -n '1p')
          Slot_2=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | grep "$Capacity" | awk '{print $1}' | awk -F ":" '{print $2}' | sed -n '2p')
          storcli64 /c0 add vd type=raid1 drive="$EID":"$Slot_1","$Slot_2"
          sleep 10s
     done

     #重复查询是否成功建立raid1

     Status=$(storcli64 /c0 show | grep -i "pd list" -A 20 | grep -i tb | awk '{print $3}' | uniq)
     if [ "$Status" = "Onln" ]; then
          echo -e "\nAll Device finish Raid1\n"
     else
          echo -e "\nRaid1 build fail"
          exit 0
     fi

     #开启fio任务，并且使用iosta去记录不同的性能

     OS_disk=$(df -h | grep boot | awk '{print $1}' | awk -F/ '{print $NF}' | sed -e 's/[0-9]*//g' | sort -u)
     ls /sys/block/ | grep sd | grep -v "$OS_disk" >block
     num=$(wc -l block)
     echo -e "\nTotal $num Device in the system\n"

     while read line; do
          echo "[${line}_seq_write_1M]" >>jobfile_sw
          echo "filename=/dev/$line" >>jobfile_sw

          echo "[${line}_seq_read_1M]" >>jobfile_sr
          echo "filename=/dev/${line}" >>jobfile_sr

          echo "[${line}_randwrite_4k]" >>jobfile_rw
          echo "filename=/dev/${line}" >>jobfile_rw

          echo "[${line}_randread_4k]" >>jobfile_rr
          echo "filename=/dev/${line}" >>jobfile_rr
     done <block

     Cur_Dir=$(pwd)

     echo -e "\n----------Do Sequential Write----------\n"
     mkdir -p /"$Cur_Dir"/1M_SW
     cd 1M_SW || exit
     cp "$Cur_Dir"/jobfile_sw /"$Cur_Dir"/1M_SW
     fio jobfile_sw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=write --bs=1M --output=1M_seqW.log --log_avg_msec=1000 --write_iops_log=1M_seqW_iops.log --write_lat_log=1M_seqW_lat.log &
     sleep 450s
     cd ..

     echo -e "\n----------Do Sequential Read----------\n"
     mkdir -p /"$Cur_Dir"/1M_SR
     cd 1M_SR || exit
     cp "$Cur_Dir"/jobfile_sr /"$Cur_Dir"/1M_SR
     fio jobfile_sr --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=read --bs=1M --output=1M_seqR.log --log_avg_msec=1000 --write_iops_log=1M_seqR_iops.log --write_lat_log=1M_seqR_lat.log &
     sleep 450s
     cd ..

     echo -e "\n----------Do Random Write----------\n"
     mkdir -p /"$Cur_Dir"/4K_RW
     cd 4K_RW || exit
     cp "$Cur_Dir"/jobfile_rw /"$Cur_Dir"/4K_RW
     fio jobfile_rw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=64 --rw=randwrite --bs=4k --output=4K_randW.log --log_avg_msec=1000 --write_iops_log=4K_randW_iops.log --write_lat_log=4K_randW_lat.log &
     sleep 450s
     cd ..

     echo -e "\n----------Do Random Read----------\n"
     mkdir -p /"$Cur_Dir"/4K_RR
     cd 4K_RR || exit
     cp "$Cur_Dir"/jobfile_rr /"$Cur_Dir"/4K_RR
     fio jobfile_rr --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=64 --rw=randwrite --bs=4k --output=4K_randW.log --log_avg_msec=1000 --write_iops_log=4K_randW_iops.log --write_lat_log=4K_randW_lat.log &
     sleep 450s
     cd ..

     mkdir -p First_FIO
     mv 1M_SW/ First_FIO/
     mv 1M_SR/ First_FIO/
     mv 4K_RW/ First_FIO/
     mv 4K_RR/ First_FIO/

     echo -e "\nThe FIO performance data collection is complete. The Devices are ready to be inserted or removed\n"
     sleep 30s

     #重新建立一个文件夹，并运行任一fio，性能稳定后将盘拔出
     echo -e "\n----------Do Fio keep performance----------\n"
     mkdir -p /"$Cur_Dir"/Second_FIO
     cd Second_FIO || exit
     cp "$Cur_Dir"/jobfile_sr /"$Cur_Dir"/Second_FIO
     fio jobfile_sr --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=read --bs=1M >>Second_FIO.log &
     sleep 220s
     cd ..

     #提示插拔盘并识别,将硬盘拔出和插入过程记录

     #记录未拔出硬盘时间/硬盘数量
     date | tee -a process.log
     wdckit s | tee -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log
     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log

     echo -e "\nCollect All Devices data,ready to swap Devices\n"
     echo -e "\n----------swap the disk----------\n"

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
     sleep 30s

     read -r -p "Have all the drives been Inserted? [Y/n] " input

     case $input in
     [yY][eE][sS] | [yY])
          echo -e "all the drives been Inserted,wait to collect data\n"
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

     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
     wdckit s | tee -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log
     sleep 15s
     echo -e "\nCheck whether the devices is being rebuilt\n"

     #判定此时系统是否识别硬盘及正在rebuild
     #当硬盘状态为rebuild且raid状态为dgrd时为正确状态

     Virtual_Status=$(storcli64 /c0/vall show | grep -i "rwtd" | awk '{print $3}' | sort -u)
     Device_StatusNums=$(storcli64 /c0 show | grep -i "pd list" -A 15 | grep -i "rbld" | wc -l)
     System_Raidnum=$(("$System_num" / 2))

     if [ "$Virtual_Status" = "Dgrd" ] && [ "$Device_StatusNums" = "$System_Raidnum" ]; then
          echo "Devices are doing rebuilding"
     else
          echo "Devices are Status false,test ending"
          exit 0
     fi

     #记录此时硬盘正在rebuild

     echo -e "\n[ $(date "+%F %T") ]\n" >>process.log
     wdckit s | tee -a process.log
     storcli64 /c0 show | grep -i "vd list" -A 40 | tee -a process.log

     sleep 15s

     echo -e "\n\nTest finish\n"

     while [ "$Virtual_Status" = "Dgrd" ]; do
          sleep 1800s
          Virtual_Status=$(storcli64 /c0/vall show | grep -i "rwtd" | awk '{print $3}' | sort -u)
     done

     sleep 300s
     echo -e "\nFinish Rebuild,Collect Log\n"

     function SmartInfo_after_Raid() {

          #根据在SmartInfo_before时查询的Port来判定是SATA/SAS盘收集信息

          echo -e "\n----------Create folder to collect smart_after and Compare----------\n"

          function Smartafter_SATA() {

               mkdir smart_after
               echo -e "SN       SLOT 1    3    5    7    10   194  198  199  health ICRC" >after.log
               dev=$(smartctl --scan | grep -i "/dev/bus" | awk '{print $1}' | uniq)
               for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
                    sn=$(smartctl -a -d "$hdd" "$dev" | grep -i "Serial number:" | awk '{print $NF}')
                    smartctl -a -x -d "$hdd" "$dev" >smart_after_"$sn".log
                    health=$(cat smart_after_"$sn"*.log | grep -i health | awk '{if ($NF == "PASSED") print "pass";else print "failed"}')
                    icrc=$(cat smart_after_"$sn"*.log | grep "ICRC" | awk '{print $3}')
                    read_error=$(cat smart_after_"$sn"*.log | grep "Raw_Read_Error_Rate" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    spin=$(cat smart_after_"$sn"*.log | grep "Spin_Up_Time" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    reall=$(cat smart_after_"$sn"*.log | grep "Reallocated_Sector_Ct" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    seek=$(cat smart_after_"$sn"*.log | grep "Seek_Error_Rate" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    spin_Retry_Count=$(cat smart_after_"$sn"*.log | grep "Spin_Retry_Count" | awk '{if($4 > $6) print "pass";else print "failed"}')
                    tem=$(cat smart_after_"$sn"*.log | grep "Temperature_Celsius" | awk '{if($(NF-2) <= 60) print "pass";else print "failed"}')
                    offline=$(cat smart_after_"$sn"*.log | grep "Offline_Uncorrectable" | awk '{if($NF == 0) print "pass";else print "failed"}')
                    udma=$(cat smart_after_"$sn"*.log | grep "UDMA_CRC_Error_Count" | awk '{if($NF == 0) print "pass";else print "failed"}')

                    echo "$sn $hdd  $read_error $spin $reall $seek $spin_Retry_Count $tem $offline $udma $health   $icrc" >>after.log
               done

               echo -e "Smart_after collection completed,then compare with smart_before.\n"

               for sn in $(cat before.log | sed 1d | awk '{print $1}'); do
                    slot_before=$(awk '$1=="'$sn'" {print $2}' before.log)
                    icrc_before=$(awk '$1=="'$sn'" {print $NF}' before.log)
                    UDMA_before=$(awk '$1=="'$sn'"{print $10}' before.log)
                    sn_after=$(awk '$1=="'$sn'" {print $1}' after.log)

                    if [ "$sn_after" == "$sn" ]; then
                         echo "----------$sn is exiting ,not lost,check pass----------" >>result.log

                         slot_after=$(cat after.log | awk '$1=="'$sn'" {print $2}')
                         if [ "$slot_after" == $slot_before ]; then
                              echo " $sn slot ch098 eck pass.slot is $slot_after" >>result.log
                         else
                              echo " $sn slot check failed. slot is $slot_after" >>result.log
                         fi

                         # echo "check 1 3 5 7 10 194 198 199 health"
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

          }

          function Smartafter_SAS() {
               mkdir smart_after
               dev=$(smartctl --scan | grep -i "/dev/bus" | awk '{print $1}' | uniq)
               echo -e "SN         SLOT Temp Read_error Write_error Elements Healthy DWORD1  \tDWORD2  " >before.log
               for hdd in $(smartctl --scan | grep -i megaraid | awk '{print $3}' | awk -F "/" '{print $NF}'); do
                    sn=$(smartctl -a -d "$hdd" "$dev" | grep -i "Serial number:" | awk '{print $NF}')
                    rpm=$(smartctl -a -d "$hdd" "$dev" | grep "Rotation Rate:" | awk '{print $NF}')
                    if [ "$rpm" != "rpm" ]; then
                         echo " $sn is ssd"
                    else
                         smartctl -a -x -d "$hdd" "$dev" >smart_after_"$sn".log
                         tem=$(grep "Current Drive Temperature" smart_after_"$sn".log | awk '{if($(NF-1) <= 60) print "pass";else print "failed"}')
                         Readerror=$(grep "Error counter log:" -A 10 smart_after_"$sn".log | grep "read:" | awk '{if($NF <= 0) print "pass";else print "failed"}')
                         Writeerror=$(grep "Error counter log:" -A 10 smart_after_"$sn".log | grep "write:" | awk '{if($NF == 0) print "pass";else print "failed"}')
                         Elements=$(grep "Elements in grown defect list:" smart_after_"$sn".log | awk '{if ($NF == 0) print "pass";else print "failed"}')
                         Healthy=$(grep "SMART Health Status:" smart_after_"$sn".log | awk '{if ($NF == "OK") print "pass";else print "failed"}')
                         DWORD1=$(grep "Invalid DWORD count" smart_after_"$sn".log | sed 2,2d | awk '{print $NF}')
                         DWORD2=$(grep "Invalid DWORD count" smart_after_"$sn".log | sed 1,1d | awk '{print $NF}')
                         echo -e "$sn   $hdd  $tem $Readerror       $Writeerror        $Elements     $Healthy    $DWORD1  \t\t\t$DWORD2  " >>after.log
                    fi
               done

               for sn in $(awk '{print $1}' before.log | sed 1d); do
                    slot_before=$(awk '$1=="'$sn'" {print $2}' before.log)
                    DWORD1_before=$(awk '$1=="'$sn'" {print $(NF-1)}' before.log)
                    DWORD2_before=$(awk '$1=="'$sn'"  {print  $NF}' before.log)
                    sn_after=$(awk '$1=="'$sn'" {print $1}' after.log)

                    if [ "$sn_after" == "$sn" ]; then
                         echo "**********$sn is exiting ,not lost,check pass***************" >>result.log

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
          }

          if [ "$Port" = "SAS" ]; then
               Smartafter_SAS
               echo -e "\nCollect SAS Smart_Info\n"
          else
               Smartafter_SATA
               echo -e "\nCollect SATA Smart_Info\n"
          fi

          echo -e "\n----------Finish SmartInfo_after Collect and Compare----------\n"
     }

     cd /"$Dir_Pre"/Raid || exit
     SmartInfo_after_Raid

     mv smart_before_*.log smart_before
     mv smart_after_*.log smart_after
     grep -i failed result.log >failed.log
     mkdir result
     mv before.log result
     mv after.log result
     mv failed.log result
     mv result.log result

     ###-----SmartInfo收集完成，收集系统信息-----###
     dmesg >dmesg.log
     sleep 5s
     cat /var/log/messages >messages.log
     sleep 5s
     ipmitool sel list >sel.log
     sleep 5s

     echo -e "\n\nFinish Test\n\n"
}

Hot_Swap

Hotplug_Raid