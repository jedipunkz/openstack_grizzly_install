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
