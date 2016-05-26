#!/bin/bash

function setup {

	set -euo pipefail
	IFS=$'\n\t'

	sed -i s/^Defaults.*requiretty/\#Defaults\ requiretty/g /etc/sudoers

	# patch incompatible with fail-over DNS setup
	SCRIPT='/etc/NetworkManager/dispatcher.d/fix-slow-dns'
	if [[ -f "${SCRIPT}" ]]; then
	    echo "Removing ${SCRIPT}..."
	    rm "${SCRIPT}"
	    sed -i -e '/^options.*$/d' /etc/resolv.conf
	fi
	unset SCRIPT

	if [ -f /usr/bin/generate_openshift_service ]
	then
	  sudo /usr/bin/generate_openshift_service
	fi
}

function cleanold {
    # Clean out all the etcd and certs and so on.
    # Otherwise we cant make the new image streams as the smoke test.
    # Speeds up the delete process by doing fast recursive delete
    (cd /origin/openshift.local.etcd && find . -type d -delete)
    (cd /origin/openshift.local.volumes && find . -type d -delete)
    (cd /origin/openshift.local.config && find . -type d -delete)

    sudo rm -rf /origin/openshift.local.config
    sudo rm -rf /origin/openshift.local.etcd
    sudo rm -rf /origin/openshift.local.volumes
}

function build {
    sudo yum install -y docker golang
    sudo systemctl restart docker
    cd /origin
    make clean build
}

cleanold
build
setup