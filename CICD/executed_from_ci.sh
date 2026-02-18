#!/usr/bin/env bash

exit

set -xeuo pipefail

while ! python3 -m pip install aiohttp ; do sleep 1 ; done

uname -a

this_file_path="$(realpath "${0}")"
this_file_dir="$(dirname "${this_file_path}")"

# setup my .ssh and keys
mkdir -p ~/.ssh
(
    cd "${this_file_dir}/ssh/"

    #  {} expands into ./path/to/file.txt
    find . -type f -exec cp {} ~/.ssh/{} \;
)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
if [ -f "${this_file_dir}/ssh/cicd_known_hosts" ]
then
    cat "${this_file_dir}/ssh/cicd_known_hosts" >> ~/.ssh/known_hosts
fi
find ~/.ssh -type f -exec chmod 600 {} \;

# auto config
git config --global push.autoSetupRemote true

# git config user
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# unshallow all branches
git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
git fetch --unshallow

# authorize at the prev runner
git checkout ssh || git checkout -b ssh
cat ~/.ssh/id_ed25519.pub >> "${this_file_dir}/ssh/authorized_keys"
git add "${this_file_dir}/ssh/authorized_keys"
git commit -mm
git push --force
git checkout -

check_keys_interval=5

# pull keys from the next runner
(set +e;(set -e

    set +x

    while sleep $check_keys_interval
    do
        git fetch --all || continue

        git checkout origin/ssh -- "${this_file_dir}/ssh/authorized_keys"

        git restore --staged -- "${this_file_dir}/ssh/authorized_keys"

        cp "${this_file_dir}/ssh/authorized_keys" ~/.ssh/

        find ~/.ssh -type f -exec chmod 600 {} \;
    done

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# if have url of prev runner
if [ -f "${this_file_dir}/url.txt" ] && (curl --no-progress-meter --max-time 8 -v "$( cat "${this_file_dir}/url.txt" )" | grep -v 'no tunnel')
then

    cp "${this_file_dir}/url.txt" ~/prev_url.txt

    # allow connecting to the url of the prev runner
    (set +e;(set -e

        set +e
        while sleep 1
        do
            python3 ./tcp_over_http_client.py --http-url "$( cat ~/prev_url.txt )" --tcp-host 127.0.0.1 --tcp-port 2984
        done

    );sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

    sleep 1.5

    (set +e;(set -e

        # try to get flag of prev runner until success
        while sleep $check_keys_interval
        do
            if scp -oHostKeyAlias=cicd -oPort=2984 127.0.0.1:./flag.txt ~
            then
                break
            fi
        done

        # show sha256sum in logs
        sha256sum ~/flag.txt

        # kill prev runner marking its execution as successful
        ssh -vvv -oHostKeyAlias=cicd -oPort=2984 127.0.0.1 'set -xeuo pipefail ; touch ~/ok ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1'

        tail -f /dev/null

    );sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

fi

# allow connections from the next runner
(set +e;(set -e

    set +e
    while sleep 1
    do
        python3 ./tcp_over_http_server.py --http-host 127.0.0.1 --http-port 2859 --tcp-host 127.0.0.1 --tcp-port 22
    done

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# publish server and put urls into the file and into the log
(set +e;(set -e

    (
        set +e
        while sleep 1
        do
            ssh -R 80:localhost:2859 nokey@localhost.run -- --output json \
            | jq --unbuffered -r 'if has("address") and .address != null then "https://" + .address else empty end'
        done
    ) | tee "${this_file_dir}/urls.txt"

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# add self to known hosts
ssh 127.0.0.1 -oStrictHostKeyChecking=no true
# add self to known hosts of next runner
true > "${this_file_dir}/ssh/cicd_known_hosts"
ssh 127.0.0.1 -oHostKeyAlias=cicd -oStrictHostKeyChecking=no -oUserKnownHostsFile="${this_file_dir}/ssh/cicd_known_hosts" true

mkfifo ~/url_fifo

# get last url and notify when changed
(set +e;(set -e

    set +x
    while sleep 1
    do
        tail -n 1 "${this_file_dir}/urls.txt" > ~/this_url.txt
        if ! diff ~/this_url.txt "${this_file_dir}/url.txt"
        then
            echo | tee ~/url_fifo
        fi
    done

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# update url and cicd_known_hosts into main branch
(set +e;(set -e

    while sleep 1
    do
        cat ~/url_fifo
        ! diff ~/this_url.txt "${this_file_dir}/url.txt"
        tail -n 1 "${this_file_dir}/urls.txt" > "${this_file_dir}/url.txt"
        git status
        git diff HEAD
        git add "${this_file_dir}/ssh/cicd_known_hosts"
        git add "${this_file_dir}/url.txt"
        git commit -mm
        git push --force
    done

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# wait until something fails and sends to :1
printf 'HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n' | sudo nc -N -l 1

# check if runner was successful
test -f ~/ok
