#!/bin/bash

if ! command -v jq >/dev/null 2>&1; then
  echo "The jq command is not available."
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "The yq command is not available"
  exit 1
fi

ATL_TIME=$(date -d "$(curl -sSq https://atl.rsync.repo.almalinux.org/almalinux/timestamp.txt)" +%s)
SEA_TIME=$(date -d "$(curl -sSq https://sea.rsync.repo.almalinux.org/almalinux/timestamp.txt)" +%s)

if [ $ATL_TIME -ge $SEA_TIME ]; then
  ORIGINAL_TIME=$ATL_TIME
else
  ORIGINAL_TIME=$SEA_TIME
fi

# Example: https://admin.fedoraproject.org/mirrormanager/propagation

# This diagram shows how many mirrors for the development branch have a repomd.xml file which is the 
# same (respectively one day older, two days older or much older) version as on the 
# master mirror.

# File names
FILES=$(curl -fsSL https://api.github.com/repos/AlmaLinux/mirrors/contents/mirrors.d | jq -r '.[].name')

echo "---"
echo "hide:"
echo "  - footer"
echo "  - toc"
echo "  - navigation"
echo "---"
echo ""
echo "# AlmaLinux Mirror Propagation Report"
echo ""
echo "This service provides information about the status of the AlmaLinux mirrors. The report shows the time it takes for updates to propagate to the mirrors, as well as the number of mirrors that have been updated. This information can be used to identify mirrors that are not up to date, and to troubleshoot any problems with the mirror propagation process."
echo ""
echo "## Primary mirror info"
echo ""
echo "- Address: \`rsync.repo.almalinux.org\`"
echo "- Last update: \`$(date -ud "@$ORIGINAL_TIME" +"%Y-%m-%d %H:%M:%S") UTC\`"
echo ""

declare -a IN_SYNC
declare -a BEHIND
declare -a UNAVAILABLE
i=0
j=0
k=0

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

      if [ "$DIFF" -le 0 ]; then
        TIME="IN SYNC"
        IN_SYNC[$i]="| $NAME | $SPONSOR |"
        i=$((i+1))
      else
        days=$((DIFF / 86400))
        hours=$(( (DIFF % 86400) / 3600 ))
        minutes=$(( (DIFF % 3600) / 60 ))

        TIME="$([ $days -gt 0 ] && echo -n "${days}d ")$([ $hours -gt 0 ] && echo -n "${hours}h ")$([ $minutes -gt 0 ] && echo "${minutes}min") behind"
        BEHIND[$j]="| $NAME | $SPONSOR | $TIME |"
        j=$((j+1))
      fi
    else
      TIME="Unavailable"
      UNAVAILABLE[$k]="| $NAME | $SPONSOR |"
      k=$((k+1))
    fi
  else
    TIME="Unavailable"
    UNAVAILABLE[$k]="| $NAME | $SPONSOR |"
    k=$((k+1))
  fi
done

echo "=== \"In sync\""
echo ""
echo "    | Mirror Name | Sponsor |"
echo "    |:--|:--|"
for value in "${IN_SYNC[@]}"; do
  echo "    $value"
done

echo ""
echo "=== \"Behind primary\""
echo ""
echo "    | Mirror Name | Sponsor | Time behind primary |"
echo "    |:--|:--|:--|"
for value in "${BEHIND[@]}"; do
  echo "    $value"
done

echo ""
echo "=== \"Unavailable\""
echo ""
echo "    | Mirror Name | Sponsor |"
echo "    |:--|:--|"
for value in "${UNAVAILABLE[@]}"; do
  echo "    $value"
done

echo ""
echo ""
echo "Last report update: \`$(date -u +"%Y-%m-%d %H:%M:%S") UTC\`"
echo ""

exit 0
