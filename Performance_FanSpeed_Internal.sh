#!/usr/bin/env bash
function Run_Cycle () {
    Cycle=$1
    for((i=0;i<"$Cycle";i++)); do
        FIO_Data
    done
    
}

function FIO_Data () {
PWD=$(pwd)
PWD_System=$(pwd)
OS_disk=$(wdckit s |grep -i "bootdevice" -A 20 |grep -i "yes" |awk '{print $2}' |awk -F "/" '{print $3}')
echo -e "OS_disk is $OS_disk\n"

mkdir -p "$PWD_System"/Smr_binfile/Before
for HDD_Slot in $(wdckit s |grep -i "dev/sd" |grep -i "no" |awk '{print $2}' |awk -F "/" '{print $3}');do
wdckit getsmr /dev/"$HDD_Slot" -s "$PWD_System"/Smr_binfile/Before
sleep 20s
done
echo -e "\ncollect Smr binfile_before finish. \n"

mkdir -p "$PWD"/Test_case

for speed in 30 80 90 100 
do

echo -e  "\nIt's $speed% now\n" 
ipmitool raw 0x3a 0x0d 0xff "$speed"
sleep 60s 
ipmitool sdr | grep -i "speed" | tee -a Fan_Speed

    for HDD_Slot in $(wdckit s |grep -i "dev/sd" |grep -i "no" |awk '{print $2}' |awk -F "/" '{print $3}');do
        mkdir -p "$PWD"/Test_case/"$HDD_Slot"
    
   
        fio --name=rand_write_4k --numjobs=1 --norandommap --rw=randwrite --direct=1 --ioengine=libaio --runtime=300 --filename=/dev/"$HDD_Slot" --bs=4k --iodepth=32 --group_reporting --time_based=1 --log_avg_msec=1000 --bwavgtime=1000 |tee -a "$PWD"/Test_case/"$HDD_Slot"/fio_4k_randwrite_${speed}%_result.txt &
        echo -e "\n----------------do $HDD_Slot fio_4k_randwrite ------------\n"
        
    done

    sleep 400s
    
    for HDD_Slot in $(wdckit s |grep -i "dev/sd" |grep -i "no" |awk '{print $2}' |awk -F "/" '{print $3}');do
        mkdir -p "$PWD"/Test_case/"$HDD_Slot"
        fio --name=seq_write_128k --numjobs=1 --norandommap --rw=write --direct=1 --ioengine=libaio --runtime=300 --filename=/dev/"$HDD_Slot" --bs=128k --iodepth=32 --group_reporting --time_based=1 --log_avg_msec=1000 --bwavgtime=1000 --write_bw_log="$speed" |tee -a "$PWD"/Test_case/"$HDD_Slot"/fio_128k_seqwrite_"$speed"%_result.txt &
        echo -e "\n----------------do $HDD_Slot fio_128k_seqwrite -------------\n" 

    done
    sleep 400s

done
echo -e  "\n\n FIO_Performance Finish,Collect bin_file and do data Compare \n\n"

ipmitool raw 0x3a 0x0d 0xff 30
sleep 120s

mkdir -p "$PWD_System"/Smr_binfile/After
for HDD_Slot in $(wdckit s |grep -i "dev/sd" |grep -i "no" |awk '{print $2}' |awk -F "/" '{print $3}');do
wdckit getsmr /dev/"$HDD_Slot" -s "$PWD_System"/Smr_binfile/After
sleep 20s
done
echo -e "\n collect Smr binfile_After finish. \n"

Data_Compare
}


function Data_Compare () {
for file in "$PWD_System"/Test_case/*;do
    if test -f "$file"
    then
        echo "$file is file"
    fi
    if test -d "$file"
    then
        echo "$file is dir"
        cd "$file" || exit
        slot=$(pwd |awk -F "/" '{print $NF}')
        echo -e "slot\tSN\t\t\t\t\tfio\t          data" >> result.log           
        for speed in 30  80  90 100
        do
         SN=$(wdckit s |grep -i "$slot" |awk '{print $8}')
         RW_4k_Data=$(cat fio_4k_randwrite_"$speed"* |grep -i "write:" |grep "IOPS" |awk '{print $2}'|awk -F "," '{print $1}')
         SW_128k_Data=$(cat fio_128k_seqwrite_"$speed"* |grep -i "write:" |grep "BW" |awk '{print $3,$4}'|awk '{print $1}')
         echo -e "$slot\t\t$SN\t\tRW_4k_$speed%\t\t  $RW_4k_Data" >>result.log
         echo -e "$slot\t\t$SN\t\tSW_128k_$speed%\t\t$SW_128k_Data" >>result.log
        done
    fi
done
#ls |grep fio |awk -F "_" '{print $3,$4}'

cd "$PWD_System"/Test_case ||exit
echo -e "slot\tSN\t\t\t\t\tfio\t          data" >> result_sum.log
for speed in 30 80 90 100;do
    for file in "$PWD_System"/Test_case/*;do
        if test -f "$file"
        then
            echo "$file is file"
        fi
        if test -d "$file"
        then
            cd "$file" ||exit
            sw=$(cat result.log | grep -i "sw" |grep -i "$speed" |sed 's/BW=//' |sed -r 's/.{5}$//')
            cd "$PWD_System"/Test_case ||exit
            echo "$sw" >> result_sum.log 
            cd "$PWD_System" ||exit
        fi
    done
done 

cd "$PWD_System"/Test_case ||exit
for speed in 30 80 90 100;do
    for file in "$PWD_System"/Test_case/*;do
        if test -f "$file"
        then
            echo " "
        fi
        if test -d "$file"
        then
            cd "$file" ||exit
            rw=$(cat result.log |cat result.log |grep -i "rw" |grep -i "$speed" |sed 's/IOPS=//')
            cd "$PWD_System"/Test_case ||exit
            echo "$rw" >> result_sum.log 
            cd "$PWD_System" ||exit
        fi
    done
done 

}

Run_Cycle  "$@"
# cd "$PWD_System"/Test_case ||exit
# echo -e "slot\tSN\t\t\t\t\tfio\t          data" >> result_sum.log
# for file in "$PWD_System"/Test_case/*;do
# if test -f "$file"
#     then
#         echo "$file is file"
#     fi
#     if test -d "$file"
#     then
#     cd "$file" ||exit
#     rw=$(cat result.log |grep -i "rw")
#     cd "$PWD_System"/Test_case ||exit
#     echo "$rw" >> result_sum.log 
#     cd "$PWD_System" ||exit
#     fi
# done

# cd "$PWD_System"/Test_case ||exit
# for file in "$PWD_System"/Test_case/*;do
# if test -f "$file"
#     then
#         echo "$file is file"
#     fi
#     if test -d "$file"
#     then
#     cd "$file" ||exit
#     sw=$(cat result.log |grep -i "sw")
#     cd "$PWD_System"/Test_case ||exit
#     echo "$sw" >> result_sum.log 
#     cd "$PWD_System" ||exit
#     fi
# done