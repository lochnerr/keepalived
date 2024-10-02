#!/bin/sh

# run-keepalive-tests.sh: Run the keepalive compose file setting up the environment, if necessary.

if [ "$(id -u)" != "0" ]; then
	echo "Must be root!"
	exit 1
fi

if grep ^ip_vs /proc/modules >/dev/null 2>&1 ; then
	echo "Info: ip_vs is already loaded!"
else
	echo "Info: Loading module ip_vs."
	modprobe ip_vs
fi

if [ "$(cat /proc/sys/net/ipv4/ip_nonlocal_bind)" = "1" ]; then
	echo "Info: net.ipv4.ip_nonlocal_bind is already set."
else
	echo "Info: Setting /proc/sys/net/ipv4/ip_nonlocal_bind to 1."
	echo 1 >/proc/sys/net/ipv4/ip_nonlocal_bind
fi

podman build -t lochnerr/keepalived .

podman volume rm -f keepalived_unittest
podman compose -f docker-compose.test.yml up
podman compose -f docker-compose.test.yml down
podman volume rm -f keepalived_unittest
