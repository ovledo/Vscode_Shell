#!/bin/bash

time=600  ###30mins for each fan speed%
Cur_Dir=$(cd "$(dirname "$0")";pwd)
Testlog=$Cur_Dir/Bytedance_FanSpeed_perf_test

echo "Clear dmesg and message log before test" | tee -a $Testlog
echo " ">/var/log/messages
dmesg -C 

mkdir FanSpeedTest
mkdir -p ./FanSpeedTest/test_data
mkdir -p ./FanSpeedTest/test_log
mkdir -p ./FanSpeedTest/smart/before
mkdir -p ./FanSpeedTest/smart/after

wdckit s >>sysinfo
storcli /c0/eall/sall show >>sysinfo
OS=`df -h |grep boot |awk '{print $1}'|awk -F/ '{print $NF}'|sed -e 's/[0-9]*//g' |sort -u`
echo OS dev $OS |tee -a $Testlog
ls /sys/block/ |grep sd |grep -v $OS >block
num=`wc -l block`
echo "Total $num Device in the system" |tee -a $Testlog
echo "Generate Jobfile for multi workload" |tee -a $Testlog

while read line
do
echo "[${line}_seq_write_128k]">>jobfile_sw
echo "filename=/dev/"${line}>>jobfile_sw

echo "[${line}_seq_read_128k]">>jobfile_sr
echo "filename=/dev/"${line}>>jobfile_sr

echo "[${line}_randwrite_4k]">>jobfile_rw
echo "filename=/dev/"${line}>>jobfile_rw

echo "[${line}_randread_4k]">>jobfile_rr
echo "filename=/dev/"${line}>>jobfile_rr

echo "[${line}_randomRW_MixRead70]">>jobfile_mix
echo "filename=/dev/"${line}>>jobfile_mix

smartctl -a /dev/${line} >./FanSpeedTest/smart/before/"${line}"_smart.log
done<block

echo "设置风扇转速为手动" |tee -a $Testlog

#设置风扇转速30%，40%，50%，70%，80%，100%
#for RPM in 0x1e 0x28
for RPM in 20 30 80 90 100  
do
  echo "设置系统风扇转速至$RPM" | tee -a $Testlog
  ipmitool raw 0x3a 0x0d 0xff $RPM
  #ipmitool raw 0x3c 0x2d 0xff $RPM
  echo "wait 120s for FanSpeed steady" |tee -a $Testlog
  sleep 120
  ipmitool sdr |grep -i speed |tee -a $Testlog

	echo "[ $(date "+%F %T") ] ------------------------Sequential Write with FanSpeed $RPM ------------------------" |tee -a $Testlog
	iostat -xm /dev/sd*  1  >> Sequential_write_iostat_"$RPM".log &
 	for loop in `seq 1 5`
	do

	fio jobfile_sw --ioengine=libaio --bs=128k --runtime=$time --rw=write --size=100% --direct=1 --numjob=1 --iodepth=32 --time_based=1 --minimal >>dev_seq_write_data_"$RPM".log 
	sleep 3
	done
	fuser -k Sequential_write_iostat_"$RPM".log
	python3 ResultParseTerse3.py -t p -i bw -f dev_seq_write_data_"$RPM".log -r seq_write_data_"$RPM".csv
	sleep 10

mv *.csv ./FanSpeedTest/test_data/
mv *.log ./FanSpeedTest/test_log/
done
while read line
do
smartctl -a /dev/${line} >./FanSpeedTest/smart/after/"${line}"_smart.log
done<block

ipmitool raw 0x3a 0x0d 0xff 20

ipmitool sdr |grep -i speed |tee -a $Testlog


echo "[ $(date "+%F %T") ]---Test complete " |tee -a $Testlog
dmesg >./FanSpeedTest/dmesg.log
cp /var/log/messages ./FanSpeedTest
mv nohup.out  jobfile_*  block $Testlog ./FanSpeedTest

