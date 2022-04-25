#!/bin/bash
##########################################################################################
source .env
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

PENDING="${NONE}[${YELLOW}....${NONE}]"
DONE="${NONE}[${GREEN} OK ${NONE}]"
FAIL="${NONE}[${RED}FAIL${NONE}]"
INFO="${NONE}[${BOLD}INFO${NONE}]"
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
echo -e "${INFO} DNS Record will be $SUBDOMAIN_IPV4.$DNSZONE_IPV4"
echo -e "${PENDING} get IP address"
IPv4="$(curl -s4 https://ip.hetzner.com)"
if [ -z $IPv4 ]; then
	echo -e "${REPLACE}${FAIL} IPv4 not found"
	exit 1
else
	echo -e "${REPLACE}${DONE} get IP address"
	echo -e "${INFO} IP address is $IPv4"
fi

#############################################
echo -e "${PENDING} attempt API connection"
API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" "https://dns.hetzner.com/api/v1/zones" -H "Auth-API-Token: ${HETZNER_API_TOKEN}")
if [ $API_STATUS_CODE != "200" ]; then
	echo -e "${REPLACE}${FAIL} attempt API connection ($(response_code $API_STATUS_CODE))"
	exit 1
else
	echo -e "${REPLACE}${DONE} attempt API connection ($(response_code $API_STATUS_CODE))"
fi

#############################################
echo -e "${PENDING} get Zones"
HETZNER_API_ZONE=$(curl -s "https://dns.hetzner.com/api/v1/zones" -H "Auth-API-Token: ${HETZNER_API_TOKEN}" | jq -r ".zones[] | select(.name==\"$DNSZONE_IPV4\") | .id")
if [ -z $HETZNER_API_ZONE ]; then
	echo -e "${REPLACE}${FAIL} get DNS Zone"
	exit 1
else
	echo -e "${REPLACE}${DONE} get DNS Zone"
fi
#############################################
echo -e "${PENDING} Check DNS Console for existing records"
RECORDS=$(curl -s "https://dns.hetzner.com/api/v1/records?zone_id=${HETZNER_API_ZONE}" \
 -H "Auth-API-Token: ${HETZNER_API_TOKEN}")
echo -e "${REPLACE}${DONE} Check DNS Console for existing records"
echo $RECORDS | jq -r '.records[] | select(.type=="A") | .name' | grep -q $SUBDOMAIN_IPV4
if [ $? -eq 1 ]; then
	echo -e "${INFO} Record not found" 
	echo -e "${PENDING} Set new Record"
	API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" -X "POST" "https://dns.hetzner.com/api/v1/records" \
	     -H 'Content-Type: application/json' \
	     -H "Auth-API-Token: ${HETZNER_API_TOKEN}" \
	     -d $"{
	  \"value\": \"${IPv4}\",
	  \"ttl\": 60,
	  \"type\": \"A\",
	  \"name\": \"${SUBDOMAIN_IPV4}\",
	  \"zone_id\": \"${HETZNER_API_ZONE}\"
	}")
	if [ $API_STATUS_CODE != "200" ]; then
		echo -e "${REPLACE}${FAIL} Set new Record $(response_code $API_STATUS_CODE)"
		exit 1
	else
		echo -e "${REPLACE}${DONE} Set new Record $(response_code $API_STATUS_CODE)"
	fi
else
	echo -e "${INFO} Record already there"
	RECORD_ID=$(echo $RECORDS | jq -r '.records[] | select(.type=="A") | select(.name=="'${SUBDOMAIN_IPV4}'") | .id' | head -1)
	OLD_IP=$(echo $RECORDS | jq -r '.records[] | select(.type=="A") | select(.name=="'${SUBDOMAIN_IPV4}'") | .value' | head -1)
	echo -e "${INFO} Current IP from Record: $OLD_IP"
	if [ $IPv4 != $OLD_IP ]; then
		echo -e "${INFO} IP has changed"
		echo -e "${PENDING} Updating Record"
		API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" -X "PUT" "https://dns.hetzner.com/api/v1/records/$RECORD_ID" \
		     -H 'Content-Type: application/json' \
		     -H "Auth-API-Token: ${HETZNER_API_TOKEN}" \
		     -d $"{
		  \"value\": \"${IPv4}\",
		  \"ttl\": 60,
		  \"type\": \"A\",
		  \"name\": \"${SUBDOMAIN_IPV4}\",
		  \"zone_id\": \"${HETZNER_API_ZONE}\"
		}")
		if [ $API_STATUS_CODE != "200" ]; then
			echo -e "${REPLACE}${FAIL} Updating Record $(response_code $API_STATUS_CODE)"
			exit 1
		else
			echo -e "${REPLACE}${DONE} Updating Record $(response_code $API_STATUS_CODE)"
		fi
	else
		echo -e "${INFO} IP has not changed"
	fi
fi
exit 0
