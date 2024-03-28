#!/usr/bin/env bash

#定义风扇转速数组，对其取值修改转速
Fan_SpeedRun=(30 50 80 90 100 30)
Fan_Speed=(30 50 80 90 100)

PWD_System=$(pwd)

sh SmartInfo.sh
sleep 5s

mkdir -p "$PWD_System"/Smr_binfile/Before
for HDD_Slot in $(wdckit s | grep -i "dev/sd" | grep -i "no" | awk '{print $2}' | awk -F "/" '{print $3}'); do
    wdckit getsmr /dev/"$HDD_Slot" -s "$PWD_System"/Smr_binfile/Before
    sleep 20s
done
echo -e "\ncollect Smr binfile_before finish. \n"

function FIO_Data() {
    OS_disk=$(wdckit s | grep -i "bootdevice" -A 20 | grep -i "yes" | awk '{print $2}' | awk -F "/" '{print $3}')
    echo -e "OS_disk is $OS_disk\n"
    PWD_Test=$(pwd)

    mkdir -p "$PWD_Test"/Test_case
    cd "$PWD_Test"/Test_case || exit

    ls /sys/block/ | grep sd | grep -v "$OS_disk" >block

    num=$(wc -l block)
    echo -e "\nTotal $num Device in the system\n"

    while read line; do
        echo "[${line}_seq_write_128k]" >>jobfile_sw
        echo "filename=/dev/$line" >>jobfile_sw

        echo "[${line}_seq_read_128k]" >>jobfile_sr
        echo "filename=/dev/${line}" >>jobfile_sr

        echo "[${line}_randwrite_4k]" >>jobfile_rw
        echo "filename=/dev/${line}" >>jobfile_rw

        echo "[${line}_randread_4k]" >>jobfile_rr
        echo "filename=/dev/${line}" >>jobfile_rr
    done <block

    for speed in "${Fan_SpeedRun[@]}"; do
        echo -e "\n\n[ $(date "+%F %T") ]" >>Fan_Speed.log
        echo -e "\nIt's $speed% now\n" | tee -a Fan_Speed.log
        ipmitool raw 0x3a 0x0d 0xff "$speed"
        sleep 60s
        ipmitool sdr | grep -i "speed" | tee -a Fan_Speed.log

        echo -e "\n----------Do Sequential Write----------\n"

        fio jobfile_sw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=32 --rw=write --bs=1M --log_avg_msec=1000 --write_iops_log=1M_seqW_iops.log --new_group | tee -a "$PWD_Test"/Test_case/fio_128k_seqwrite_"$speed"%_result.txt &
        wait

        echo -e "\n----------Do Random Write----------\n"

        fio jobfile_rw --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --ramp_time=60 --runtime=300 --time_based --numjobs=1 --iodepth=64 --rw=randwrite --bs=4k --log_avg_msec=1000 --write_iops_log=4K_randW_iops.log --new_group | tee -a "$PWD_Test"/Test_case/fio_4k_randwrite_${speed}%_result.txt &
        wait

    done
    echo -e "\n\n FIO_Performance Finish,Collect bin_file and do data Compare \n\n"

}

function Data_Compare() {

    #整理每块硬盘的数据
    for speed in "${Fan_Speed[@]}"; do
        for slot in $(wdckit s | grep -i "dev/sd" | grep -i "no" | awk '{print $2}' | awk -F "/" '{print $3}'); do
            SN=$(wdckit s | grep -i "$slot" | awk '{print $8}')
            RW_4k_Data=$(cat fio_4k_randwrite_"$speed"* | grep "$slot" -A 2 | grep -i "write:" | grep "IOPS" | awk '{print $2}' | awk -F "," '{print $1}' | awk '{if(NR==1) {line=$0} else {line=line","$0} } END{print line}')
            SW_128k_Data=$(cat fio_128k_seqwrite_"$speed"* | grep "$slot" -A 2 | grep -i "write:" | grep "BW" | awk '{print $3,$4}' | awk '{print $1}' | awk '{if(NR==1) {line=$0} else {line=line","$0} } END{print line}')
            echo -e "$slot\t$SN\tRW_4k_$speed%\t$RW_4k_Data" | column -t >>"$slot"_result.log
            echo -e "$slot\t$SN\tSW_128k_$speed%\t$SW_128k_Data" | column -t >>"$slot"_result.log
            column -t "$slot"_result.log >"$slot"_result_sort.log
        done
    done

    result_arr=()
    n=2
    result_arr[0]=Slot
    result_arr[1]=SN
    for sw_speed in "${Fan_SpeedRun[@]}"; do
        sw_result=SW_128K_"$sw_speed"%
        result_arr["$n"]="$sw_result"
        n=$(("$n" + 1))
    done

    for rw_speed in "${Fan_SpeedRun[@]}"; do
        rw_result=RW_4k_"$rw_speed"%
        result_arr["$n"]="$rw_result"
        n=$(("$n" + 1))
    done

    echo "${result_arr[*]}" >>result_sum.log

    for slot in $(wdckit s | grep -i "dev/sd" | grep -i "no" | awk '{print $2}' | awk -F "/" '{print $3}'); do
        arr=()
        arr[0]="$slot"
        SN=$(wdckit s | grep -i "$slot" | awk '{print $8}')
        arr[1]="$SN"
        i=2
        for speed in "${Fan_Speed[@]}"; do
            sw=$(cat "$slot"_result_sort.log | grep -i "sw" | grep -i "$speed"% | sed 's/BW=//g' | sed 's/MiB\/s//g' | awk '{print $NF}')
            arr["$i"]="$sw"

            sw_check=$(echo "$sw" | sed 's/,//')
            if [ "$sw_check" != "$sw" ]; then
                sw_new1=$(echo "$sw" | awk -F "," '{print $1}')
                sw_new2=$(echo "$sw" | awk -F "," '{print $2}')
                arr["$i"]="$sw_new1"
                j=$(("$i" + 5))
                arr["$j"]="$sw_new2"
            fi

            if [ "$(($i + 1))" = "$j" ]; then
                i=$(("$i" + 2))
            else
                i=$(("$i" + 1))
            fi
        done

        for speed in "${Fan_Speed[@]}"; do
            rw=$(cat "$slot"_result_sort.log | grep -i "rw" | grep -i "$speed"% | sed 's/IOPS=//g' | awk '{print $NF}')
            arr["$i"]="$rw"

            rw_check=$(echo "$rw" | sed 's/,//')
            if [ "$rw_check" != "$rw" ]; then
                rw_new1=$(echo "$rw" | awk -F "," '{print $1}')
                rw_new2=$(echo "$rw" | awk -F "," '{print $2}')
                arr["$i"]="$rw_new1"
                j=$(("$i" + 5))
                arr["$j"]="$rw_new2"
            fi
            i=$(("$i" + 1))

        done

        echo "${arr[*]}" >>result_sum.log

        cat result_sum.log |column -t > restlt_sort.log
    done
}

function Run_Cycle() {
    Cycle=$1
    for ((i = 1; i <= "$Cycle"; i++)); do
        mkdir -p /"$PWD_System"/Test_"$i"Cycle
        cd /"$PWD_System"/Test_"$i"Cycle || exit
        FIO_Data
        wait
        Data_Compare
        wait
    done

}

Run_Cycle "$@"

ipmitool raw 0x3a 0x0d 0xff 30
sleep 120s

mkdir -p "$PWD_System"/Smr_binfile/After
for HDD_Slot in $(wdckit s | grep -i "dev/sd" | grep -i "no" | awk '{print $2}' | awk -F "/" '{print $3}'); do
    wdckit getsmr /dev/"$HDD_Slot" -s "$PWD_System"/Smr_binfile/After
    sleep 20s
done
echo -e "\n collect Smr binfile_After finish. \n"

cd "$PWD_System" || exit
sh SmartInfo.sh
