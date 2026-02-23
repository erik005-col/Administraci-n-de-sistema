#!/bin/bash

echo -e "\n[+] Nombre del Host:"
hostname

echo " Direcion IPv4: $(hostname -I | awk '{print $2}') "

echo -e "\n [+] Espacio en Disco (raiz):"
df -h / | awk 'NR==2 {print "Total:" $2 ", usado: " $3 ", Disponible: " $4}'