#!/usr/bin/env bash

for Slot in $(wdckit s |grep Good |awk '{print $2}' |sed 1d);do
    wdckit l "$Slot" -s ./
    sleep 15s
done