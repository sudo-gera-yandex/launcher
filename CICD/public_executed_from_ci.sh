#!/usr/bin/env bash

set -xeuo pipefail

(set +e;(set -e

    while ! python3 -m pip install aiohttp ; do sleep 1 ; done

    uname -a

    this_file_path="$(realpath "${0}")"
    this_file_dir="$(dirname "${this_file_path}")"

    # setup my .ssh and keys
    mkdir -p ~/.ssh
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q
    (
        cd "${this_file_dir}/ssh/"

        #  {} expands into ./path/to/file.txt
        find . -type f -exec cp {} ~/.ssh/{} \;
    )
    cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
    find ~/.ssh -type f -exec chmod 600 {} \;

    # auto push
    git config --global push.autoSetupRemote true

    # git config user
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"

    # unshallow all branches
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --unshallow

    # prepare for committing url and server key
    public_runner_hash="$(git rev-parse HEAD)"
    git checkout ssh || git checkout -b ssh
    git reset --hard "$public_runner_hash"

    # allow connections from the private runner
    (set +e;(set -e

        set +e
        while sleep 1
        do
            python3 "${this_file_dir}/tcp_over_http_server.py" --http-host 127.0.0.1 --http-port 2859 --tcp-host 127.0.0.1 --tcp-port 22
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
    touch ~/url_enabled

    # get last url and notify when changed
    (set +e;(set -e

        set +x
        while sleep 1
        do
            tail -n 1 "${this_file_dir}/urls.txt" > ~/this_url.txt
            if ! diff ~/this_url.txt "${this_file_dir}/url.txt"
            then
                if curl --no-progress-meter --max-time 8 -v "$(cat ~/this_url.txt)"
                then
                    echo | tee ~/url_fifo
                fi
            fi
        done

    );sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

    # push url.txt, cicd_known_hosts and authorized_keys into ssh branch
    (set +e;(set -e

        while [ -f ~/url_enabled ]
        do
            cat ~/url_fifo
            ! diff ~/this_url.txt "${this_file_dir}/url.txt"
            tail -n 1 "${this_file_dir}/urls.txt" > "${this_file_dir}/url.txt"
            git add "${this_file_dir}/ssh/cicd_known_hosts"
            git add "${this_file_dir}/ssh/authorized_keys"
            git add "${this_file_dir}/url.txt"
            git commit -mm
            git push --force
        done

        tail -f /dev/null

    );sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

    tail -f /dev/null

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# run not longer than 5 hours
(set +e;(set -e

    sleep 18000
    echo -n 'done sleeping for 18000 at'
    date

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# wait until something fails and sends to :1
printf 'HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n' | sudo nc -N -l 1

# check if runner was successful
test -f ~/ok
