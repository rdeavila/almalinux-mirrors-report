#!/bin/bash

# Função para calcular o tempo decorrido em palavras (adaptada para o Bash)
time_ago_in_words() {
    from_time=$1
    to_time=$2

    difference=$((to_time - from_time))
    minutes=$((difference / 60))
    hours=$((minutes / 60))
    days=$((hours / 24))
    weeks=$((days / 7))
    months=$((days / 30))

    if [[ $minutes -le 1 ]]; then
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

# Usando curl para obter o tempo dos espelhos (substituindo Crest)
atl_resp=$(curl -s -k "https://atl.rsync.repo.almalinux.org/almalinux/TIME")
sea_resp=$(curl -s -k "https://sea.rsync.repo.almalinux.org/almalinux/TIME")

if [[ $atl_resp -ge $sea_resp ]]; then
    echo " done. Using time from ATL"
    original_time=$atl_resp
else
    echo " done. Using time from SEA"
    original_time=$sea_resp
fi

echo "Collecting mirror list..."

# Usando curl e jq para obter e processar a lista de espelhos
all_mirrors=$(curl -s -k "https://mirrors.almalinux.org/debug/json/all_mirrors")
mirrorlist=$(echo "$all_mirrors" | jq '.result')
echo " done."

# Usando heredoc para construir o Markdown
cat <<MD > docs/index.md
---
hide:
  - footer
  - toc
  - navigation
---

# AlmaLinux Mirror Propagation Report

This service provides information about the status of the AlmaLinux mirrors. The report shows the time it takes for updates to propagate to the mirrors, as well as the number of mirrors that have been updated. This information can be used to identify mirrors that are not up to date, and to troubleshoot any problems with the mirror propagation process.

- Source mirror address: `rsync.repo.almalinux.org`
- Source mirror build date: `$(date -d @$original_time)`

MD

mirrorlist_total=$(echo "$mirrorlist" | jq 'keys | length')
mirrorlist_completed=0

echo "Starting mirror probe..."

# Iterando sobre os espelhos usando jq
echo "$mirrorlist" | jq -r 'keys[]' | while read -r mirror; do
    status=$(echo "$mirrorlist" | jq -r ".[$mirror].status")
    private=$(echo "$mirrorlist" | jq -r ".[$mirror].private")

    if [[ $status == "ok" && $private == false ]]; then
        sponsor=$(echo "$mirrorlist" | jq -r ".[$mirror].sponsor_name")
        sponsor_url=$(echo "$mirrorlist" | jq -r ".[$mirror].sponsor_url")

        if echo "$mirrorlist" | jq -e ".[$mirror].urls.http" >/dev/null; then
            mirror_address=$(echo "$mirrorlist" | jq -r ".[$mirror].urls.http")
        else
            mirror_address=$(echo "$mirrorlist" | jq -r ".[$mirror].urls.https")
        fi

        if [[ ! $mirror_address =~ /$ ]]; then
            mirror_address="$mirror_address/"
        fi

        # Usando curl com timeout para obter o tempo do espelho
        mirror_resp=$(curl -s -k -m 2 -max-time 2 --max-redirs 2 "$mirror_address/TIME")

        if [[ $? -eq 0 ]]; then
            mirror_time=$mirror_resp
            compare=$((original_time - mirror_time))

            if [[ $compare -le 0 ]]; then
                in_sync+="    | $mirror | [$sponsor]($sponsor_url) |\n"
            else
                behind+="    | $mirror | [$sponsor]($sponsor_url) | $(time_ago_in_words $mirror_time $original_time) |\n"
            fi
        else
            unavailable+="    | $mirror | [$sponsor]($sponsor_url) | curl error |\n" 
        fi
    fi
    mirrorlist_completed=$((mirrorlist_completed + 1))

    echo "  $((mirrorlist_completed / mirrorlist_total * 100))%"
done

# Adicionando as tabelas ao Markdown
cat <<MD >> docs/index.md

=== "In sync"

    | Mirror Name | Sponsor |
    |:--|:--|
$in_sync

=== "Behind primary"

    | Mirror Name | Sponsor | Time behind primary |
    |:--|:--|:--|
$behind

=== "Unavailable"

    | Mirror Name | Sponsor | Reason |
    |:--|:--|:--|
$unavailable


Last report update: `$(date -u)`

MD

echo "Writing Markdown... done."