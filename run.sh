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
    minutes=$((time_difference / 60))
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

in_sync_record() {
    echo "<tr><td>$1</td><td><a href=\"$2\" class=\"text-reset\">$3</a></td></tr>"
}

behind_record() {
    echo "<tr><td>$1</td><td><a href=\"$2\" class=\"text-reset\">$3</a></td><td>$4</td></tr>"
}

unavailable_record() {
    echo "<tr><td>$1</td><td><a href=\"$2\" class=\"text-reset\">$3</a></td><td>$4</td></tr>"
}

echo "Collecting time from primary mirrors..."

original_time=""
original_loc=""

# Atlanta, GA, USA
atl_resp=$(curl -s -k --max-time 10 "https://atl.rsync.repo.almalinux.org/almalinux/TIME")
original_time="$atl_resp"
original_loc="Atlanta, GA, USA"

# Seattle, WA, USA
sea_resp=$(curl -s -k "https://sea.rsync.repo.almalinux.org/almalinux/TIME")
if [[ -z "$original_time" ]] || [[ "$sea_resp" -gt "$original_time" ]]; then
    original_time="$sea_resp"
    source_server="Seattle, WA, USA"
fi

echo " done. Using time from $original_loc"

echo "Collecting mirror list..."
all_mirrors=$(curl -s -k --max-time 10 "https://mirrors.almalinux.org/debug/json/all_mirrors")
mirrorlist=$(echo "$all_mirrors" | jq '.result')
echo " done."

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
    status=$(jq -r --arg m "$mirror" '.[$m].status' <<< "$mirrorlist")
    private=$(jq -r --arg m "$mirror" '.[$m].private' <<< "$mirrorlist")

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
                in_sync+="$(in_sync_record "${mirror}" "${sponsor_url}" "${sponsor}")"
            else
                # Mirror is behind the primary mirror
                behind+="$(behind_record "${mirror}" "${sponsor_url}" "${sponsor}" "$(time_ago_in_words "${mirror_time}" "${original_time}")")"
                # Notify if the mirror is significantly behind (more than 3 hours)
                # if [[ $compare -gt 10800 ]]; then
                if [[ $compare -gt 60 ]]; then
                    notify "$mirror" "$(time_ago_in_words "${mirror_time}" "${original_time}")"
                fi
            fi
        else
            # Mirror is unavailable or failed to fetch the TIME file
            unavailable+="$(unavailable_record "${mirror}" "${sponsor_url}" "${sponsor}" "${mirror_resp}")"
        fi
    fi
    # Increment the count of tested mirrors
    mirrorlist_completed=$((mirrorlist_completed + 1))

    # Print the progress of tested mirrors
    echo "Tested $mirrorlist_completed of $mirrorlist_total"
done <<< "$mirror_keys"

echo -n "Writing file..."

rm -rf site
mkdir site
cp index.html ./site/

sed -i "s|IN_SYNC_RESPONSE|${in_sync}|g" ./site/index.html
sed -i "s|BEHIND_PRIMARY_RESPONSE|${behind}|g" ./site/index.html
sed -i "s|UNAVAILABLE_RESPONSE|${unavailable}|g" ./site/index.html
sed -i "s|SOURCE_TIME|$(date -d @$original_time)|g" ./site/index.html
sed -i "s|REPORT_TIME|$(date -u)|g" ./site/index.html

echo " done."

exit 0
