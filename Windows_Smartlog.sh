#!/usr/bin/env bash

for((i=1;i<="$1";i++)); do
    Slot=$(echo {a..z} |awk '{print $'$i'}')
    echo "$Slot"

    smartctl -a -x /dev/sd"$Slot" > sd"$Slot".log
done


