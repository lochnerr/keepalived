#!/bin/sh

set -e

# run-sut.sh: Script to run system unit tests.

init_keepalive_daemon() {

  # Create a script to run in the background to kill the keepalive daemon when signaled.
  cat >/usr/local/bin/wait_for_shutdown.sh <<-__EOD__
	#!/bin/sh
	while : ; do
	   sleep 5s
	   if [ -e /sut/stop.sig ]; then
             echo "Shutdown invoked..."
	     if [ -e /var/run/keepalived.pid ]; then
	       echo "Killing daemon."
	       kill "\$(cat /var/run/keepalived.pid)" || :
	     else
	       echo "Warning: No daemon to kill."
	     fi
	     echo "Exiting."
	     exit 0
	   fi
	done
	__EOD__

  chmod +x /usr/local/bin/wait_for_shutdown.sh
  
  # Clear any leftover signal files on the sut volume.
  rm -f /sut/start.sig
  rm -f /sut/stop.sig
  echo "Command signals cleared."
  
  echo "Starting the wait_for_shutdown.sh script in the background."
  /usr/local/bin/wait_for_shutdown.sh &
  
  # Start the nginx server.
  echo "Starting nginx."
  nginx

  # Create the keepalived config template.
  cat >/tmp/keepalived.conf <<-__EOF__
	global_defs {
	  default_interface eth0
	  # The script user must be root in order to see messages from the notify script when running with docker loggng.
	  script_user root
	  enable_script_security
	  # The following enables checking that when in unicast mode, the
	  # source address of a VRRP packet is one of our unicast peers.
	  ###check_unicast_src
	}

	vrrp_instance VI_1 {
	  interface eth0

	  state BACKUP
	  virtual_router_id 51
	  priority PRIORITY
	  nopreempt

	  unicast_peer {
	    192.168.1.10
	    192.168.1.11
	    192.168.1.12
	  }

	  virtual_ipaddress {
	    192.168.1.231
	  }

	  authentication {
	    auth_type PASS
	    auth_pass d0cker
	  }

	  notify "/usr/local/bin/keepalived-test-notify.sh"
	}
	__EOF__

  # Modify the config template for this container.
  MODE="BACKUP"
  if [ "$NAME" = "kad12" ]; then
    IP="192.168.1.12"
    PRIORITY="50"
  elif [ "$NAME" = "kad11" ]; then
    IP="192.168.1.11"
    PRIORITY="100"
  else
    IP="192.168.1.10"
    PRIORITY="150"
    MODE="MASTER"
  fi
  cp /tmp/keepalived.conf temp.conf
  sed -i \
    -e "s/BACKUP/${MODE}/" \
    -e "s/PRIORITY/${PRIORITY}/" \
    -e "/${IP}/d" \
    temp.conf
  if [ "${MODE}" = "MASTER" ]; then
    # nopreempt does not work with initial state MASTER.
    sed -i -e "/^.*nopreempt/d" temp.conf
  fi
  mv -f temp.conf /etc/keepalived/keepalived.conf

  # Write the ID (IP address) of this container for nginx to serve.
  echo "$IP" >/usr/share/nginx/html/id.txt

  # Trap signals.
  SIGNALS_RESTART="HUP"
  SIGNALS_SHUTDOWN="INT KILL TERM STOP RTMIN+3"
  trap "restart"   $SIGNALS_RESTART
  trap "shutdown"  $SIGNALS_SHUTDOWN

  # Check for request
  while : ; do
    sleep 5s
    if [ -e /sut/start.sig ]; then
      echo "Startup invoked..."
      detail="--log-detail "
      detail=""
      keepalived -f /etc/keepalived/keepalived.conf --dont-fork --log-console $detail || :
      echo "keepalived exited."
      break
    fi
  done
}

NAME="$(hostname -s)"
if [ "$NAME" != "sut" ]; then
  echo "Daemon container: ${NAME}."
  init_keepalive_daemon
  exit 0
fi

# Set the status to okay.
rc="0"

echo "System Unit Test container: ${NAME}."

run_test() {

  host="$1"
  echo "Running test for $host..."
  # Start the keepalive daemon.
  echo "start" >/$host/start.sig
  # Wait for it to take control of the address.
  sleep 20
  # Determine which host is active.
  active="$(curl -s http://192.168.1.231/id.txt || :)"
  if [ "${active}" = "$2" ]; then
    echo "Testing ${host}, active host is correct: ${active}."
  else
    [ -z "$active" ] && active="unknown"
    echo "Testing ${host}, active host is incorrect: ${active}, expected ${2}."
    rc="1"
  fi
  sleep 3
  echo "Exiting test for $host."
}

# Sleep to let the daemon containers to clear their command files.
sleep 8

run_test kad12 192.168.1.12
run_test kad11 192.168.1.12
run_test kad10 192.168.1.10

echo "Terminatind daemon containers."

# Shutdown the daemon containers.
echo "shutdown" >/kad12/stop.sig
echo "shutdown" >/kad11/stop.sig
echo "shutdown" >/kad10/stop.sig

# Let the daemon containers finish.
sleep 10

echo "INFO: Service $NAME exiting with rc = ${rc}."
exit $rc

