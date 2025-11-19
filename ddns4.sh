#!/bin/bash
##########################################################################################
source $(dirname "$0")/.env
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
	if [[ $1 == "200" ]]; then echo "$1 Success";
	elif [[ $1 == "201" ]]; then echo "$1 Success";
	elif [[ $1 == "401" ]]; then echo "$1 Unauthorized" && exit 1;
	elif [[ $1 == "403" ]]; then echo "$1 Forbidden" && exit 1;
	elif [[ $1 == "406" ]]; then echo "$1 Not acceptable" && exit 1;
	elif [[ $1 == "422" ]]; then echo "$1 Unprocessable entity" && exit 1;
	else echo "$1 Unknown Status Code" && exit 1; fi
}
#############################################
echo -e "[INFO] DDNS Manager by Aaron"
echo -e "[INFO] started $(date)"
echo -e "[INFO] DNS Record will be $SUBDOMAIN_IPV4.$DNSZONE_IPV4"
echo -e "[....] get IP address"
IPv4="$(curl -s4 https://ip.hetzner.com)"
if [[ -z $IPv4 || ! $IPv4 =~ ^[0-9]{1,3}("."[0-9]{1,3}){3}$ ]]; then
	IPv4="$(curl -s4 https://icanhazip.com)"
fi
if [[ -z $IPv4 || ! $IPv4 =~ ^[0-9]{1,3}("."[0-9]{1,3}){3}$ ]]; then
	echo -e "[FAIL] IPv4 not found"
	exit 1
else
	echo -e "[DONE] get IP address"
	echo -e "[INFO] IP address is $IPv4"
fi

#############################################
echo -e "[....] attempt API connection"
API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" "https://api.hetzner.cloud/v1/zones" -H "Authorization: Bearer ${HETZNER_API_TOKEN}")
if [[ $API_STATUS_CODE != "200" ]]; then
	echo -e "[FAIL] attempt API connection ($(response_code $API_STATUS_CODE))"
	exit 1
else
	echo -e "[DONE] attempt API connection ($(response_code $API_STATUS_CODE))"
fi

#############################################
echo -e "[....] get Zone"
HETZNER_API_ZONE=$(curl -s "https://api.hetzner.cloud/v1/zones/${DNSZONE_IPV4}" -H "Authorization: Bearer ${HETZNER_API_TOKEN}" | jq -r '.zone.id')
if [ $HETZNER_API_ZONE == "null" ]; then
	echo -e "[FAIL] get DNS Zone"
	exit 1
else
	echo -e "[DONE] get DNS Zone"
fi
#############################################
echo -e "[....] Check for existing records"
API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" "https://api.hetzner.cloud/v1/zones/${HETZNER_API_ZONE}/rrsets/${SUBDOMAIN_IPV4}/A" \
 -H "Authorization: Bearer ${HETZNER_API_TOKEN}")
echo -e "[DONE] Check DNS Console for existing records"
if [[ $API_STATUS_CODE != "200" ]]; then
	echo -e "[INFO] Record not found"
	echo -e "[....] Set new Record"
	API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" -X "POST" "https://api.hetzner.cloud/v1/zones/${HETZNER_API_ZONE}/rrsets" \
	     -H 'Content-Type: application/json' \
	     -H "Authorization: Bearer ${HETZNER_API_TOKEN}" \
	     -d $"{
			  \"ttl\": 60,
			  \"type\": \"A\",
			  \"name\": \"${SUBDOMAIN_IPV4}\",
			  \"records\": [{
			  	\"value\": \"${IPv4}\",
			  	\"comment\": \"Created by hetzner-ddns script.\"
			  	}]
			}")
	if [[ $API_STATUS_CODE != "201" ]]; then
		echo -e "[FAIL] Set new Record ($(response_code $API_STATUS_CODE))"
		exit 1
	else
		echo -e "[DONE] Set new Record ($(response_code $API_STATUS_CODE))"
	fi
else
	echo -e "[INFO] Record already there"
	OLD_IP=$(curl -s -H "Authorization: Bearer ${HETZNER_API_TOKEN}" "https://api.hetzner.cloud/v1/zones/${HETZNER_API_ZONE}/rrsets/${SUBDOMAIN_IPV4}/A" | jq -r '.rrset.records[0].value')
	echo -e "[INFO] Current IP from Record: $OLD_IP"
	if [[ $IPv4 != $OLD_IP ]]; then
		echo -e "[INFO] IP has changed"
		echo -e "[....] Updating Record"
		API_STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}" -X "POST" "https://api.hetzner.cloud/v1/zones/${HETZNER_API_ZONE}/rrsets/${SUBDOMAIN_IPV4}/A/actions/set_records" \
		     -H 'Content-Type: application/json' \
		     -H "Authorization: Bearer ${HETZNER_API_TOKEN}" \
		     -d $"{
			  \"records\": [{
			  	\"value\": \"${IPv4}\",
			  	\"comment\": \"Created by hetzner-ddns script.\"
			  	}]
			}")
		if [[ $API_STATUS_CODE != "201" ]]; then
			echo -e "[FAIL] Updating Record ($(response_code $API_STATUS_CODE))"
			exit 1
		else
			echo -e "[DONE] Updating Record ($(response_code $API_STATUS_CODE))"
		fi
	else
		echo -e "[INFO] IP has not changed"
	fi
fi
exit 0
