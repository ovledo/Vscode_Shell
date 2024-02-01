#!/usr/bin/env bash

for((Inte_index=1;Inte_index<10;Inte_index++)); do
     Inte_index_String=$(storcli64 /c0/eall/s"$Inte_index" show all |grep Intf -A 2 |grep -v "^-*$"|awk '{print $'$Inte_index' }')

     if [ "$Inte_index_String" = "Intf" ]; then
          echo -e "\nDevice is $Inte_index_String\n"
          break
     else
          echo "do next "
     fi
done