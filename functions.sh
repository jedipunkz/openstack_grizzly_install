# --------------------------------------------------------------------------------------
# check os vendor
# --------------------------------------------------------------------------------------
function check_os() {
    VENDOR=$(lsb_release -i -s)
    echo $VENDER
}

# --------------------------------------------------------------------------------------
# check os codename
# --------------------------------------------------------------------------------------
function check_codename() {
    CODENAME=$(lsb_release -c -s)
    echo $CODENAME
}

# --------------------------------------------------------------------------------------
# get field function
# --------------------------------------------------------------------------------------
function get_field() {
    while read data; do
        if [ "$1" -lt 0 ]; then
            field="(\$(NF$1))"
        else
            field="\$$(($1 + 1))"
        fi
        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
    done
}

# --------------------------------------------------------------------------------------
# package installation function
# --------------------------------------------------------------------------------------
function install_package() {
    apt-get -y install "$@"
}

# --------------------------------------------------------------------------------------
# restart function
# --------------------------------------------------------------------------------------
function restart_service() {
    check_os
    if [[ "$VENDOR" = "Ubuntu" ]]; then
        sudo /usr/bin/service $1 restart
    elif [[ "$VENDOR" = "Debian" ]]; then
        sudo /usr/sbin/service $1 restart
    else
        echo "We does not support your distribution."
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# restart function
# --------------------------------------------------------------------------------------
function start_service() {
    check_os
    if [[ "$VENDOR" = "Ubuntu" ]]; then
        sudo /usr/bin/service $1 start
    elif [[ "$VENDOR" = "Debian" ]]; then
        sudo /usr/sbin/service $1 start
    else
        echo "We does not support your distribution."
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# stop function
# --------------------------------------------------------------------------------------
function stop_service() {
    check_os
    if [[ "$VENDOR" = "Ubuntu" ]]; then
        sudo /usr/bin/service $1 stop
    elif [[ "$VENDOR" = "Debian" ]]; then
        sudo /usr/sbin/service $1 stop
    else
        echo "We does not support your distribution."
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# print syntax
# --------------------------------------------------------------------------------------
function print_syntax() {
    cat ./usage
    exit 1
}

# --------------------------------------------------------------------------------------
# check parameter
# --------------------------------------------------------------------------------------
function check_para() {
    if [ ! "$1" ]; then
        echo "This paramter $1 is not available."
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# check network interface which you login
# --------------------------------------------------------------------------------------
function check_interface() {
    if [ "$2" = "allinone" ]; then
        MESSAGE="in all in one node, You have to login via management network."
    elif [ "$2" = "controller" ]; then
        MESSAGE="in controller node, You have to login via public network."
    elif [ "$2" = "network" ]; then
        MESSAGE="in compute node, You have to login via management network."
    else
        echo "\$2 should be 'allinone' or 'controller' or 'network'."
        exit 1
    fi

    printf '\033[0;32m%s\033[0m\n' "Please check network interface which you login with."
    printf '\033[0;32m%s\033[0m\n' "If you login to host via wrong interaface, you will lost network connectivity."
    echo -e "\e[33m $MESSAGE \e[m"
    echo -e -n "\e[33m Do you login to this IP address : $1 ? (y/n) \e[m"

    read YN

    if [ $YN = 'Y' ] || [ $YN = 'y' ]; then
        echo "OK."
    elif [ $YN = 'N' ] || [ $YN = 'n' ]; then
        printf '\033[0;34m%s\033[0m\n' "I can not proceed this script. You will lost connectivity."
        printf '\033[0;34m%s\033[0m\n' "Check network interface to login."
        exit 1
    else
        printf '\033[0;34m%s\033[0m\n' "Please answer y/n"
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# setup configuration file
# --------------------------------------------------------------------------------------
function setconf() {
    local i=1
    for element in "$@"
    do
        IFS=':', read -ra array <<< "$element"
        if [[ "${array[0]}" = "infile" ]]; then
            local input=${array[1]}
            continue
        elif [[ "${array[0]}" = "outfile" ]]; then
            local output=${array[1]}
            continue
        fi
        para[$i]="-e s#${array[0]}#${array[1]}#g "
        para+=${para[$i]}
        i=$(($i + 1))
    done

    if [[ "$output" ]]; then
        cp $output ${output}.org
        sed $para $input > $output
    else
        cp $input ${input}.org
        sed -i $para $input
    fi
}
