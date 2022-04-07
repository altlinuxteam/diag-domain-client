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

run_by_root()
{
    local msg=
    if test "$1" = '-m'; then
        shift
        msg="$1"
        shift
    fi
    if test `id -u` != 0; then
        echo -n "Running not by root, SKIP: "
        echo $*
    else
        test -z "$msg" ||
            echo -n "$msg: "
        $*
    fi
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

check_system_auth()
{
    local auth=$(/usr/sbin/control system-auth)
    echo "control system_auth: $auth"
    readlink -f /etc/pam.d/system-auth
    cat /etc/pam.d/system-auth
    test -n "$auth" -a "$auth" != "unknown"
}

test_domain_system_auth()
{
    local auth=$(/usr/sbin/control system-auth)
    test -n "$auth" -a "$auth" != "local"
}

check_krb5_conf_ccache()
{
    local ccache=$(/usr/sbin/control krb5-conf-ccache)
    echo "control krb5-conf-ccache: $ccache"
    test -n "$ccache" -a "$ccache" != "unknown"
}

test_keyring_krb5_conf_ccache()
{
    local ccache=$(/usr/sbin/control krb5-conf-ccache)
    test -n "$ccache" -a "$ccache" == "keyring"
}

check_krb5_conf_kdc_lookup()
{
    local retval=0
    echo -n "/etc/krb5.conf: dns_lookup_kdc "
    if grep -q '^\s*dns_lookup_kdc\s*=\s*\([Tt][Rr][Uu][Ee]\|1\|[Yy][Ee][Ss]\)\s*$' /etc/krb5.conf; then
        echo "is enabled"
    else
        if grep -q '^\s*dns_lookup_kdc\s*=' /etc/krb5.conf; then
            echo "is disabled"
            retval=1
        else
            echo "is enabled by default"
        fi
    fi
    return $retval
}

check_krb5_keytab_exists()
{
    ls -la /etc/krb5.keytab
    test -e /etc/krb5.keytab
}

run check_hostnamectl "Check hostnamectl"
run test_hostname "Test hostname is FQDN"
run check_system_auth "System authentication"
run test_domain_system_auth "Domain system authentication"
run check_krb5_conf_ccache "Kerberos credential cache"
run test_keyring_krb5_conf_ccache "Keyring as kerberos credential cache"
run check_krb5_conf_kdc_lookup "Check DNS lookup kerberos KDC"
run check_krb5_keytab_exists "Check machine crendetial cache"
