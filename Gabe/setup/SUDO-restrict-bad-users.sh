#!/bin/bash

allowed_users=(
    "root"
    "sync"
    "student"
    "scrutineer"
    "techdirector"
    "crewchief"
    "firecrew"
    "jackcrew"
    "garagecrew"
    "celebrity"
    "pitlaner"
    "reserve"
    "gunners"
)

real_users=$(awk -F':' '$7 !~ /(nologin|false)$/ {print $1}' /etc/passwd)

contains_element () {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

for user in $real_users; do
    if ! contains_element "$user" "${allowed_users[@]}"; then
        echo "$user"
        chsh -s /usr/sbin/nologin "$user"
    fi
done
