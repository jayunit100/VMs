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

function installOpenShift {
	cd /origin

     set -x
	echo "-- Starting build, memory:"
	free -mh
	# make clean build
	echo "Starting openshift"
	sudo /origin/_output/local/bin/linux/amd64/openshift start --public-master=localhost &> openshift.log &
	echo "-- Now starting as new user..."
	#oc logout
	#yes "j" | oc login
	echo "-- now checking who i am and creating project!"
	echo "sleeping to avoid openshift.local... kubeconfig missing error..."
	sleep 5
	sudo -u vagrant whoami
	sudo chmod +r /origin/openshift.local.config/master/openshift-registry.kubeconfig
	sudo chmod +r /origin/openshift.local.config/master/admin.kubeconfig
	echo "Creating registry.  Sleeping a while first..."
	sleep 1
	/origin/_output/local/bin/linux/amd64/oadm registry --create --credentials=/origin/openshift.local.config/master/openshift-registry.kubeconfig --config=/origin/openshift.local.config/master/admin.kubeconfig
	echo "now creating project"
	oc="/origin/_output/local/bin/linux/amd64/oc"

	# warning this project needs to be manually deleted after your first 'vagrant up', or it will persist even after destroying vms.
	# purge the openshift.local.etcd created on your host.
	sudo -u vagrant $oc login https://localhost:8443 -u=admin -p=admin --config=/origin/openshift.local.config/master/openshift-registry.kubeconfig
	#sudo -u vagrant $oc login localhost:8443 -u=admin -p=admin --config=/data/src/github.com/openshift/origin/openshift.local.config/master/openshift-registry.kubeconfig
	sudo -u vagrant $oc new-project project1 --config=/origin/openshift.local.config/master/openshift-registry.kubeconfig || true
	
	echo "Now starting the examples!!!"

	# Make for sure that admin can do things as user vagrant.
	sudo chmod 755 /origin/openshift.local.config/master/admin.kubeconfig
	sudo -u vagrant mkdir /home/vagrant/.kube/
	sudo -u vagrant cp /origin/openshift.local.config/master/admin.kubeconfig /home/vagrant/.kube/config
	sudo -u vagrant ls /home/vagrant/.kube/
	sudo -u vagrant $oc login https://localhost:8443 -u=admin -p=admin --insecure-skip-tls-verify=true --config=/home/vagrant/.kube/config && $oc --config=/home/vagrant/.kube/config create -f /origin/examples/image-streams/image-streams-centos7.json -n project1

	sudo -u vagrant $oc get nodes --config=/origin/openshift.local.config/master/admin.kubeconfig
}

cleanold
build
setup
installOpenShift