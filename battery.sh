#!/bin/bash

settings_dir=$(dirname $0)
settings_file="$settings_dir/settings"

function get_voltage() {
	voltage=$(ioreg -l -n AppleSmartBattery -r | grep "\"Voltage\" =" | awk '{ print $3/1000 }' | tr ',' '.')
	echo "$voltage"
}

function is_charging_enabled() {
	hex_status=$($settings_dir/smc -k CH0B -r | awk '{print $4}' | sed s:\)::)
	[[ "$hex_status" == "00" ]] && return
	false
}

function enable_charging() {
	echo "🔌🔋 Enabling battery charging"
	sudo $settings_dir/smc -k CH0B -w 00
	sudo $settings_dir/smc -k CH0C -w 00
}

function disable_charging() {
	echo "🔌🪫 Disabling battery charging"
	sudo $settings_dir/smc -k CH0B -w 02
	sudo $settings_dir/smc -k CH0C -w 02
}


function is_valid_voltage() {
	if [[ ! "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		echo "Invalid voltage: \"$1\""
		return 1
	fi
	if (($(echo "$1 < 11.1" | bc -l) || $(echo "$1 > 12.6" | bc -l))); then
		echo "Voltage out of range: ${1}V"
		return 1
	fi
	return 0
}

function status() {
	voltage=$(get_voltage)
	echo "Current Voltage: ${voltage}V"
}

action=$1
p1=$2
p2=$3

if [[ "$action" == "status" ]]; then
	status
fi

if [[ "$action" == "set" ]]; then
	if ! is_valid_voltage "$p1"; then exit 1; fi
	if ! is_valid_voltage "$p2"; then exit 1; fi
	if (($(echo "$p1 >= $p2" | bc -l))); then
		echo "First voltage must be lower than second"
		exit 1
	fi
	
	echo "$p1 $p2" > $settings_file
	echo "Set voltage between ${p1}V and ${p2}V and saved to $settings_file"
fi

if [[ "$action" == "enable" ]]; then
	enable_charging
fi

if [[ "$action" == "disable" ]]; then
	disable_charging
fi

if [[ "$action" == "maintain" ]]; then
	echo "Maintaining voltage"
	while true; do
		settings=$(cat $settings_file 2>/dev/null)
		if [[ ! $settings ]]; then
			echo "No voltage set"
			exit 1
		fi
		
		u0=$(get_voltage)
		u1=$(echo $settings | awk '{print $1}')
		u2=$(echo $settings | awk '{print $2}')
		echo "$u0 $u1 $u2"
		
		is_charging=$(! is_charging_enabled)$?
		echo $is_charging
		if (($(echo "$u0 < $u1" | bc -l))) && [ $is_charging = 0 ]; then
			enable_charging
		elif (($(echo "$u0 >= $u2" | bc -l))) && [ $is_charging = 1 ]; then
			disable_charging
		fi
		
		sleep 3
	done
fi
