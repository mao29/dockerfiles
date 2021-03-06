#!/bin/sh

function walg_conf_json() {
ifs=$IFS
json='{'
n=0
for name in $WALG_VARS
do
  if [ $n -gt 0 ]
  then
    sep=",\n\t"
  else
    sep="\n\t"
  fi
  eval value=\${$name}
#   re='^[0-9]+$'
#   if  [[ $value =~ $re ]] ; then
#     #echo "$value is number"
#     json="$json$sep\"$name\":$value"
#   else
    json="$json$sep\"$name\":\"$value\""
#   fi
#   echo $var=$value
  let n=$n+1
done
json="$json\n}\n"
echo  $json
}

set -x

if [ -z "$POSTGRES_logging_collector" ]; then POSTGRES_logging_collector=on; fi
if [ -z "$POSTGRES_log_directory" ]; then POSTGRES_log_directory=pg_log; fi
if [ -z "$POSTGRES_log_filename" ]; then POSTGRES_log_filename=\'postgresql-%u_%H.log\'; fi
if [ -z "$POSTGRES_log_rotation_age" ]; then POSTGRES_log_rotation_age=1h ;fi
if [ -z "$POSTGRES_log_rotation_size" ]; then POSTGRES_log_rotation_size=0; fi

for confVar in `echo ${!POSTGRES*}`
do
  confValue=${!confVar}
  key=${confVar:9}
  if [ "$confValue" ]
  then
    sedExp="$sedExp -e s|#$key.*=.*|$key.*=.*| -e s|^$key.*=.*|$key=$confValue|"
  fi
done
#echo "$sedExp"
ErrFile=/tmp/sed.log
ConfFile=/var/lib/pgsql/data/postgresql.conf
TmpConfFile=/tmp/postgresql.conf
sed $sedExp <$ConfFile >$TmpConfFile 2>$ErrFile;

if [ -s $ErrFile ]
then
  cat $ErrFile
else
  mv $TmpConfFile $ConfFile
fi

POSTGRES_PARAMS=''
if [ -n "$BACKUP_RESTORE" ]
then
  BACKUP_RESTORE_FILE="/var/lib/pgsql/data/BACKUP_RESTORE"
  OLD_BACKUP_RESTORE=
  if [ -f  $BACKUP_RESTORE_FILE ]
  then
    read OLD_BACKUP_RESTORE < $BACKUP_RESTORE_FILE
  fi
  if [ -n "$RESTORE_HOST" -a -n "$RESTORE_PASSWORD" -a "$BACKUP_RESTORE" != "$OLD_BACKUP_RESTORE" ]
  then
    if [ -z "$RESTORE_PORT" ]
    then
      export RESTORE_PORT=5432
    fi
    if [ -z "$RESTORE_USER" ]
    then
      export  RESTORE_USER='postgres'
    fi
    /bin/dumpRestoreAll.sh
    echo $BACKUP_RESTORE > $BACKUP_RESTORE_FILE
  else
    if [ "$BACKUP_RESTORE" == "$OLD_BACKUP_RESTORE" ]
    then
      echo "Режим бекапа BACKUP_RESTORE Повторный запуск сервиса с идентификатором $BACKUP_RESTORE. Бекап не производится"
    fi
    if [ -z "$RESTORE_HOST" ]
    then
      echo "Режим бекапа BACKUP_RESTORE Переменная RESTORE_HOST не определена. Бекап не производится"
    fi
    if [ -z "$RESTORE_PASSWORD" ]
    then
      echo "Режим бекапа BACKUP_RESTORE: Переменная RESTORE_PASSWORD не определена. Бекап не производится"
    fi
  fi
fi

if [ -n "$BACKUP_WALG" ]
then
  BACKUP_WALG_FILE="/var/lib/pgsql/data/BACKUP_WALG"
  OLD_BACKUP_WALG=
  if [ -f  $BACKUP_WALG_FILE ]
  then
    read OLD_BACKUP_WALG < $BACKUP_WALG_FILE
  fi
  if [ "$BACKUP_WALG" != "$OLD_BACKUP_WALG" ]
  then
    if [ -n "$WALG" -a -f "/etc/wal-g.d/server-$WALG.conf" ]
    then
      /bin/walgRestoreAll.sh
    else
      echo "Режим WALG=$WALG не поддержмивается"
    fi
  else
    if [ "$BACKUP_WALG" == "$OLD_BACKUP_WALG" ]
    then
      echo "Режим бекапа BACKUP_WALG. Повторный запуск сервиса с идентификатором $BACKUP_WALG. Бекап не производится"
    fi
  fi
fi

if [ -n "$WALG" -a -f "/etc/wal-g.d/server-$WALG.conf" ] # Включить режим архивирования WAL-G
then
  WALG_CONFFILE=~postgres/.walg.json
  . /etc/wal-g.d/server.conf
  . /etc/wal-g.d/server-$WALG.conf
    conf=`walg_conf_json`
    echo -ne $conf  > $WALG_CONFFILE
    chown postgres:postgres /bin/wal-g
    if [ -n "$WALG_FILE_PREFIX" ]
    then
      mkdir -p $WALG_FILE_PREFIX
      chown postgres:postgres $WALG_FILE_PREFIX
      chmod 777 $WALG_FILE_PREFIX
      ls -ld $WALG_FILE_PREFIX
    fi
    if [ -z "$WALG_PUSH_TIMEOUT" ]
    then
      WALG_PUSH_TIMEOUT=300
    fi
    while :;
    do
      su -s /bin/backup-push.sh postgres;
      su -s /bin/backup-delete.sh postgres;
      sleep $WALG_PUSH_TIMEOUT
    done &

    POSTGRES_PARAMS="-c archive_mode=on -c wal_level=replica -c archive_timeout=60 -c archive_command='/bin/wal-push.sh %p'"
#     POSTGRES_PARAMS="-c archive_mode=on -c wal_level=replica -c archive_timeout=60 -c archive_command='/bin/wal-push.sh %p'"
fi

exec su -c "/usr/bin/postgres -D /var/lib/pgsql/data $POSTGRES_PARAMS"  -s /bin/sh postgres


