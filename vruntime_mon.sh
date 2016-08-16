#!/bin/bash
#
# Print out 'init' process's children and/or
# Monitor one of above processes
#

SELF_NAME=$(basename $0)
VERSION=0.1

#Store all init children processes
INIT_CHILDREN_PID=""

print_usage() {
    (
        echo "$SELF_NAME version $VERSION -- Shows all children processes of 'init'"
        echo ""
        echo "usage:"
        echo "    $SELF_NAME <options>"
        echo "    options:"
        echo "        -m, --monitor    Display all the 'init' children processes and select one to monitor"
        echo "        -s, --show       Display all the 'init' children processes"
        echo "        -p, --pid <pid>  Monitor specified process and print out the latest 'se.vruntime'"
        echo "        -h, --help       Show this help"
        echo "        -v, --version    Show version number"
    ) >&2
    exit 0
}

log() {
    echo -e "$(date): $1" 2>&1
    #syslog has its own timestamp already
    logger -t ${SELF_NAME} "$1"
}

error_log() {
    log "ERROR- $1"
}

is_digit() {
    local RE='^[0-9]+$'
    if [[ $1 =~ $RE ]] ; then
        return 0
    fi
    return 1
}

get_proc_name() {
    local PID=$1
    grep "Name:" /proc/$PID/status 2>/dev/null| awk '{for (i=2; i<=NF; i++) print $i}'
}

show_init_children() {
    #To have more clean message in syslog, save temporary result
    #to a tmp file and then printout to syslog once
    local TMP_FILE="/tmp/${SELF_NAME}.$$.tmp"
    echo "List of 'init' children processes" >>${TMP_FILE}
    echo "---------------------------------" >>${TMP_FILE}
    echo -e "PID\t\tNAME" >>${TMP_FILE}
    echo -e "---\t\t----" >>${TMP_FILE}
    
    local OUTPUT=$(ls /proc)
    for PID in ${OUTPUT}; do
        #skip non-number files
        if ! is_digit $PID; then
            continue
        fi
        
        local STATUS_FILE="/proc/$PID/status"
        local PARENT_PID=$(grep "PPid:" ${STATUS_FILE} 2>/dev/null | awk '{print $2}')
        local STATUS=(${PIPESTATUS[@]})
        
        #Conditions checked: no error, parent pid found and it's init's child
        if [ $? -eq 0 ] && [ "${STATUS[0]}" = "0" ] &&
        [ -n "${PARENT_PID}" ] && [ ${PARENT_PID} -eq 1 ]; then
            local PROC_NAME=$(get_proc_name $PID)
            #The process could die before or between 'grep'
            if [ -n "${PROC_NAME}" ]; then
                INIT_CHILDREN_PID="${INIT_CHILDREN_PID[@]} $PID"
                echo -e "$PID\t\t${PROC_NAME}" >>${TMP_FILE}
            fi
        fi
    done
    
    log "$(cat $TMP_FILE)"
    rm -f $TMP_FILE
}

monitor_vruntime() {
    local PID=$1
    if ! is_digit $PID; then
        error_log "'$PID' is not a valid PID."
        exit 1
    fi
    local SCHED_FILE="/proc/$PID/sched"
    if [ ! -f $SCHED_FILE ]; then
        error_log "process '$PID' does not exist or has already gone."
        exit 1
    fi
    
    local PROC_NAME=$(get_proc_name $PID)
    
    log "Monitoring process '${PROC_NAME}' (PID: $PID)..."
    
    local VRUN_VALUE="unknown"
    local INTERVAL="2" #TODO: parametrizate the interval?
    #TODO: handle the case when PID is wrapped around and
    #reused by other process within the interval
    while [ -f $SCHED_FILE ]; do
        VRUN_VALUE=$(grep 'se.vruntime' $SCHED_FILE 2>/dev/null| awk '{print $3}')
        echo -en "\r"
        echo -n "se.vruntime: $VRUN_VALUE"
        sleep $INTERVAL
    done
    echo -e "\r"
    
    log "Process '${PROC_NAME}' (PID: ${PID}) died, lastest 'se.vruntime' value is: ${VRUN_VALUE}"
    
}

is_valid_input() {
    
    if ! is_digit $1; then
        echo "Input is not a valid PID"
        return 1
    fi
    #check if the input PID is in the init children list
    for PID in ${INIT_CHILDREN_PID}; do
        if [ $1 -eq $PID ]; then
            return 0
        fi
    done
    echo "Selected PID is not in above init children list."
    return 1
}

show_and_monitor() {
    
    show_init_children
    
    local PROMPT_MSG="Please select one PID of above process PIDs to monitor:"
    echo ""
    echo "$PROMPT_MSG"
    read PID
    while ! is_valid_input $PID; do
        echo "Input again:"
        read PID
    done
    echo ""
    log "PID '$PID' is chosen to monitor"
    monitor_vruntime $PID
    
}

main() {
    # Parse command line
    case $1 in
        -m|--monitor)
            show_and_monitor
        ;;
        -s|--show)
            if [ "$2" ]; then
                print_usage
            fi
            show_init_children
        ;;
        -p|--pid)
            if [ ! "$2" ]; then
                print_usage
            fi
            monitor_vruntime "$2"
        ;;
        -h|--help)
            print_usage
        ;;
        *)
            #Default to display init's children and select one to monitor
            show_and_monitor
        ;;
    esac
}

main "$@"

