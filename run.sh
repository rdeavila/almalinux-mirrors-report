#!/bin/bash

if ! command -v jq >/dev/null 2>&1; then
  echo "The jq command is not available."
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "The yq command is not available"
  exit 1
fi

if ! command -v pandoc >/dev/null 2>&1; then
  echo "The pandoc command is not available"
  exit 1
fi

ORIGINAL_TIME=$(curl -fsSL "https://rsync.repo.almalinux.org/almalinux/TIME")

IN_SYNC=0
UP_TO_12H=0
UP_TO_24H=0
MORE_THAN_24H=0
UNAVAILABLE=0

# Example: https://admin.fedoraproject.org/mirrormanager/propagation

# This diagram shows how many mirrors for the development branch have a repomd.xml file which is the 
# same (respectively one day older, two days older or much older) version as on the 
# master mirror.

# File names
FILES=$(curl -fsSL https://api.github.com/repos/AlmaLinux/mirrors/contents/mirrors.d | jq -r '.[].name')
TABLE=""

echo "# AlmaLinux Mirror Propagation Report"
echo ""
echo "This service provides information about the status of the AlmaLinux mirrors. The report shows the time it takes for updates to propagate to the mirrors, as well as the number of mirrors that have been updated. This information can be used to identify mirrors that are not up to date, and to troubleshoot any problems with the mirror propagation process."
echo ""
echo "- Primary mirror: \`rsync.repo.almalinux.org\`, updated at \`$(date -ud "@$ORIGINAL_TIME" +"%Y-%m-%d %H:%M:%S") UTC\`"

TABLE+=$(echo "| Mirror Name | Sponsor | Status |\n")
TABLE+=$(echo "|:--|:--|:--|\n")

for FILE in $FILES; do
  DETAILS=$(curl -fsSL "https://raw.githubusercontent.com/AlmaLinux/mirrors/master/mirrors.d/$FILE")
  NAME=$(yq -r '.name' <<< "$DETAILS")
  SPONSOR=$(yq -r '.sponsor' <<< "$DETAILS")
  ADDRESS=$(yq -r '.address.https' <<< "$DETAILS")

  if [ "$ADDRESS" == "null" ]; then
    ADDRESS=$(yq -r '.address.http' <<< "$DETAILS")
  fi

  if [[ "${ADDRESS: -1}" != '/' ]]; then
    ADDRESS="$ADDRESS/"
  fi

  TIME=$(curl -fsSL -m 2 "${ADDRESS}TIME" 2>/dev/null)

  if [ $? -eq 0 ]; then
    if [[ $TIME =~ ^[0-9]+$ ]]; then
      DIFF=$(($ORIGINAL_TIME - $TIME))

      if [ "$DIFF" -eq 0 ]; then
        TIME="IN SYNC"
        IN_SYNC=$((IN_SYNC + 1))
      else
        TIME="$(date -d "@$(($DIFF))" +"%Hh %Mmin") behind"
        DAYS=$((epoch / 86400))
        HOURS=$(( (epoch % 86400) / 3600 ))

        if [ "$DAYS" -eq 0 ]; then
          if [ "$HOURS" -le 12 ]; then
              UP_TO_12H=$((UP_TO_12H + 1))
          else
              UP_TO_24H=$((UP_TO_24H + 1))
          fi
        else
          MORE_THAN_24H=$((MORE_THAN_24H + 1))
        fi
      fi
    else
      TIME="Unavailable"
      UNAVAILABLE=$((UNAVAILABLE + 1))
    fi
  else
    TIME="Unavailable"
    UNAVAILABLE=$((UNAVAILABLE + 1))
  fi

  TABLE+=$(echo "| $NAME | $SPONSOR | $TIME |\n")
done

echo "- In sync: $IN_SYNC"
echo "- Up to 12h: $UP_TO_12H"
echo "- Up to 24h: $UP_TO_24H"
echo "- More than 24h: $MORE_THAN_24H"
echo "- Unavailable: $UNAVAILABLE"
echo "- Report update: \`$(date -u +"%Y-%m-%d %H:%M:%S") UTC\`"

echo -e $TABLE

exit 0
