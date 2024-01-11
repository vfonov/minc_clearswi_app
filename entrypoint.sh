#! /bin/sh
# TODO: figure out file permission madness

#### SETUP USER ####
if [ "$(id -u)" = "0" ]; then
# setup fake user
USER_ID=${LOCAL_USER_ID:-1000}
USER_GID=${LOCAL_USER_GID:-1000}
echo "Starting with $USER_ID:$USER_GID"
groupadd -f -g $USER_GID user
useradd --shell /bin/bash -u $USER_ID -g $USER_GID -o -c "" -M -d /tmp user
export HOME=/tmp
else
echo "Running as $(id -u)"
fi
####

${JULIA_PATH}/bin/julia --project=/env /env/clearswi_minc.jl $@
