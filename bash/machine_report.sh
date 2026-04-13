`#!/bin/bash
#========================================================================
# M A C H I N E R E P O R T
#========================================================================
# SYNOPSIS
#       ./machine-report ${IP} ${OPTION}
#
# DESCRIPTION
#      Machine Report - Bash Script
#      The One and Only Almighty Script for checking Linux machine issues
#========================================================================
# IMPLEMENTATION
#-    version         Machine-Report 1.0.5
#-    code            Bash Script
#-    authors         Yuna Son
#-    copyright       Copyright (c) Yuna Son
#========================================================================
# History
#    2023-06-28 Started by Yuna Son & Julian T.G.
#    2024-03-15 Released v1.0.0 by Yuna Son
#    2024-11-28 Updated C-state check
#========================================================================
# M A C H I N E R E P O R T
#========================================================================

# Setting variables =======================================================
SSH_ARGS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
SH="ssh $SSH_ARGS"
SH_HOST="root@${1}"
IP=${1}
Green='\033[0;32m'
Yellow='\033[1;33m'
Red='\033[1;31m'
NC='\033[0m'
opt=${2}
day=$(date | awk '{print $3}')
month=$(date | awk '{print $2}')
host=$(who am i | awk '{print $1}')
dir="/home/${host}"
readonly SERVICES=("ssh" "cron" "rsyslog")

# Main condition ==========================================================

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "[I] LOOK BELOW FOR HOW TO USE"
        echo "./machine_report IP_Adress Option"
        echo " "
        echo "Default is running all commands"
	echo " -h, --help HELP!!!"
        exit 255
fi

# Check if the machine is running Windows
kernel_name=$($SH $SH_HOST "uname -s")
if [[ $kernel_name == *CYGWIN_NT* ]]; then
  echo -e "${Red}This is Windows machine. This script is not supported on Windows machines${NC}"
  exit 1
fi

if [[ ! "$IP" =~ ((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$ ]]; then 
#	(([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5]))$ ]]; then
        printf $Red"Please insert correct IP format 8.8.8.8"$NC
	echo " "
        printf $Yellow"Please type -h or --help to see how it works"$NC
	echo " "
        exit 255
fi

# Main Functions ===========================================================

#CPU Frequency Check
fre_check() {
    count=$($SH $SH_HOST "cat /proc/cpuinfo | grep 'physical id' | sort -u | wc -l")
    
    if [ $count -gt 1 ]; then
        freq=$($SH $SH_HOST "cpupower monitor -m Mperf | awk 'NR>2 {sum += \$6; count++} END {printf \"%d\", sum / count}'")
    else
        freq=$($SH $SH_HOST "cpupower monitor -m Mperf | awk 'NR>2 {sum += \$4; count++} END {printf \"%d\", sum / count}'")
    fi

    max_freq=$($SH $SH_HOST "cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq" 2>&1)
    min_freq=$($SH $SH_HOST "cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq" 2>&1)

    # Check if output contains "No such file or directory"
    if [[ $max_freq == *"No such file or directory"* || $min_freq == *"No such file or directory"* ]]; then
        echo "$max_freq"
        echo "$min_freq"
        echo -e "${Red}WARNING: Power management is not enabled in the OS, please raise with DC!${NC}"
        return 1
    fi

    max_freq_mhz=$(($max_freq / 1000))
    min_freq_mhz=$(($min_freq / 1000))

    echo "Current Frequency: " $freq "Mhz"
    echo "Maximum Frequency: " $max_freq_mhz "Mhz"
    echo "Minimum Frequency: " $min_freq_mhz "Mhz"
    echo " "

    if [ -z "$freq" ]; then
        echo "Unknown frequency"
    else
        freq_percent=$(($freq * 100 / $max_freq_mhz))

        # Set frequency % threshold here
        if [ $freq_percent -lt 80 ]; then
            echo -e "\e[31mWARNING: CPU frequency is low ($freq_percent%)\e[0m"
            status="0"
        else
            echo -e "\e[32mCPU frequency is normal ($freq_percent%)\e[0m"
            status="1"
        fi
    fi
}

#CPU Temperature Check
temp_check()
{
        # Get the CPU temperature and calculate the average temperature in Celsius degree unit
        temps=$($SH $SH_HOST "cat /sys/class/thermal/thermal_zone*/temp")

        # Initialize the sum variable
        sum=0

        # Loop through the temperature values and add them to the sum variable
        for temp in $temps; do
            sum=$((sum + temp))
        done

        # Calculate the average temperature and convert it to Celsius degrees
        num_temps=$(echo $temps | wc -w)
        avg_temp=$((sum / (num_temps * 1000)))

        # Extract the decimal part from the result
        decimal=$((sum % (num_temps * 1000)))
        if [[ $decimal -ge 500 ]]; then
            avg_temp=$((avg_temp + 1))
        fi

        # Get the CPU idle time
        # idle=$(mpstat 1 1 | awk '/Average:/ {printf "%.2f\n", 100-$NF}')

        # Execute the sensors and ipmitool commands for CPU temperature information
        sensors_output=$($SH $SH_HOST "sensors coretemp-isa-0000")
        ipmitool_output=$($SH $SH_HOST "ipmitool sensor | grep -iE '(fan)'")

        # Print the sensors and ipmitool output
        echo "$sensors_output"
        echo ""
        echo "$ipmitool_output"
        echo ""

        # Print the results
        # echo "CPU Idle Time: $idle%"

        if [[ $avg_temp -gt 80 ]]; then
            echo -e "WARNING: Average CPU Temperature: \033[31m$avg_temp °C\033[0m"
        else
            echo -e "Average CPU Temperature: \033[32m$avg_temp °C\033[0m"
        fi
}

#BIOS Check
turbo_mode_check()
{
        #Print the turbo boost settings
        turbo_status=$($SH $SH_HOST "rdmsr -a 0x1a0 -f 38:38 | awk '{ sum+=\$1 } END { print sum/NR }'")
        if [ "$turbo_status" == 0 ]; then
            echo -e "${Green}Turbo Boost Enabled${NC}"
        else
            echo -e "${Red}WARNING: Turbo Boost Disabled, please raise with DC!${NC}"
        fi
}

hyper_thread_check()
{
        thread=$($SH $SH_HOST "dmidecode -t processor | grep Count")
        core_count=$(echo "$thread" | grep 'Core Count' | awk '{print $3}')
        thread_count=$(echo "$thread" | grep 'Thread Count' | awk '{print $3}')
        if [ "$core_count" == "$thread_count" ];then
                echo -e "${Red}WARNING: Hyper Threading Disabled${NC}"
        else
                echo -e "${Green}Hyper Threading Enabled${NC}"
        fi
}

c_state_check()
{
    idle_driver=$($SH $SH_HOST "cat /sys/devices/system/cpu/cpuidle/current_driver")
    c_state=$($SH $SH_HOST "cat /sys/module/intel_idle/parameters/max_cstate")

    #driver: intel_idle, max_cstate = 1 / driver: none, max_cstate = 0

    if [ "$idle_driver" = "none" ]; then
        if [ "$c_state" -eq "0" ] || [ "$c_state" -eq "1" ]; then
            echo -e "${Green}C-State is disabled${NC}"
        elif [ "$c_state" -ge "2" ]; then
            echo -e "${Red}WARNING: C-State is enabled - Must be Disabled${NC} "
            echo -e "${Red}Max C-state Value: $c_state${NC}"
        fi
    elif [ "$idle_driver" = "acpi_idle" ]; then
        if [ "$c_state" -eq "0" ]; then
            echo -e "${Red}WARNING: C-State is enabled - Must be Disabled${NC}"
            echo -e "${Red}Max C-state Value: $c_state${NC}"
        elif [ "$c_state" -eq "1" ]; then
            echo -e "${Green}C-State is disabled${NC}"
        elif [ "$c_state" -ge "2" ]; then
            echo -e "${Red}WARNING: C-State is enabled - Must be Disabled${NC}"
            echo -e "${Red}Max C-state Value: $c_state${NC}"
        fi
    elif [ "$idle_driver" = "intel_idle" ]; then
        if [ "$c_state" -eq "0" ] || [ "$c_state" -eq "1" ]; then
            echo -e "${Green}C-State is disabled${NC}"
        elif [ "$c_state" -ge "2" ]; then
            echo -e "${Red}WARNING: C-State is enabled - Must be Disabled${NC}"
            echo -e "${Red}Max C-state Value: $c_state${NC}"
        fi
    else
        echo "unknown driver" 
    fi
}

driver_check()
{
             c_gov=$($SH $SH_HOST "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
             driver=$($SH $SH_HOST "cpupower frequency-info | grep driver | awk '{print \$2}'")
         if [ "$driver" = "" ]; then
         echo -e "${Red}WARNING: unknown driver${NC}"
         echo "Scaling Driver: $driver (active BIOS profile: ${c_gov})"
         elif [ "$driver" = "or" ]; then
              driver="unknown"
         echo "Scaling Driver: $driver (active BIOS profile: ${c_gov})"
         else
         echo "Scaling Driver: $driver (active BIOS profile: ${c_gov})"
         fi
}

#CPU High Usage Process Check
cpu_process_check()
{
        # Get the list of PIDs of processes using more than 95% of CPU
        top_procs=$($SH $SH_HOST "top -b -n 1 | tail -n +8 | awk '{if(\$9>95) print \$1}'")

        # Check if any top process exists
        if [ -z "$top_procs" ]; then
            echo "No process using more than 95% of CPU"
        else
            echo -e "\033[31mWARNING: Processes using more than 95% of CPU:\033[0m"

            # Iterate over each top process and show information using ps command
            for pid in $top_procs
            do
              echo -e "PID: \033[34m$pid\033[0m"
              process_info=$($SH $SH_HOST "ps -p $pid -o %cpu,%mem,cmd")
              echo -e "$process_info"
              echo ""
            done
        fi
}

#CPU Core Check
cpu_core_check()
{
        # Get the current CPU governor
        lscpu_out=$($SH $SH_HOST "lscpu")
        echo "$lscpu_out" | grep 'Model name' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        echo "$lscpu_out" | grep 'CPU(s)' | grep -v 'NUMA node0 CPU(s)'
        echo "$lscpu_out" | grep 'Core(s) per socket'
}

#Load average Check
load_average_check ()
{
    uptime_output=$($SH $SH_HOST "uptime")
    load_average=$(echo "$uptime_output" | awk -F 'load average: ' '{print $2}' | awk -F ', ' '{print $1}')
    core_count=$($SH $SH_HOST "grep -c processor /proc/cpuinfo")
    threshold=$(echo "$core_count * 0.7" | bc -l)

    if (( $(echo "$load_average > $threshold" | bc -l) )); then
        echo -e "${Red}WARNING: Load average is above 70%!${NC}"
        echo -e "$uptime_output"
    else
        echo -e "$uptime_output"
   fi
}

#RAM Usage
ram_usage ()
{
    ram_usage_check=$($SH $SH_HOST "free -h")
    echo -e "$ram_usage_check"
}

#RAM Size
ram_size ()
{
    ram_size_check=$($SH $SH_HOST "dmidecode -t 17 | grep -E 'Size:|Locator:' | grep -v 'Bank Locator:' | paste - - -d ' '")
    echo -e "$ram_size_check"
}

#RAM Check
#Check if there is RAM error in syslog or dmesg
ram_err_check()
{
    echo "Starting the check in syslog for RAM errors..."

    # Checking '/var/log/syslog' for MC0 (a possible RAM error)
    ramerr=$($SH $SH_HOST "grep MC0 /var/log/syslog | grep -i 'unknown\|CE'")

    if [ -n "$ramerr" ]; then
     echo -e "${Red}WARNING: Found the following RAM errors in syslog:${NC}"
     echo -e "$ramerr"
    else
     echo -e "No RAM errors in the syslog"
     echo ""
    fi

    # Checking 'dmesg' for MC0 (a possible RAM error)
    dmesg1=$($SH $SH_HOST "dmesg -T | grep MC0 | grep -iE 'unknown|CE' | grep -v 'Giving out device to module'")
   if [ -z "$dmesg1" ]; then
      echo -e "No RAM error in dmesg"
      echo ""
    else
      echo -e "${Red}WARNING: Found the following RAM errors in dmesg:${NC}"
        echo -e "$dmesg1"
        echo ""
        fi

    # Checking '/var/log/syslog' for other possible errors
     echo "Checking dmesg for other possible errors..."
    dmesg2=$($SH $SH_HOST "dmesg -l err -T | grep -Ev 'SGX disabled by BIOS|Timed out waiting for FW-initiated reset|ISH: hw start failed|kauditd hold queue overflow'")
    if [ -z "$dmesg2" ]; then
        echo -e "No other errors in dmesg"
        echo ""
    else
     echo -e "${Red}WARNING: Found the following errors in dmesg:${NC} it may not be related to RAM"
     echo -e "$dmesg2"
     echo ""
    fi
}

#Disk Check
disk_err_check()
{
#Check if there is disk i/o error or read only error in dmesg
      echo "checking disk i/o and read-only file system error..."
    diskerr=$($SH $SH_HOST "dmesg | grep -iE 'i/o error|read-only file system'")

    if [ -n "$diskerr" ]; then
        echo -e "$diskerr"
        echo -e "${Red}WARNING: Found disk error in dmesg${NC}"
    else
        echo -e "No disk error in dmesg"
    fi
}

#Disk Space
disk_space ()
{
    disk_space=$($SH $SH_HOST "df -h | grep -v '/dev/loop'")
    usage=$(echo "$disk_space" | awk '{print $5}' | grep -o '[0-9]*' | sort -nr | head -1)

    if [[ -n "$usage" ]] && [[ "$usage" -gt 80 ]]; then
    echo -e "${Red}WARNING: Disk usage is above 80%!${NC}"
    echo -e "$disk_space"
    else
    echo -e "$disk_space"
    fi
}

disk_write_check()
{
        echo "This test will write 1GB of data to the disk and measure the write speed"
        echo "This test will take about 1 minute to complete"
        echo "Please wait..."

        # get the write speed
        write_speed=$($SH $SH_HOST "dd if=/dev/zero of=/tmp/testfile bs=1G count=1 oflag=direct 2>&1 | tail -n 1 | awk '{print \$8\" \"\$9\" \"\$10\" \"\$11}'")
        write_speed_value=$(echo "$write_speed" | awk '{print $3}')

        # print the write speed
        echo " "
        echo "Write speed: $write_speed"

        # Warning if the write speed is below 50 MB/s
        if [[ $write_speed == *"MB/s"* ]]; then
            write_speed=$(echo $write_speed | grep -o '[0-9]*')
          if (( $(echo "$write_speed_value < 50" | bc -l) )); then
            echo -e "${Red}WARNING: Write speed is below 50 MB/s!${NC}"
            fi
        fi
        # remove the file
        $SH $SH_HOST "rm -f /tmp/testfile"
}

check_smart_raw_values() {
    local smart_output="$1"
    local raw_values
    raw_values=$(echo "$smart_output" | awk '{print $10}' | grep -v 'RAW_VALUE')
    for value in $raw_values; do
        if [[ $value != 0 ]]; then
            echo -e "${Red}WARNING: Disk has errors, please raise with DC!${NC}"
            return
        fi
    done
}

#SMART Test
smrtclt_test ()
{
    echo "checking smartclt test result..."
    disks=$($SH $SH_HOST "lsblk -d -n -o NAME | grep '^sd'")

    # Loop through the disks and check for issues
    for disk in $disks; do
        echo -e "<Checking disk $disk>"

        test_result=$($SH $SH_HOST "smartctl -H /dev/$disk")

        # Check if the result contains the specific error message
        if [[ $test_result == *"Smartctl open device: /dev/$disk failed: DELL or MegaRaid controller, please try adding '-d megaraid,N'"* ]]; then
            echo -e $test_result
            echo -e "${Green} This is not failure, detected DELL or MegaRaid controller. Running alternative command. ${NC}"
            smart_test=$($SH $SH_HOST "smartctl -a -d megaraid,0 /dev/$disk | grep -E 'Model|Serial|ID#|Raw_Read_Error_Rate|Reallocated_Sector_Ct|Retired_Block_Count|Spin_Retry_Count|Pending_Sector|Offline_Uncorrectable|Current_Pending_Sector|Uncorrectable_Sector|Soft_Read_Error_Rate|Seek_Error_Rate|UDMA_CRC_Error_Count'")
            echo -e "$smart_test"

            # Check if the disk is a Seagate model for DELL or MegaRaid controller
            model=$(echo "$smart_test" | grep 'Model Family:' | awk -F: '{print $2}' | xargs)
            device=$(echo "$smart_test" | grep 'Device Model:' | awk -F: '{print $2}' | xargs)
            #check if model is seagate or device starts with ST
            if [[ $model == *"Seagate"* ]] || [[ $device == ST[0-9][0-9][0-9][0-9]* ]]; then
             echo -e "${Green} This is a Seagate model. You can ignore Raw_Read_Error_Rate and Seek_Error_Rate${NC}"

             smart_test=$($SH $SH_HOST "smartctl -a /dev/$disk | grep -E 'Reallocated_Sector_Ct|Spin_Retry_Count|Current_Pending_Sector|Offline_Uncorrectable|UDMA_CRC_Error_Count'")
             check_smart_raw_values "$smart_test"
            else
             check_smart_raw_values "$smart_test"
            fi
        else
            # Otherwise, use the original command
            smart_test=$($SH $SH_HOST "smartctl -a /dev/$disk | grep -E 'Model|Serial|ID#|Raw_Read_Error_Rate|Reallocated_Sector_Ct|Spin_Retry_Count|Pending_Sector|Offline_Uncorrectable|Current_Pending_Sector|Uncorrectable_Sector|Soft_Read_Error_Rate|Seek_Error_Rate|UDMA_CRC_Error_Count'")
            echo -e "$smart_test"

            # Check if the disk is a Seagate model for normal controllers
            model=$(echo "$smart_test" | grep 'Model Family:' | awk -F: '{print $2}' | xargs)
            device=$(echo "$smart_test" | grep 'Device Model:' | awk -F: '{print $2}' | xargs)
            #check if model is seagate or device starts with ST
            if [[ $model == *"Seagate"* ]] || [[ $device == ST[0-9][0-9][0-9][0-9]* ]]; then
             echo -e "${Green} This is a Seagate model. You can ignore Raw_Read_Error_Rate and Seek_Error_Rate${NC}"

             smart_test=$($SH $SH_HOST "smartctl -a /dev/$disk | grep -E 'Reallocated_Sector_Ct|Spin_Retry_Count|Current_Pending_Sector|Offline_Uncorrectable|UDMA_CRC_Error_Count'")
             check_smart_raw_values "$smart_test"
            else
             check_smart_raw_values "$smart_test"
            fi
        fi
        echo ""
        echo -e "$test_result"
    done
}

#Check if there is an issue with SATA cable
sata_cable_check()
{
    sata_errors=$($SH $SH_HOST "dmesg | grep -E 'ata.*(ABRT|UNC|ERR|error)'")

    if [ -n "$sata_errors" ]; then
      echo -e "${Red}WARNING: SATA errors found:${NC}"
      echo -e "$sata_errors"
    else
      echo -e "No SATA error"
    fi
}

#Check NIC card error
run_ssh_cmd() {
    echo $($SH $SH_HOST "$1")
}

filter_result() {
    echo $(run_ssh_cmd "ethtool -S $1 | grep $2 | awk -F: '{print \$NF}'" | tr -d ' ')
}

calculate_error_percent() {
    if [[ $1 =~ ^[0-9]+ && $2 =~ ^[0-9]+ && $2 -ne 0 ]]; then
        echo $(echo "scale=2; $1 * 10000 / $2" | bc)
    else
        echo 0
    fi
}

nic_err_check() {
    interfaces=$(run_ssh_cmd "ifconfig -a | grep -oE '^[a-zA-Z0-9]+'")
    errors_found=false

    for interface in $interfaces; do
        if [[ $interface != "docker0" && $interface != "lo" ]]; then
            stats=$($SH $SH_HOST "ethtool -S $interface 2>/dev/null")

            rx_err_packets=$(echo "$stats" | grep rx_errors | awk -F: '{print $NF}' | tr -d ' ')
            tx_err_packets=$(echo "$stats" | grep tx_errors | awk -F: '{print $NF}' | tr -d ' ')
            rx_packets=$(echo "$stats" | grep rx_packets | awk -F: '{print $NF}' | tr -d ' ')
            tx_packets=$(echo "$stats" | grep tx_packets | awk -F: '{print $NF}' | tr -d ' ')
            [ -z "$rx_packets" ] && rx_packets=$(echo "$stats" | grep rx_mcast_packets | awk -F: '{print $NF}' | tr -d ' ')
            [ -z "$tx_packets" ] && tx_packets=$(echo "$stats" | grep tx_mcast_packets | awk -F: '{print $NF}' | tr -d ' ')

            rx_err_percent=$(calculate_error_percent $rx_err_packets $rx_packets)
            tx_err_percent=$(calculate_error_percent $tx_err_packets $tx_packets)

            if (( $(echo "$rx_err_percent > 1" | bc -l) )) || (( $(echo "$tx_err_percent > 1" | bc -l) )); then
                echo -e "${Red}WARNING: NIC errors found for interface $interface:${NC}"
                echo "$stats" | grep -E '(rx_errors|tx_errors): [1-9][0-9]*$'
                errors_found=true
            else
                if ! $errors_found; then
                    echo ""
                    echo -e "No NIC error found for $interface"
                fi
            fi
        fi
    done
    if ! $errors_found; then
        echo ""
        echo "No NIC errors found on any interfaces."
    fi
}

#CMOS battery Check
cmos_battery ()
{
    battery_check=$($SH $SH_HOST "cat /proc/driver/rtc | grep batt_status")
    battery_status=$(echo "$battery_check" | grep -o 'batt_status[[:space:]]*:[[:space:]]*[^[:space:]]*' | cut -d ':' -f 2 | tr -d ' ')

    if [[ "$battery_status" == "bad" ]]; then
      echo -e "${Red}WARNING: Low battery level detected!${NC}"
      echo -e "$battery_check"
    else
      echo -e "$battery_check"
    fi
}

#PSU Status Check
psu_status_check()
{
    ps_result=$($SH $SH_HOST "ipmitool sdr -- type 'Power Supply'")
    echo -e "checking PSU status..."
    echo -e "$ps_result"
    
   # Check if ipmitool is installed
    if [ -z "$ps_result" ]; then
       echo -e "ipmitool is not installed on this server."
       echo -e ""
   fi

   # Check if there is failure detected in PSU
    if [[ $ps_result == *"Fail"* ]]; then
        echo -e "${Red}WARNING: PSU failure detected!${NC}"
    fi
}

binary_check()
{
    any_inactive=false
    for service in "${SERVICES[@]}"; do
        status=$($SH $SH_HOST "systemctl is-active $service")
        if [ "$status" = "active" ]; then
            echo -e "${Green}${service}: ${status}${NC}"
        else
            echo -e "${Red}${service}: ${status}${NC}"
            any_inactive=true
        fi
    done

    if $any_inactive; then
        echo -e "${Red}WARNING: One or more services are not active, please check.${NC}"
    fi
}

# Sets the filename as the IP but converts . to - for the filename
    filename="${IP//./-}"

# Default will run full script and outputs below
if [ -z "$opt" ]; then
        # Define an array of checks
        declare -a checks=(
            "fre_check" 
            "temp_check"
            "turbo_mode_check"
            "hyper_thread_check"
            "c_state_check"
            "driver_check"
            "cpu_process_check"
            "cpu_core_check"
            "load_average_check"
            "ram_usage"
            "ram_size"
            "ram_err_check"
            "disk_err_check"
            "disk_space"
            "disk_write_check"
            "smrtclt_test"
            "sata_cable_check"
            "nic_err_check"
            "cmos_battery"
            "psu_status_check"
            "binary_check"
        )

        # Function to run each check in the background
        run_check() {
            check=$1
            output_file="${filename}_${check}_tmp.txt"
            $check > "$output_file"
        }

        # Run each check in the background
        for check in "${checks[@]}"; do
            run_check "$check" &
        done

        # Wait for all background jobs to finish
        wait

        # Display the output of each check
        echo "================================================================================"
        echo "[ ${IP} ]"
        echo "============================= CPU Frequency Check: ============================"
        echo ""
        cat "${filename}_fre_check_tmp.txt"
        echo ""
        echo "============================ CPU Temperature Check: ==========================="
        echo ""
        cat "${filename}_temp_check_tmp.txt"
        echo ""
        echo "=============================== CPU BIOS Check: ==============================="
        echo ""
        cat "${filename}_turbo_mode_check_tmp.txt"
        cat "${filename}_hyper_thread_check_tmp.txt"
        cat "${filename}_c_state_check_tmp.txt"
        cat "${filename}_driver_check_tmp.txt"
        echo ""
        echo "=========================== Load Average Check: ==============================="
        echo ""
        cat "${filename}_load_average_check_tmp.txt"
        echo ""
        echo "========================= CPU High Usage Process Check: ======================="
        echo ""
        cat "${filename}_cpu_process_check_tmp.txt"
        echo ""
        echo "=============================== CPU Core Check: ==============================="
        echo ""
        cat "${filename}_cpu_core_check_tmp.txt"
        echo ""
        echo "=============================== RAM Usage: ===================================="
        echo ""
        cat "${filename}_ram_usage_tmp.txt"
        echo ""
        echo "=============================== RAM Size: ====================================="
        echo ""
        cat "${filename}_ram_size_tmp.txt"
        echo ""
        echo "=============================== RAM Error: ===================================="
        echo ""
        cat "${filename}_ram_err_check_tmp.txt"
        echo ""
        echo "=============================== Disk Error: ==================================="
        echo ""
        cat "${filename}_disk_err_check_tmp.txt"
        echo ""
        echo "=============================== Disk Space: ==================================="
        echo ""
        cat "${filename}_disk_space_tmp.txt"
        echo ""
        echo "=============================== Disk Write: ==================================="
        echo ""
        cat "${filename}_disk_write_check_tmp.txt"
        echo ""
        echo "=============================== SMART Test: ==================================="
        echo ""
        cat "${filename}_smrtclt_test_tmp.txt"          
        echo ""
        echo "=============================== SATA Cable: ==================================="
        echo ""
        cat "${filename}_sata_cable_check_tmp.txt"
        echo ""
        echo "=============================== CMOS Battery: ================================="
        echo ""
        cat "${filename}_cmos_battery_tmp.txt"
        echo ""
        echo "=============================== NIC Error: ===================================="
        echo ""
        cat "${filename}_nic_err_check_tmp.txt"
        echo ""
        echo "=============================== PSU Status: ==================================="
        echo ""
        cat "${filename}_psu_status_check_tmp.txt"
        echo ""
        echo "================================ Binary Check: ================================"
        echo ""
        cat "${filename}_binary_check_tmp.txt"
        echo ""
        echo "=============================== TEST RESULT: ==================================="
        # display if there is any warning message in the output, print failed or passed and also print which test failed
        if grep -q "WARNING" "${filename}"_*_tmp.txt; then
            echo -e "RESULT: [${IP}] ${Red}FAILED${NC}"
            echo -e "Please check the above output for more details"
            echo ""
        else
            echo -e "RESULT: [${IP}] ${Green}PASSED${NC}"
            echo ""
        fi

        # Clean up temporary files
        rm "${filename}"_*_tmp.txt
fi`