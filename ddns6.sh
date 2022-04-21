#!/bin/bash
##########################################################################################
# SETTINGS
HETZNER_API_TOKEN=""  # https://dns.hetzner.com/settings/api-token
SERVERNAME=""         # desired subdomain  e.g. "server1"
DNSZONE=""            # name of the zone in DNS Console  e.g. "example.com"
##########################################################################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Software dependency not met: $1"
        exit 1
    fi
}
for COMMAND in "curl" "jq" "grep"; do
    command_exists "${COMMAND}"
done
#############################################
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
YELLOW='\033[01;33m'
PURPLE='\033[01;35m'
CYAN='\033[01;36m'
WHITE='\033[01;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
REPLACE='\e[1A\e[K'

PENDING="${NONE}[${YELLOW}PENDING${NONE}]"
SUCCESS="${NONE}[${GREEN}SUCCESS${NONE}]"
ERROR="${NONE}[${RED} ERROR ${NONE}]"
INFO="${NONE}[${BOLD} INFOS ${NONE}]"
#############################################
#HTTP Response Code Echo
response_code() {
	if [ $1 == "200" ]; then echo "$1 Success";
	elif [ $1 == "401" ]; then echo "$1 Unauthorized" && exit 1;
	elif [ $1 == "403" ]; then echo "$1 Forbidden" && exit 1;
	elif [ $1 == "406" ]; then echo "$1 Not acceptable" && exit 1;
	elif [ $1 == "422" ]; then echo "$1 Unprocessable entity" && exit 1;
	else echo "$1 Unknown Status Code" && exit 1; fi
}
#############################################
echo -e "${INFO} DDNS Manager by Aaron"
echo -e "${INFO} started $(date)"
echo -e "${INFO} DNS Record will be $SERVERNAME.$DNSZONE"
echo -e "${PENDING} get IP address"
IPv6="$(curl -s6 https://ip.hetzner.com)"
if [ -z $IPv6 ]; then
	echo -e "${REPLACE}${ERROR} IPv6 not found"
	exit 1
else
	echo -e "${REPLACE}${SUCCESS} get IP address"
	echo -e "${INFO} IP address is $IPv6"
fi

#############################################
echo -e "${PENDING} attempt API connection"
API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" "https://dns.hetzner.com/api/v1/zones" -H "Auth-API-Token: ${HETZNER_API_TOKEN}")
if [ $API_STATUS_CODE != "200" ]; then
	echo -e "${REPLACE}${ERROR} attempt API connection ($(response_code $API_STATUS_CODE))"
	exit 1
else
	echo -e "${REPLACE}${SUCCESS} attempt API connection ($(response_code $API_STATUS_CODE))"
fi

#############################################
echo -e "${PENDING} get Zones"
HETZNER_API_ZONE=$(curl -s "https://dns.hetzner.com/api/v1/zones" -H "Auth-API-Token: ${HETZNER_API_TOKEN}" | jq -r ".zones[] | select(.name==\"$DNSZONE\") | .id")
if [ -z $HETZNER_API_ZONE ]; then
	echo -e "${REPLACE}${ERROR} get DNS Zone"
	exit 1
else
	echo -e "${REPLACE}${SUCCESS} get DNS Zone"
fi
#############################################
echo -e "${PENDING} Check DNS Console for existing records"
RECORDS=$(curl -s "https://dns.hetzner.com/api/v1/records?zone_id=${HETZNER_API_ZONE}" \
 -H "Auth-API-Token: ${HETZNER_API_TOKEN}")
echo -e "${REPLACE}${SUCCESS} Check DNS Console for existing records"
echo $RECORDS | jq -r '.records[] | select(.type=="AAAA") | .name' | grep -q $SERVERNAME
if [ $? -eq 1 ]; then
	echo -e "${INFO} Record not found" 
	echo -e "${PENDING} Set new Record"
	API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" -X "POST" "https://dns.hetzner.com/api/v1/records" \
	     -H 'Content-Type: application/json' \
	     -H "Auth-API-Token: ${HETZNER_API_TOKEN}" \
	     -d $"{
	  \"value\": \"${IPv6}\",
	  \"ttl\": 60,
	  \"type\": \"AAAA\",
	  \"name\": \"${SERVERNAME}\",
	  \"zone_id\": \"${HETZNER_API_ZONE}\"
	}")
	if [ $API_STATUS_CODE != "200" ]; then
		echo -e "${REPLACE}${ERROR} Set new Record $(response_code $API_STATUS_CODE)"
		exit 1
	else
		echo -e "${REPLACE}${SUCCESS} Set new Record $(response_code $API_STATUS_CODE)"
	fi
else
	echo -e "${INFO} Record already there"
	RECORD_ID=$(echo $RECORDS | jq -r '.records[] | select(.type=="AAAA") | select(.name=="'${SERVERNAME}'") | .id' | head -1)
	OLD_IP=$(echo $RECORDS | jq -r '.records[] | select(.type=="AAAA") | select(.name=="'${SERVERNAME}'") | .value' | head -1)
	echo -e "${INFO} Current IP from Record: $OLD_IP"
	if [ $IPv6 != $OLD_IP ]; then
		echo -e "${INFO} IP has changed"
		echo -e "${PENDING} Updating Record"
		API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" -X "PUT" "https://dns.hetzner.com/api/v1/records/$RECORD_ID" \
		     -H 'Content-Type: application/json' \
		     -H "Auth-API-Token: ${HETZNER_API_TOKEN}" \
		     -d $"{
		  \"value\": \"${IPv6}\",
		  \"ttl\": 60,
		  \"type\": \"AAAA\",
		  \"name\": \"${SERVERNAME}\",
		  \"zone_id\": \"${HETZNER_API_ZONE}\"
		}")
		if [ $API_STATUS_CODE != "200" ]; then
			echo -e "${REPLACE}${ERROR} Updating Record $(response_code $API_STATUS_CODE)"
			exit 1
		else
			echo -e "${REPLACE}${SUCCESS} Updating Record $(response_code $API_STATUS_CODE)"
		fi
	else
		echo -e "${INFO} IP has not changed"
	fi
fi
exit 0
