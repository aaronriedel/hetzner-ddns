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
#get IPv4 address:
IPv4="$(curl -s4 https://ip.hetzner.com)"
echo "#####################"
echo "DDNS Manager by Aaron"
echo "started $(date)"
echo "DNS Record will be $SERVERNAME.$DNSZONE"
echo -n "IPv4 is: "
echo $IPv4
echo ""
#############################################
API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" "https://dns.hetzner.com/api/v1/zones" -H "Auth-API-Token: ${HETZNER_API_TOKEN}")
if [ $API_STATUS_CODE != "200" ]; then
	echo "API ERROR"
	response_code $API_STATUS_CODE
fi
if [ -z $IPv4 ]; then
	echo "no IPv4 found"
	exit 1
fi
#############################################
HETZNER_API_ZONE=$(curl -s "https://dns.hetzner.com/api/v1/zones" -H "Auth-API-Token: ${HETZNER_API_TOKEN}" | jq -r ".zones[] | select(.name==\"$DNSZONE\") | .id")
#############################################
echo "Check DNS Console for existing records"
RECORDS=$(curl -s "https://dns.hetzner.com/api/v1/records?zone_id=${HETZNER_API_ZONE}" \
 -H "Auth-API-Token: ${HETZNER_API_TOKEN}")
echo $RECORDS | jq -r '.records[] | select(.type=="A") | .name' | grep -q $SERVERNAME
if [ $? -eq 1 ]; then
	echo "Record not found" 
	echo -n "Set new Record: "
	response_code $(curl -o /dev/null -s -w "%{http_code}" -X "POST" "https://dns.hetzner.com/api/v1/records" \
	     -H 'Content-Type: application/json' \
	     -H "Auth-API-Token: ${HETZNER_API_TOKEN}" \
	     -d $"{
	  \"value\": \"${IPv4}\",
	  \"ttl\": 60,
	  \"type\": \"A\",
	  \"name\": \"${SERVERNAME}\",
	  \"zone_id\": \"${HETZNER_API_ZONE}\"
	}")
	echo ""
else
	echo "Record already there"
	RECORD_ID=$(echo $RECORDS | jq -r '.records[] | select(.type=="A") | select(.name=="'${SERVERNAME}'") | .id' | head -1)
	echo -n "Current IP from Record: "
	OLD_IP=$(echo $RECORDS | jq -r '.records[] | select(.type=="A") | select(.name=="'${SERVERNAME}'") | .value' | head -1)
	echo $OLD_IP
	if [ $IPv4 != $OLD_IP ]; then
		echo "IP has changed"
		echo -n "Updating Record... "
		response_code $(curl -o /dev/null -s -w "%{http_code}" -X "PUT" "https://dns.hetzner.com/api/v1/records/$RECORD_ID" \
		     -H 'Content-Type: application/json' \
		     -H "Auth-API-Token: ${HETZNER_API_TOKEN}" \
		     -d $"{
		  \"value\": \"${IPv4}\",
		  \"ttl\": 60,
		  \"type\": \"A\",
		  \"name\": \"${SERVERNAME}\",
		  \"zone_id\": \"${HETZNER_API_ZONE}\"
		}")
		echo ""
	else
		echo "IP has not changed"
	fi
fi
exit 0
