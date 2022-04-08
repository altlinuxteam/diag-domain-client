#!/bin/bash
set -euo pipefail

. shell-terminfo

terminfo_init

verbose=1

msg_fail()
{
    echo -n " \ $*: ["
    color_text "FAIL" red
    echo "]"
}

msg_warn()
{
    echo -n " \ $*: ["
    color_text "WARN" yellow
    echo "]"
}

msg_done()
{
    echo -n " \ $*: ["
    color_text "DONE" green
    echo "]"
}

_command()
{
    local retval=0
    local x=
    local p='$'
    if test "$1" = '-x'; then
        shift
        x=1
    fi
    if test "$1" = '-r'; then
        shift
        p='#'
    fi
    color_message "$p $*" bold
    test -z "$x" || echo -------------------------------------------------------------------------------
    $* || retval=$?
    test -z "$x" || echo -------------------------------------------------------------------------------
    echo
    return $retval
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
        _command -r $* || return 1
    fi
}

run()
{
    local retval=126
    local func="$1"
    local msg=$(printf "/======             %-52s ======" "$func")

    test -z $verbose || echo " /============================================================================="
    if test -z $verbose; then
        $func >/dev/null 2>&1 && retval=0 || retval=$?
    else
        color_message "$msg" bold white
        $func && retval=0 || retval=$?
    fi

    test -z $verbose || echo "\=============================================================================="
    case "$retval" in
        0) msg_done  "$2" ;;
        2) msg_warn  "$2" ;;
        *) msg_fail "$2" ;;
    esac
    test -z $verbose || color_message "  \============================================================================" bold white
    test -z $verbose || echo
}

check_hostnamectl()
{
    local retval=0
    local static_host="$(hostnamectl --static)" || retval=1
    local transient_host="$(hostname)" || retval=1
    _command hostnamectl || retval=1
    test "$static_host" = "$transient_host" || retval=1
    return $retval
}

test_hostname()
{
    local host=`hostname`
    HOSTNAME_COMMON="$host"
    HOSTNAME_SHORT=`hostname -s`
    HOSTNAME_FQDN=`hostname -f`
    test "$host" != "${host/.}" || return 2
}

check_system_auth()
{
    local auth=$(/usr/sbin/control system-auth)
    echo "control system_auth: $auth"
    _command readlink -f /etc/pam.d/system-auth
    _command -x cat /etc/pam.d/system-auth
    SYSTEM_AUTH="$auth"
    test -n "$auth" -a "$auth" != "unknown"
}

test_domain_system_auth()
{
    test -n "$SYSTEM_AUTH" ||
        SYSTEM_AUTH=local
    test "$SYSTEM_AUTH" != "local" || return 2
}

is_system_auth_local()
{
    test "$SYSTEM_AUTH" = "local"
}

check_krb5_conf_exists()
{
    local retval=0
    _command ls -l /etc/krb5.conf
    KRB5_DEFAULT_REALM=
    if ! test -e /etc/krb5.conf; then
        is_system_auth_local && retval=2 || retval=1
    else
        _command -x cat /etc/krb5.conf
        KRB5_DEFAULT_REALM=$(grep "^\s*default_realm\s\+" /etc/krb5.conf | sed -e 's/^\s*default_realm\s*=\s*//' -e 's/\s*$//')
    fi
    return $retval
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
    local retval=0
    _command ls -l /etc/krb5.keytab
    if ! test -e /etc/krb5.keytab; then
        is_system_auth_local && retval=2 || retval=1
    fi
    return $retval
}

check_keytab_credential_list()
{
    local retval=0
    if ! run_by_root klist -ke; then
        is_system_auth_local && retval=2 || retval=1
    fi
    return $retval
}

check_resolv_conf()
{
    local retval=0
    _command ls -l /etc/resolv.conf
    _command -x cat /etc/resolv.conf
    SEARCH_DOMAIN=$(grep "^search\s\+" /etc/resolv.conf | sed -e 's/^search\s\+//' -e 's/\s/\n/' | head -1)
    NAMESERVER1=$(grep "^nameserver\s\+" /etc/resolv.conf | sed -e 's/^nameserver\s\+//' -e 's/\s/\n/' | head -1)
    NAMESERVER2=$(grep "^nameserver\s\+" /etc/resolv.conf | sed -e 's/^nameserver\s\+//' -e 's/\s/\n/' | head -2 | tail -1)
    NAMESERVER3=$(grep "^nameserver\s\+" /etc/resolv.conf | sed -e 's/^nameserver\s\+//' -e 's/\s/\n/' | head -3 | tail -1)
}

compare_resolv_conf_with_default_realm()
{
    echo "SEARCH_DOMAIN = '$SEARCH_DOMAIN'"
    echo "KRB5_DEFAULT_REALM = '$KRB5_DEFAULT_REALM'"
    local domain=$(echo "$SEARCH_DOMAIN" | tr '[:upper:]' '[:lower:]')
    local realm=$(echo "$KRB5_DEFAULT_REALM" | tr '[:upper:]' '[:lower:]')

    DOMAIN_DOMAIN="$domain"
    if test -n "$realm"; then
        DOMAIN_DOMAIN="$realm"
    else
        return 2
    fi
    test -n "$domain" || return 2
    test "$domain" = "$realm" || return 2
}

check_smb_conf()
{
    local retval=0
    _command ls -l /etc/samba/smb.conf
    _command -x grep -v -e '^\s*[#;]' -e '^\s*$' /etc/samba/smb.conf
    _command -x testparm -s
    SMB_REALM=$(testparm -v -s 2>/dev/null | grep "^\s*realm\s*=" | sed -e 's/^\s*realm\s*=\s*//' -e 's/\s*$//')
    SMB_NETBIOS_NAME=$(testparm -v -s 2>/dev/null | grep "^\s*netbios name\s*=" | sed -e 's/^\s*netbios name\s*=\s*//' -e 's/\s*$//')
}

compare_smb_realm_with_krb5_default_realm()
{
    echo "SMB_REALM = '$SMB_REALM'"
    echo "KRB5_DEFAULT_REALM = '$KRB5_DEFAULT_REALM'"

    test -n "$SMB_REALM" || return 2
    test -n "$KRB5_DEFAULT_REALM" || return 2
    test "$KRB5_DEFAULT_REALM" = "$SMB_REALM" || return 2
}

test_smb_realm()
{
    local retval=0

    DOMAIN_REALM="$KRB5_DEFAULT_REALM"
    if test -n "$SMB_REALM"; then
        DOMAIN_REALM="$SMB_REALM"
        DOMAIN_DOMAIN="$(echo "$SMB_REALM" | tr '[:upper:]' '[:lower:]')"
    else
        test -z "$DOMAIN_REALM" ||
            DOMAIN_DOMAIN="$(echo "$DOMAIN_REALM" | tr '[:upper:]' '[:lower:]')"
        test -n "$DOMAIN_REALM" ||
            DOMAIN_REALM="$(echo "$DOMAIN_DOMAIN" | tr '[:lower:]' '[:upper:]')"
        is_system_auth_local && retval=2 || retval=1
    fi

    echo "DOMAIN_REALM = '$DOMAIN_REALM'"
    echo "DOMAIN_DOMAIN = '$DOMAIN_DOMAIN'"

    return $retval
}

test_domainname()
{
    HOSTNAME_DOMAIN=`hostname -d`

    if [ "$HOSTNAME_DOMAIN" = "$HOSTNAME_SHORT" -o "$HOSTNAME_DOMAIN" = '(none)' -o -z "$HOSTNAME_DOMAIN" ]; then
        HOSTNAME_DOMAIN=
        echo "HOSTNAME_DOMAIN = '$HOSTNAME_DOMAIN'"
        return 2
    fi

    if [ -z "$DOMAIN_DOMAIN" ]; then
        DOMAIN_DOMAIN="$HOSTNAME_DOMAIN"
        test -n "$DOMAIN_REALM" ||
            DOMAIN_REALM="$(echo "$DOMAIN_DOMAIN" | tr '[:lower:]' '[:upper:]')"
        echo "HOSTNAME_DOMAIN = '$HOSTNAME_DOMAIN'"
        echo "Update realm and domain from HOSTNAME_DOMAIN:"
        echo " DOMAIN_REALM = '$DOMAIN_REALM'"
        echo " DOMAIN_DOMAIN = '$DOMAIN_DOMAIN'"
        return 2
    fi

    echo "HOSTNAME_DOMAIN = '$HOSTNAME_DOMAIN'"
    test "$HOSTNAME_DOMAIN" = "$DOMAIN_DOMAIN" || return 1
}

_check_nameserver()
{
    local ns="$1"
    if _command ping -c 2 -i2 "$ns"; then
        test -z "$DOMAIN_DOMAIN" || _command host "$DOMAIN_DOMAIN" "$ns"
    else
        return 1
    fi
}

check_nameservers()
{
    retval1=0
    retval2=0
    retval3=0
    if [ -n "$NAMESERVER1" ]; then
        _check_nameserver "$NAMESERVER1" || retval1=1
    fi
    if [ -n "$NAMESERVER2" ]; then
        _check_nameserver "$NAMESERVER2" || retval2=1
    fi
    if [ -n "$NAMESERVER3" ]; then
        _check_nameserver "$NAMESERVER3" || retval3=1
    fi
    if test "$retval1" = 0 -a "$retval2" = 0 -a "$retval3" = 0; then
        return 0;
    fi
    if test "$retval1" = 1 -a "$retval2" = 1 -a "$retval3" = 1; then
        return 1;
    fi
    return 2
}

check_kerberos_and_ldap_srv_records()
{
    test -n "$DOMAIN_DOMAIN" || return 1
    _command host -t srv "_kerberos._udp.$DOMAIN_DOMAIN"
    _command host -t srv "_ldap._tcp.$DOMAIN_DOMAIN"
}

compare_netbios_name()
{
    local netbios=$(echo "$SMB_NETBIOS_NAME" | tr '[:upper:]' '[:lower:]')
    local host=$(echo "$HOSTNAME_SHORT" | tr '[:upper:]' '[:lower:]')

    echo "SMB_NETBIOS_NAME = '$SMB_NETBIOS_NAME'"
    echo "HOSTNAME_SHORT = '$HOSTNAME_SHORT'"
    test "$netbios" = "$host" || return 1
}

run check_hostnamectl "Check hostname persistance"
run test_hostname "Test hostname is FQDN (not short)"
run check_system_auth "System authentication method"
run test_domain_system_auth "Domain system authentication enabled"
run check_krb5_conf_exists "Check Kerberos configuration exists"
run check_krb5_conf_ccache "Kerberos credential cache status"
run test_keyring_krb5_conf_ccache "Using keyring as kerberos credential cache"
run check_krb5_conf_kdc_lookup "Check DNS lookup kerberos KDC status"
run check_krb5_keytab_exists "Check machine crendetial cache is exists"
run check_keytab_credential_list "Check machine credentials list in keytab"
run check_resolv_conf "Check nameserver resolver configuration"
run compare_resolv_conf_with_default_realm "Compare krb5 realm and first search domain"
run check_smb_conf "Check Samba configuration"
run compare_smb_realm_with_krb5_default_realm "Compare samba and krb5 realms"
run test_smb_realm "Check Samba domain realm"
run test_domainname "Check hostname FQDN domainname"
run check_nameservers "Check nameservers availability"
run check_kerberos_and_ldap_srv_records "Check Kerberos and LDAP SRV-records"
run compare_netbios_name "Compare NetBIOS name and hostname"
