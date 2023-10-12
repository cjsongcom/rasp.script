#!/bin/bash

SCRIPT=`realpath -s $0`
SCRIPTPATH=`dirname ${SCRIPT}`
SCRIPTNAME=`basename ${SCRIPT}`

cd ${SCRIPTPATH}


TEMP_FAN_ON=$1
TEMP_FAN_OFF=$2


if [ -z "${TEMP_FAN_ON}" ] || \
   [ -z "${TEMP_FAN_OFF}" ]; then
  TEMP_FAN_ON=55
  TEMP_FAN_OFF=40
fi



eval LOG_FILE_PATH="~/fan-oper.log"

# get by 'sudo uhubctl'
USB_HUB_FOR_FAN="1-1.1.2"


function add_log {

  local _oper=$1
  local _msg=$2

  local _prefix=$(date +"%y%m%d %H:%M:%S")

  (
    echo "[${_prefix}][${_oper}] ${_msg}" >> ${LOG_FILE_PATH}
  )
}


function get_rasp_temp {
  local _rst=0

  _rst=$(vcgencmd measure_temp 2>&1)

  if [ $? -ne 0 ]; then
    echo -n "${_rst}"
    return 1
  fi

  _rst=$(echo -n "${_rst}" | cut -d '=' -f2 | cut -d '.' -f1)
  echo -n "${_rst}"

  return 0
}


function check_fan_action {
	
  local _cur_temp=$1
  local _cur_usbhub_pwr_st=$2

  local _re='^[0-9]+$'

  if ! [[ ${_cur_temp} =~ ${_re} ]] ; then
    return 1
  fi

  local _num_temp=$((${_cur_temp}))

  # 0: turn off fan
  # 1: turn on fan
  # 2: do nothing
  local _rst_fan_oper=0


  # fan usb power is already on
  if [ ${_cur_usbhub_pwr_st} -eq 1 ]; then
    if [ ${_num_temp} -lt ${TEMP_FAN_ON} ]; then
      if [ ${_num_temp} -gt ${TEMP_FAN_OFF} ]; then
	_rst_fan_oper=2
	echo -n ${_rst_fan_oper}

	return 0
      fi
    fi
  fi


  # current temp is less for turning on fan
  if [ ${_num_temp} -lt ${TEMP_FAN_ON} ]; then
    # turn off fan
    _rst_fan_oper=0

    # fan usbhub power is off
    if [ ${_cur_usbhub_pwr_st} -eq 0 ]; then
      _rst_fan_oper=2
    fi

  else
    # turn on fan
    _rst_fan_oper=1

    if [ ${_cur_usbhub_pwr_st} -eq 1 ]; then
      _rst_fan_oper=2
    fi

  fi

  echo -n ${_rst_fan_oper}

  return 0
}


function get_usbhub_power_status {
  local _hub_path=$1
  local _exec_rst=$(sudo uhubctl -l "${_hub_path}" 2>/dev/null)

  if [ $? -ne 0 ] || \
     [ -z "${_exec_rst}" ]; then
    return 1
  fi

  local _has_off=$(echo -n "${_exec_rst}" | grep "off" 2>/dev/null)

  if [ -z "${_has_off}" ]; then
    echo -n 1
  else
    echo -n 0
  fi

  return 0
}



#
# entry
#

# 0:turn off, 1:turn on, 2:do nothing
fan_oper=0
force_turn_on_fan=0

cur_usbhub_pwr_st=$(get_usbhub_power_status "${USB_HUB_FOR_FAN}")

if [ $? -ne 0 ]; then
  add_log "FATAL" "FAILED TO GET usbhub power status, path=${USB_HUB_FOR_FAN}"

  # assume usbhub power status is on
  cur_usbhub_pwr_st=1
fi

cur_temp=$(get_rasp_temp)

if [ $? -ne 0 ]; then
  add_log "FATAL" "FAILED TO EXECUTE  vcgencmd measure_temp, reason=${cur_temp}"
 
  # force turning on fan
  force_turn_on_fan=1

else
  fan_oper=$(check_fan_action ${cur_temp} ${cur_usbhub_pwr_st})

  if [ $? -ne 0 ]; then
    # force turn on fan
    force_turn_on_fan=1   
  fi

fi


#
# fan operation
#

COMM_MSG="CUR_TEMP=${cur_temp}, CUR_USB_HUB_PWR_ST=${cur_usbhub_pwr_st}, TEMP_FAN_ON=${TEMP_FAN_ON}, TEMP_FAN_OFF=${TEMP_FAN_OFF}"


if [ ${force_turn_on_fan} -eq 1 ]; then
  #sudo uhubctl -l ${USB_HUB_FOR_FAN} -d 2 -w 2 -a 1
  add_log "FAN_ON" "force turn on fan, invalid powerstatus, temp,  ${COMM_MSG}"

else

  if [ ${fan_oper} -eq 2 ]; then
    # do nothing
    add_log "DO_NOTHING" "${COMM_MSG}"

  else

    if [ ${fan_oper} -eq 1 ]; then
      sudo uhubctl -l ${USB_HUB_FOR_FAN} -d 2 -w 2 -a 1  1>/dev/null
      add_log "FAN_ON" "${COMM_MSG}"

    else
      sudo uhubctl -l ${USB_HUB_FOR_FAN} -d 2 -w 2 -a 0	 1>/dev/null   
      add_log "FAN_OFF" "${COMM_MSG}"

    fi

  fi

fi
