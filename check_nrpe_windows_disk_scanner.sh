#!/bin/bash
#
# "THE BEER-WARE LICENSE" - - - - - - - - - - - - - - - - - -
# This file was initially written by Robert Claesson.
# As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.
# - - - - - - - - - - - - - - - robert.claesson@gmail.com - -
#
#################################################################################################################################
#
# Description: Queries a Windows host for drive letters by NRPE and adds a service-check for each drive letter in OP5 Monitor.
#
# Runtime errors are logged in: /var/tmp/windows-disk-scanner.log
#
#################################################################################################################################

# Binaries
curl=$(which curl)
nrpe="/opt/plugins/check_nrpe"

# Check check_nrpe existence
if ! which "$nrpe"
then
	echo "Could not find check_nrpe plugin. Please check its location."
	exit 3
fi

help="\n
Usage: $0 -H op5-server -u api-user -p api-password -g host-group\n
Options:
-H Hostname/IP of OP5 server
-u API username
-p API password
-g Windows hostgroup name"

# Check for people who need help
if [ "${1}" = "--h" -o "${#}" = "0" ] || [ "${1}" = "--help" -o "${#}" = "0" ] || [ "${1}" = "-h" -o "${#}" = "0" ];
        then
        echo -e "${help}";
        exit 3
fi

# Setup variables
while getopts "H:u:p:g:" input; do
        case ${input} in
        H)      op5_host=${OPTARG};;
        u)      username=${OPTARG};;
		p)		password=${OPTARG};;
		g)		windows_hostgroup=${OPTARG};;
        *)      $help ; exit 3;;
        \?)     $help ; exit 3;;
        esac
done

# Get all hosts from Windows hostgroup
printf "\nFetching hosts from Windows host groups...\n"
hosts=$($curl -s -g -k -X GET -u "$username:$password" "https://$op5_host/api/filter/query?query=[hosts]%20groups%20%3E=%20%22$windows_hostgroup%22&columns=name&limit=1000")
if [ $? -ne "0" ]
then
    echo -e "$(date)" >> /var/tmp/windows-disk-scanner.log ; printf "ERROR: Could not contact OP5 API.\nExiting.\n\n" | tee -a /var/tmp/windows-disk-scanner.log
    exit 1
fi
printf "[DONE]\n\n"

# Trim JSON output to only values (host names)
hosts=$(sed -e 's/[}"]*\(.\)[{"]*/\1/g;y/,/\n/' <<< "$hosts" | cut -d":" -f2 | sed 's/]//g')

# Query hosts for drive letters (using NRPE)
printf "Searching for drive letters on hosts and adding those to OP5 Monitor...\n"
for host in $hosts
do
    drive_letters=$("$nrpe" -u -t 3 -s -H "$host" -c check_drivesize -a "filter=type in ('fixed')")
    if [ $? -eq "3" ]
    then
        echo -e $(date) >> /var/tmp/windows-disk-scanner.log ; printf "ERROR: Host $host could not be reachable over NRPE\n\n" | tee -a /var/tmp/windows-disk-scanner.log
        continue
    fi

    # Trim down to only drive letters
    drive_letters=$(echo $drive_letters | cut -d"|" -f2 | sed 's/[0-9]*//g' | sed -E -e 's/[[:blank:]]+/\n/g' | grep "^'" | cut -d"'" -f2 | cut -d":" -f1 | sort | grep -v "Volume" | uniq)

    # Add a service-check for each drive in OP5 Monitor
    for drive_letter in $drive_letters
    do
      # Verify drive_letter is a valid path
      if [[ $drive_letter =~ [A-Z] && ${#drive_letter} == 1 ]]
      then
        # Fetch OP5 hostname from address
        op5_hostname=$($curl -s -g -k -X GET -u "$username:$password" "https://$op5_host/api/filter/query?format=json&query=%5Bhosts%5D+address+%3D+%22$host%22&columns=name")

        # Add drive a service-check in OP5
        $curl \
            -s -k -H \
                    'content-type: application/json' \
            -u \
                    "$username:$password" \
            -d \
                    "{"\"file_id"\": "\"etc/services.cfg"\", \
                    "\"host_name"\": "\"$op5_hostname"\", \
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
       else
         echo -e $(date) >> /var/tmp/windows-disk-scanner.log ; printf "ERROR: $drive_letter is not a usable driver letter\n\n" | tee -a /var/tmp/windows-disk-scanner.log
      fi
    done
done
printf "[DONE]\n\n"

printf "Saving changes...\n"
# Save changes to OP5 Monitor
$curl -s -k -X POST -H 'content-type: application/json' -u "$username:$password" "https://$op5_host/api/config/change" >> /dev/null
printf "[DONE]\n\n"
