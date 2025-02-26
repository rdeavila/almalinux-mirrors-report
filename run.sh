#!/bin/bash

notify() {
  mirror=$1
  time_difference=$2

  if grep -q "${mirror}" notification-list.json; then
    email=$(jq -r --arg m "$mirror" '.[] | select(.mirror_name == $m) | .email' notification-list.json)

    json=$(jq -n \
        --arg mirror "$mirror" \
        --arg difference "$time_difference" \
        --arg email "$email" \
        '{sender: {email: "no-reply@rda.run",name: "Mirror Report from rda.run"},
        to: [{email: "\($email)"}],
        textContent: "Hi there!\n\nThe mirror \($mirror) is \($time_difference) behind official AlmaLinux mirrors.\nPlease check the mirror status and update it accordingly.",
        subject: "\($mirror) is \($time_difference) behind official AlmaLinux mirrors"
        }')

    curl -Ssl --request POST \
        --url https://api.brevo.com/v3/smtp/email \
        --header 'accept: application/json' \
        --header "api-key: $BREVO_API_KEY" \
        --header 'content-type: application/json' \
        --data "$json" -o /dev/null
  fi
}

time_ago_in_words() {
    from_time=$1
    to_time=$2

    time_difference=$((to_time - from_time))
    minutes=$((difference / 60))
    hours=$((minutes / 60))
    days=$((hours / 24))
    weeks=$((days / 7))
    months=$((days / 30))

    if [[ $time_difference -le 1 ]]; then
        echo "one minute"
    elif [[ $minutes -le 59 ]]; then
        echo "$minutes minutes"
    elif [[ $minutes -le 119 ]]; then
        echo "an hour"
    elif [[ $minutes -le 1439 ]]; then
        echo "$hours hours"
    elif [[ $minutes -le 10079 ]]; then
        echo "$days days"
    elif [[ $minutes -le 43199 ]]; then
        echo "$weeks weeks"
    else
        echo "more than a month"
    fi
}

echo "Collecting time from primary mirrors..."

atl_resp=$(curl -s -k --max-time 10 "https://atl.rsync.repo.almalinux.org/almalinux/TIME")
sea_resp=$(curl -s -k "https://sea.rsync.repo.almalinux.org/almalinux/TIME")

if [[ $atl_resp -ge $sea_resp ]]; then
    echo " done. Using time from ATL"
    original_time=$atl_resp
else
    echo " done. Using time from SEA"
    original_time=$sea_resp
fi

echo "Collecting mirror list..."
all_mirrors=$(curl -s -k --max-time 10 "https://mirrors.almalinux.org/debug/json/all_mirrors")
mirrorlist=$(echo "$all_mirrors" | jq '.result')
echo " done."

cat <<MD > docs/index.md
---
hide:
  - footer
  - toc
  - navigation
---

# AlmaLinux Mirror Propagation Report

This service provides information about the status of the AlmaLinux mirrors. The report shows the time it takes for updates to propagate to the mirrors, as well as the number of mirrors that have been updated. This information can be used to identify mirrors that are not up to date, and to troubleshoot any problems with the mirror propagation process.

- Source mirror address: \`rsync.repo.almalinux.org\`
- Source mirror build date: \`$(date -d @$original_time)\`

MD

mirrorlist_total=$(echo "$mirrorlist" | jq 'keys | length')
mirrorlist_completed=0

echo "Starting mirror probe..."
in_sync=""
behind=""
unavailable=""

# Store the list of mirrors in a variable
mirror_keys=$(echo "$mirrorlist" | jq -r 'keys[]')

# Loop through each mirror in the mirror list
while read -r mirror; do
    # Get the status and privacy setting of the current mirror
    status=$(echo "$mirrorlist" | jq -r --arg m "$mirror" '.[$m].status')
    private=$(echo "$mirrorlist" | jq -r --arg m "$mirror" '.[$m].private')

    if [[ $status == "ok" && $private == false ]]; then
        # Get the sponsor name and URL of the current mirror
        sponsor=$(echo "$mirrorlist" | jq -r  --arg m "$mirror" '.[$m].sponsor_name')
        sponsor_url=$(echo "$mirrorlist" | jq -r --arg m "$mirror" '.[$m].sponsor_url')

        # Determine the mirror address (HTTP or HTTPS)
        if echo "$mirrorlist" | jq -e --arg m "$mirror" '.[$m].urls.http' >/dev/null; then
            mirror_address=$(echo "$mirrorlist" | jq -r --arg m "$mirror" '.[$m].urls.http')
        else
            mirror_address=$(echo "$mirrorlist" | jq -r --arg m "$mirror" '.[$m].urls.https')
        fi

        if [[ ! $mirror_address =~ /$ ]]; then
            mirror_address="$mirror_address/"
        fi

        # Fetch the mirror's TIME file to get the last update time
        mirror_resp=$(curl -sSL --max-time 5 --max-redirs 2 "$mirror_address/TIME" 2>&1)

        if [[ $? -eq 0 ]] && [[ $mirror_resp =~ ^[0-9]+$ ]]; then
            # Calculate the time difference between the primary mirror and the current mirror
            mirror_time=$mirror_resp
            compare=$((original_time - mirror_time))

            if [[ $compare -le 0 ]]; then
                # Mirror is in sync with the primary mirror
                in_sync+="    | ${mirror} | [${sponsor}](${sponsor_url}) |"$'\n'
            else
                # Mirror is behind the primary mirror
                behind+="    | ${mirror} | [${sponsor}](${sponsor_url}) | $(time_ago_in_words "${mirror_time}" "${original_time}") |"$'\n'
                # Notify if the mirror is significantly behind (more than 6 hours)
                if [[ $compare -gt 21600 ]]; then
                    notify "$mirror" "$(time_ago_in_words "${mirror_time}" "${original_time}")"
                fi
            fi
        else
            # Mirror is unavailable or failed to fetch the TIME file
            unavailable+="    | ${mirror} | [${sponsor}](${sponsor_url}) | ${mirror_resp} |"$'\n'
        fi
    fi
    # Increment the count of tested mirrors
    mirrorlist_completed=$((mirrorlist_completed + 1))

    # Print the progress of tested mirrors
    echo "Tested $mirrorlist_completed of $mirrorlist_total"
done <<< "$mirror_keys"

cat <<MD >> docs/index.md
=== "In sync"

    | Mirror Name | Sponsor |
    |:--|:--|
${in_sync}

=== "Behind primary"

    | Mirror Name | Sponsor | Time behind primary |
    |:--|:--|:--|
${behind}

=== "Unavailable"

    | Mirror Name | Sponsor | Reason |
    |:--|:--|:--|
${unavailable}


Last report update: \`$(date -u)\`

MD

echo "Writing Markdown... done."
