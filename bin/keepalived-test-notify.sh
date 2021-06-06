#!/bin/bash

# for ANY state transition.
# "notify" script is called AFTER the
# notify_* script(s) and is executed
# with 3 arguments provided by keepalived
# (ie don't include parameters in the notify line).
# arguments
# $1 = "GROUP"|"INSTANCE"
# $2 = name of group or instance
# $3 = target state of transition
#     ("MASTER"|"BACKUP"|"FAULT")

TYPE=$1
NAME=$2
STATE=$3

echox() {
  if [ "$LOGTYPE" = "syslog" ]; then
    logger "$1"
  else
    echo "$1" > /proc/1/fd/1
  fi
}

case $STATE in
    "MASTER") echox "INFO: I'm the MASTER ($2)! Whup whup."
        exit 0
    ;;
    "BACKUP") echox "INFO: Ok, i'm just a backup ($2), great."
        exit 0
    ;;
    "FAULT")  echox "WARNING: Fault, what ?"
        exit 0
    ;;
    "STOP")  echox "INFO: Stopping!"
        exit 0
    ;;
    *)        echox "ERROR: Unknown state '$STATE'"
        exit 1
    ;;
esac
