#!/usr/bin/env bash

set -xeuo pipefail

(set +e;(set -e

    while ! python3 -m pip install aiohttp ; do sleep 1 ; done

    uname -a

    this_file_path="$(realpath "${0}")"
    this_file_dir="$(dirname "${this_file_path}")"

    this_repo_dir="$(git rev-parse --show-toplevel)"

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

    # setup account credentials
    cat "${this_file_dir}/.git-credentials" >> ~/.git-credentials
    chmod 600 ~/.git-credentials
    git config --global credential.helper store

    # push my public key into public repo
    (
        cd "${this_repo_dir}/../node-launcher-public"
        public_main_hash="$(git rev-parse HEAD)"
        git checkout runner || git checkout -b runner
        git reset --hard "$public_main_hash"
        cp ~/.ssh/authorized_keys "CICD/ssh/authorized_keys"
        git add CICD/ssh/authorized_keys
        git commit -mm
        git push --force
    )

    check_keys_interval=5

    # pull url and server key from the public repo
    while sleep $check_keys_interval
    do
        git -C "${this_repo_dir}/../node-launcher-public" fetch --all || continue

        git -C "${this_repo_dir}/../node-launcher-public" stash || true

        # check that branch exists on remote
        git -C "${this_repo_dir}/../node-launcher-public" rev-parse origin/ssh || continue

        git -C "${this_repo_dir}/../node-launcher-public" checkout origin/ssh -- "${this_repo_dir}/../node-launcher-public/CICD/ssh/authorized_keys"
        git -C "${this_repo_dir}/../node-launcher-public" checkout origin/ssh -- "${this_repo_dir}/../node-launcher-public/CICD/ssh/cicd_known_hosts"
        git -C "${this_repo_dir}/../node-launcher-public" checkout origin/ssh -- "${this_repo_dir}/../node-launcher-public/CICD/url.txt"

        git -C "${this_repo_dir}/../node-launcher-public" restore --staged    -- "${this_repo_dir}/../node-launcher-public/CICD"

        if diff ~/.ssh/authorized_keys                                           "${this_repo_dir}/../node-launcher-public/CICD/ssh/authorized_keys"
        then
            break
        fi
    done

    cat "${this_repo_dir}/../node-launcher-public/CICD/ssh/cicd_known_hosts" >> ~/.ssh/known_hosts
    find ~/.ssh -type f -exec chmod 600 {} \;

    # allow connecting to the url of the prev runner
    (set +e;(set -e

        set +e
        while sleep 1
        do
            python3 "${this_file_dir}/tcp_over_http_client.py" --http-url "$( cat "${this_repo_dir}/../node-launcher-public/CICD/url.txt" )" --tcp-host 127.0.0.1 --tcp-port 2984
        done

    );sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

    # connect and run starter
    (set +e;(set -e

        while sleep 5
        do
            if scp -oHostKeyAlias=cicd -oPort=2984 "${this_file_dir}/starter.sh" 127.0.0.1:.
            then
                break
            fi
        done

        ssh -oHostKeyAlias=cicd -oPort=2984 127.0.0.1 'rm ~/url_enabled && touch ~/ok && nohup ./starter.sh 1>starter.txt 2>starter.txt &'

        touch ~/ok

        ssh -oHostKeyAlias=cicd -oPort=2984 127.0.0.1 'tail -n 999999999 -f starter.txt'

    );sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

    tail -f /dev/null

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# run not longer than 100 sec
(set +e;(set -e

    sleep 45
    echo -n 'done sleeping for 45 at'
    date

);sleep 4 ; curl -v --max-time 1 --no-progress-meter 127.0.0.1:1)&

# wait until something fails and sends to :1
printf 'HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n' | sudo nc -N -l 1

# check if runner was successful
test -f ~/ok

