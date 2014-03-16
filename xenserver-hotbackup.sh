#!/bin/bash
#  Xenserver hotbackup script
#  Copyright (C) 2013  dharry <foo.kishi@gmail.com>
# Author: dharry <foo.kishi at gmail.com>
#
# Usage:
# 1. install xenserver-hotbackup.sh
#        % cp -p xenserver-hotbackup.sh /path/to/xenserver-hotbackup.sh
# 2. set file permission
#        % chmod +x xenserver-hotbackup.sh
# 3. edit cfg
#        % vi xenserver-hotbackup.cfg
# 4. set crontab (example)
#        % 10 1 * * * /path/to/xenserver-hotbackup.sh -f /path/to/xenserver-hotbackup.cfg
#

export LANG=C

# defaults setting
uuid=
vmname=
xenserver=
xe_user=
xe_password=
vm_backup_base_dir=
vm_backup_dir=
compression=true #true/false
vm_backup_rotation_count=4
email_log=0
email_server=localhost
email_server_port=25
email_delay_interval=1
email_to=
email_xmailer=
email_from=
workdir=
workdir_debug=0
xvaname=
config=
logdir=
logfile=
logger=true
debug=true

#xenserver environment
XE_EXTRA_ARGS=

# templary 
workdir=${workdir:-"/tmp/.xsb$$work"}
email_log_header=${workdir}/email.header
email_log_output=${workdir}/email.log
email_log_content=${workdir}/email.content
email_finalLog=

# misc
suffix=`date "+%Y-%m-%d_%H-%M-%S"`
mycommand=`basename $0`
myhost=`hostname -s`
myuser=${USER:=root}
s_time=
e_time=


abspath()
{
  local _path=$1
  which readlink > /dev/null 2>&1
  if [ $? = 0 ]; then
    readlink  -m $_path
  else
    echo $(cd $(dirname $_path); pwd)/$(basename $_path)
  fi
}

dateTag()
{
  date "+%Y-%m-%d %H:%M:%S"
}

errLog() {
    time=`dateTag`
    local str="${@}"
    local message="error; ${str}"
    email_log=1

    [ ${debug}  = "true" ] &&  echo "${time} -- ${message}"
    [ ${logger} = "true" ] && logger "err" "${message}"
    echo "${time} -- ${message}" >> $logfile
}

infoLog() {
    time=`dateTag`
    local str="${@}"
    local message="info: ${str}"

    [ ${debug}  = "true" ] &&  echo "${time} -- ${message}"
    [ ${logger} = "true" ] && logger "info" "${message}"
    echo "${time} -- ${message}" >> $logfile 
}

confLog() {
    time=`dateTag`
    local str="${@}"
    local message="CONFIG - ${str}"
    infoLog "${message}"
}

startTimer() {
  s_time=`date +%s`
}

endTimer() {
    e_time=`date +%s`
    duration=$(echo $((e_time - s_time)))

    #calculate overall completion time
    if [[ ${duration} -le 60 ]] ; then
        echo "Backup Duration: ${duration} Seconds"
    else
        echo "Backup Duration: $(awk 'BEGIN{ printf "%.2f\n", '${duration}'/60}') Minutes"
    fi
}

# usage
usage()
{
  _exit_code=$1
   cat <<EOF
Usage: $0 [-f config.cfg ]
EOF

  exit ${_exit_code}
}

checkCommand()
{
  tag="checkCommand()"
  which xe >/dev/null 2>&1 ||    { echo "${tag}: xe command not in path!"; return 1; }
  xe vm-list > /dev/null 2>&1 || { echo "${tag}: xe command faild!"; return 1; }
  if [ $email_log != 0 ]
  then 
    which nc >/dev/null 2>&1 ||  { echo "${tag}: nc command not in path!"; return 1; }
  fi
}

checkVariables()
{
  # Necessary variables
  tag="checkVariables()"
  [ "x${uuid}" = "x"  ]         &&  { echo "${tag}: uuid not set!"; return 1; }
  [ "x${vmname}" = "x" ]        &&  { echo "${tag}: vmname not set!"; return 1; }
  [ "x${vm_backup_base_dir}" = "x" ] &&  { echo "${tag}: vm_backup_base_dir not set!"; return 1; }

  # maybe xenserver?
  if [ "x${xenserver}" = "x" ]; then
    xenserver=localhost
    for path in /opt/xensource/bin/xapi /etc/xapi.conf
    do
      [  -f "${path}" ] || xenserver=""
    done
  fi

  [ "x${xenserver}" = "x" ] && { echo "${tag}: xenserver not set!"; return 1; }
  
  if [ "${xenserver}" != "localhost" ]
  then
     [ "x${xe_user}"     = "x" ]  &&  { echo "${tag}: xe_user not set!"; return 1; }
     [ "x${xe_password}" = "x" ]  &&  { echo "${tag}: xe_password not set!"; return 1; }
  fi

  return 0
}

setVariables()
{
  if [ ${email_log} != 0 ]; then
    email_server=${email_server:=localhost}
    email_server_port=${email_server_port:=25}
    email_delay_interval=${email_delay_interval:=3}
    email_to=${email_to:=$myuser@$myhost}
    email_from=${email_from:=$myuser@$myhost}
    email_xmailer=${email_xmailer:=$mycommand}
    workdir=${workdir:="/tmp/.xsb$$work"}
    workdir_debug=0
  fi

  compression=${compression:=true}
  vm_backup_rotation_count=${vm_backup_rotation_count:=0}
  vm_backup_dir=${vm_backup_base_dir}/${vmname}
  xvaname=${vm_backup_dir}/${suffix}.xva
  logdir=${vm_backup_dir}/logs
  logfile=${logdir}/${suffix}.log
  
  [ -d "${vm_backup_dir}" ] || mkdir -p  "${vm_backup_dir}" > /dev/null 2>&1
  [ -d "${logdir}" ]        || mkdir -p  "${logdir}"        > /dev/null 2>&1

  if [ "x${xenserver}" != x"localhost" ]
  then
    export XE_EXTRA_ARGS="server=${xenserver},port=443,username=${xe_user},password=${xe_password}"
  fi

  return 0
}

printConfig()
{
  for e in uuid vmname xenserver xe_user xe_password vm_backup_base_dir vm_backup_dir compression \
           vm_backup_rotation_count email_log email_server email_server_port email_delay_interval email_to \
           email_xmailer email_from workdir workdir_debug xvaname config logdir logfile logger debug  \
           email_log_header email_log_output email_log_content
  do
     [ $e = "xe_password" ] && continue
     eval "val=`echo \\$$e`"
     case $e in
       vm_backup_base_dir|vm_backup_dir|workdir|logdir|logfile) val=`abspath $val`;;
       email_log_header|email_log_output|email_log_content) val=`abspath $val`;;
       *) ;;
     esac

     confLog "${e} = ${val}"
  done
}

finalLog()
{
  local _status=$1
  if [ $_status = 0 ]; then
    email_finalLog="INFO: VM(s) backup has been succeeded!"
  else
    email_finalLog="ERROR: Error(s) occurred when backing up VM(s)!\nPlease investigate the cause of the failure."
  fi
}

buildHeaders()
{
    echo -ne "HELO ${myhost}\r\n"                > "${email_log_header}"
    echo -ne "MAIL FROM: <${email_from}>\r\n"   >> "${email_log_header}"
    echo -ne "RCPT TO: <${email_to}>\r\n"       >> "${email_log_header}"
    echo -ne "DATA\r\n"                         >> "${email_log_header}"
    echo -ne "From: ${email_from}\r\n"          >> "${email_log_header}"
    echo -ne "To: ${email_to}\r\n"              >> "${email_log_header}"
    echo -ne "Subject: [VM Backup] XenServer xva - ${vmname} \r\n" >> "${email_log_header}"
    echo -ne "Date: `date`\r\n"                 >> "${email_log_header}"
    echo -ne "X-Mailer: ${email_xmailer} \r\n"  >> "${email_log_header}"
    echo -en "\r\n"                             >> "${email_log_header}"
    
    echo -en ".\r\n"                            >> "${email_log_output}"
    echo -en "quit\r\n"                         >> "${email_log_output}"

    cat "${email_log_header}"                    > "${email_log_content}"
    echo -en "${email_finalLog}\r\n"            >> "${email_log_content}"
    echo -en "\r\n"                             >> "${email_log_content}"
    cat "${logfile}"                            >> "${email_log_content}"
    cat "${email_log_output}"                   >> "${email_log_content}"
}


sendMail()
{
  #close email message
  if [ "${email_log}" -eq 1 ] ; then
    mkdir -p ${workdir} > /dev/null 2>&1
    buildHeaders 
    nc -i ${email_delay_interval} ${email_server} ${email_server_port} < ${email_log_content} > /dev/null 2>&1
    echo " ${nc_bin} -i ${email_delay_interval} ${email_server} ${email_server_port}" > /tmp/b.txt
    if [ $? != 0 ] ; then
      errLog "failed to email log output to ${email_server}:${email_server_port} to ${email_to}"
    fi
    \rm -fr ${workdir} > /dev/null 2>&1
  fi
}

vmBackup()
{
  # create snapshot
  labelname=snapshot-${suffix}
  snap_uuid=`xe vm-snapshot uuid=${uuid} new-name-label=${labelname}`
  if [ $? = 0 ]; then
    infoLog "Creating Snapshot \"${labelname}\" for $vmname"
  else
    errLog  "Creating Snapshot \"${labelname}\" for $vmname"
    return 1
  fi
  #trap "xe vm-uninstall uuid="${snap_uuid}" force=true > /dev/null 2>&1" ERR

  # export xva
  xe template-param-set is-a-template=false uuid=${snap_uuid}
  xe vm-export compress=${compression} vm=${snap_uuid} filename=${xvaname} > /dev/null 2>&1
  if [ $? = 0 ]; then
    infoLog "Export to file \"${labelname}\" for $vmname"
  else
    errLog  "Export to file \"${labelname}\" for $vmname"
    xe vm-uninstall uuid="${snap_uuid}" force=true > /dev/null 2>&1
    return 1
  fi

  # remove snapshot
  xe vm-uninstall uuid=${snap_uuid} force=true > /dev/null 2>&1
  if [ $? = 0 ]; then
    infoLog "Remove Snapshot \"${labelname}\" for $vmname"
  else
    errLog  "Remove Snapshot \"${labelname}\" for $vmname"
    return 1
  fi
 
  # for your safety
  sleep 2
}

vmRotate()
{
  [ x${vm_backup_dir} = "x" ]            && return 0
  [ x${vm_backup_rotation_count} = "x" ] && return 0
  cnt=${vm_backup_rotation_count}
  for xva in `ls -t ${vm_backup_dir}/*xva`
  do
     if [ $cnt -ne 0 ]; then
       cnt=$((cnt-1))
       continue
     fi
     if [ -f "${xva}" ] ; then
       chmod 644 "${xva}"
       \rm -f "${xva}" > /dev/null 2>&1
       if [ $? = 0 ]; then
         infoLog "Remove Backup .xva file \"${xva}\" for $vmname"
       else
         errLog  "Remove Backup .xva file \"${xva}\" for $vmname"
         return 1
       fi
     fi
  done
}


##
## main
##

[ $# -eq 0 ] && usage 1
startTimer

while getopts hc:d:f:n:u: opt
do
    case $opt in
        h) usage 0;;
        d) backup_dir="${OPTARG}"  ;;
        c) compression="${OPTARG}" ;;
        n) vmname=${OPTARG}  ;;
        u) uuid="${OPTARG}" ;;
        f) config="${OPTARG}";;
        *) echo "invalid argument."; exit 1;;
    esac
done

[ "x${config}" = "x" ] && usage 1
[ -f "${config}" ]    || { echo "${config} is not found"; exit 1; }

source ${config}

checkVariables || exit 1
setVariables   || exit 1
checkCommand   || exit 1

echo "[$logfile]" >> $logfile
infoLog "============================== ${mycommand} LOG START =============================="
infoLog "Initiate backup for ${vmname} "

# config log
printConfig

# export .xva
vmBackup

# vmBackup message
status=$?
finalLog $status

if [ $status = 0 ]; then
  # rotate .xva
  vmRotate
fi

message=`endTimer`
infoLog "${message}"

if [ $status = 0 ]; then
  infoLog "Successfully completed backup for ${vmname}"
  infoLog "============================== ${mycommand} LOG END ================================"
else
  errLog  "failed completed backup for ${vmname}"
  errLog  "============================== ${mycommand} LOG END ================================"
fi

# notice mail
[ $email_log = 1 ] && sendMail

# exit
[ $status = 0 ] || exit 1
exit 0 

