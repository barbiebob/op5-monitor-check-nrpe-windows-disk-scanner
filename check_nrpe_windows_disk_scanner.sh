#!/bin/bash
#################################################################################################################################
#
# Description: Queries a Windows host for drive letters by NRPE and adds a service-check for each drive letter in OP5 Monitor.
#
# Runtime errors are logged in: /var/tmp/windows-disk-scanner.log
#
# Author: Robert Claesson, OP5 AB, 2017, <rclaesson@op5.com>
#
#################################################################################################################################

# Binaries
curl=$(which curl)
nrpe="/opt/plugins/check_nrpe"

# Source naemon utilities
source /opt/plugins/utils.sh

help="$0 \n
Usage: $0 -H op5-server -u api-user -p api-password\n
Options:
-H Hostname/IP of OP5 server
-u API username
-p API password
-g Windows hostgroup name"

# Check for people who need help
if [ "${1}" = "--h" -o "${#}" = "0" ] || [ "${1}" = "--help" -o "${#}" = "0" ] || [ "${1}" = "-h" -o "${#}" = "0" ];
        then
        echo -e "${help}";
        exit $STATE_UNKNOWN
fi

# Setup variables
while getopts "H:u:p:g:" input; do
        case ${input} in
        H)      op5_host=${OPTARG};;
        u)      username=${OPTARG};;
		p)		password=${OPTARG};;
		g)		windows_hostgroup=${OPTARG};;
        *)      $help ; exit $STATE_UNKNOWN;;
        \?)     $help ; exit $STATE_UNKNOWN;;
        esac
done

# Get all hosts from Windows hostgroup
printf "\nFetching hosts from Windows host groups...\n"
hosts=$(curl -s -g -k -X GET -u "$username:$password" "https://$op5_host/api/filter/query?query=[hosts]%20groups%20%3E=%20%22$windows_hostgroup%22&columns=name")
if [ $? -ne "0" ]
then
    echo -e $(date) >> /var/tmp/windows-disk-scanner.log ; printf "Could not contact OP5 API.\nExiting.\n\n" >> /var/tmp/windows-disk-scanner.log
    exit 1
fi
printf "[DONE]\n\n"

# Trim JSON output to only values (host names)
hosts=$(sed -e 's/[}"]*\(.\)[{"]*/\1/g;y/,/\n/' <<< $hosts | cut -d":" -f2 | sed 's/]//g')

# Query hosts for drive letters (using NRPE)
printf "Searching for drive letters on hosts and adding those to OP5 Monitor...\n"
for host in $hosts
do
    drive_letters=$("$nrpe" -u -t 3 -s -H "$host" -c check_drivesize)
    if [ $? -eq "3" ]
    then
        echo -e $(date) >> /var/tmp/windows-disk-scanner.log ; printf "Host $host could not be reachable over NRPE\n\n" >> /var/tmp/windows-disk-scanner.log
        break
    fi

    # Trim down to only drive letters
    drive_letters=$(echo $drive_letters | cut -d"|" -f2 | sed 's/[0-9]*//g' | sed -E -e 's/[[:blank:]]+/\n/g' | grep "^'" | cut -d"'" -f2 | cut -d":" -f1 | sort | uniq)

    # Add a service-check for each drive in OP5 Monitor
    for drive_letter in $drive_letters
    do
        $curl \
            -s -k -H \
                    'content-type: application/json' \
            -u \
                    "$username:$password" \
            -d \
                    "{"\"file_id"\": "\"etc/serivces.cfg"\", \
                    "\"host_name"\": "\"$host"\", \
                    "\"service_description"\": "\"Disk\ Usage\ $drive_letter:"\", \
                    "\"check_command"\": "\"check_nrpe_win_drivesize"\", \
                    "\"check_command_args"\": "\"Drive=$drive_letter\ MaxWarn=85%\ MaxCrit=95%"\", \
                    "\"check_interval"\": "\"5"\", \
                    "\"check_period"\": "\"24x7"\", \
                    "\"max_check_attempts"\": "\"3"\", \
                    "\"retry_interval"\": "\"1"\", \
                    "\"notification_interval"\": "\"0"\", \
                    "\"notification_options"\": "\"c,w,u,r,f,s"\", \
                    "\"notification_period"\": "\"24x7"\", \
                    "\"template"\": "\"default-service"\"}" \
            "https://$op5_host/api/config/service" >> /dev/null
    done
done
printf "[DONE]\n\n"

printf "Saving changes...\n"
# Save changes to OP5 Monitor
$curl -s -k -X POST -H 'content-type: application/json' -u "$username:$password" "https://$op5_host/api/config/change" >> /dev/null
printf "[DONE]\n\n"
