#!/bin/bash
set -e

confFile=/etc/wal-g.d/server-"$WALG".conf

if [ ! -f $confFile ]
then
  echo "Storage configuration file $confFile does not exist"
  exit 1
fi


. /etc/wal-g.d/server.conf
. $confFile


/bin/wal-g delete retain FULL $WALG_FULL_RETAIN --confirm
