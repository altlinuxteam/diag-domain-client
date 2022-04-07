#!/bin/bash
set -euo pipefail

. shell-terminfo

terminfo_init

verbose=1

msg_fail()
{
    echo -n $*:" ["
    color_text "FAIL" red
    echo "]"
}

msg_warn()
{
    echo -n $*:" ["
    color_text "WARN" yellow
    echo "]"
}

msg_done()
{
    echo -n $*:" ["
    color_text "DONE" green
    echo "]"
}

run()
{
    local func="$1"
    local msg_error=msg_fail
    [ "${func#test_}" = "$func" ] ||
        msg_error=msg_warn
    if test -z $verbose; then
        $func >/dev/null 2>&1
    else
        echo "--- $func ---"
        $func
    fi && (test -z $verbose || echo ---; msg_done "$2") || (test -z $verbose || echo ---; $msg_error "$2")
    test -z $verbose || echo ---
    test -z $verbose || echo
}

check_hostnamectl()
{
    local static_host="$(hostnamectl --static)"
    local transient_host="$(hostname)"
    hostnamectl
    test "$static_host" = "$transient_host"
}

test_hostname()
{
    local host=`hostname`
    test "$host" != "${host/.}"
}

run check_hostnamectl "Check hostnamectl"
run test_hostname "Test hostname is FQDN"
