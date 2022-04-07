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
        return 2
    else
        test -z "$msg" ||
            echo -n "$msg: "
        $* || return 1
    fi
}

run()
{
    local retval=126
    local func="$1"

    if test -z $verbose; then
        $func >/dev/null 2>&1 && retval=0 || retval=$?
    else
        echo "--- $func ---"
        $func && retval=0 || retval=$?
    fi

    test -z $verbose || echo ---
    case "$retval" in
        0) msg_done  "$2" ;;
        2) msg_warn  "$2" ;;
        *) msg_fail "$2" ;;
    esac
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
    test "$host" != "${host/.}" || return 2
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
    test -n "$auth" -a "$auth" != "local" || return 2
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
    test -n "$ccache" -a "$ccache" == "keyring" || return 2
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
            retval=2
        fi
    fi
    return $retval
}

check_krb5_keytab_exists()
{
    ls -la /etc/krb5.keytab
    test -e /etc/krb5.keytab
}

check_keytab_credential_list()
{
    run_by_root klist -ke
}

run check_hostnamectl "Check hostnamectl"
run test_hostname "Test hostname is FQDN"
run check_system_auth "System authentication"
run test_domain_system_auth "Domain system authentication"
run check_krb5_conf_ccache "Kerberos credential cache"
run test_keyring_krb5_conf_ccache "Keyring as kerberos credential cache"
run check_krb5_conf_kdc_lookup "Check DNS lookup kerberos KDC"
run check_krb5_keytab_exists "Check machine crendetial cache is exists"
run check_keytab_credential_list "Check keytab credential list"
