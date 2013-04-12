# --------------------------------------------------------------------------------------
# check environment
# --------------------------------------------------------------------------------------
function check_env() {
    if [[ -x $(which lsb_release 2>/dev/null) ]]; then
        CODENAME=$(lsb_release -c -s)
        if [[ $CODENAME != "raring" ]]; then
            echo "This code was tested on precise and quantal only."
            exit 1
        fi
    else
        echo "You can run this code on Ubuntu OS only."
        exit 1
    fi
    export CODENAME
}

# --------------------------------------------------------------------------------------
# check os vendor
# --------------------------------------------------------------------------------------
function check_os() {
    VENDOR=$(lsb_release -i -s)
    export VENDER
}

function check_codename() {
    VENDOR=$(lsb_release -c -s)
    export CODENAME
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
