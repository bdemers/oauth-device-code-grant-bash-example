#!/bin/bash

client_id="${CLI_OKTA_CLIENT_ID}"
issuer="${CLI_OKTA_ISSUER}"

client_id=${1:-"${client_id}"}
issuer=${2:-"${issuer}"}

function usage () {
  echo "Usage: $0 <client-id> <issuer>"
}

if [[ ( $1 == "--help") ||  $1 == "-h" ]] 
then 
  usage
  exit 0
fi

if [[  -z "$client_id" || -z "$issuer" ]]
then 
  usage
  exit 1
fi

if ! command -v jq &> /dev/null
then
    echo "jq could not be found, it is required for this script"
    exit
fi

# Discovery of endpoint URLs
discovery_response=$(curl --silent --url "${issuer}/.well-known/openid-configuration")
authorize_url=$(echo "${discovery_response}" | jq --raw-output .'device_authorization_endpoint')
token_url=$(echo "${discovery_response}" | jq --raw-output .'token_endpoint')

# initial auth request
authorize_response=$(curl --silent \
  --request POST \
  --url "${authorize_url}" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=${client_id}" \
  --data-urlencode 'scope=openid profile offline_access')
  
echo "Server responded with:"
echo "${authorize_response}" | jq

device_code=$(echo "${authorize_response}" | jq --raw-output .'device_code')
verification_uri_complete=$(echo "${authorize_response}" | jq --raw-output .'verification_uri_complete')
verification_uri=$(echo "${authorize_response}" | jq --raw-output .'verification_uri')
user_code=$(echo "${authorize_response}" | jq --raw-output .'user_code')
interval=$(echo "${authorize_response}" | jq --raw-output .'interval')
expires_in=$(echo "${authorize_response}" | jq --raw-output .'expires_in')

echo
echo "Opening browser..."
open "${verification_uri_complete}"
echo
echo
echo "If a browser did not open go to: ${verification_uri}, and enter in the code: ${user_code}"
echo

# Display a QR code if `qrencode` is available
if command -v qrencode &> /dev/null
then
    echo "Or scan this QR Code and login from your phone"
    qrencode -m 2 -t utf8 "${verification_uri_complete}"
fi

echo
echo "Polling for status"

SECONDS=0
running=true
while ${running} && (( SECONDS < expires_in ))
do
  sleep "${interval}"

  token_response=$(curl --silent \
    --request POST \
    --url "${token_url}" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=${client_id}" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
    --data-urlencode "device_code=${device_code}")

echo "$token_response" | jq

  access_token=$(echo "${token_response}" | jq --raw-output .'access_token | select (.!=null)')

  if [[ -n "$access_token" ]]
  then
    running=false
    echo "Access Token: ${access_token}"
  else
    echo "Error:"
    echo "${token_response}" | jq
    echo
  fi
done

# Print error if script timed out
if [[ $SECONDS > $expires_in ]]
then
  echo "Code expired, run this script again"
fi
