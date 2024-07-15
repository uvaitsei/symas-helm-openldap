#!/usr/bin/env bash
#
# SPDX-License-Identifier: APACHE-2.0
# shellcheck disable=SC1091,SC2064

set -euo pipefail
#set -x
trap "trap - SIGTERM && kill -- -$$ || /bin/true" SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM EXIT
trap 'error "Failure during testing!"' SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM

# Load libraries
. "$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/liblog.sh"

is_boolean_yes() {
    local -r bool="${1:-}"
    # comparison is performed without regard to the case of alphabetic characters
    shopt -s nocasematch
    if [[ "$bool" = 1 || "$bool" =~ ^(yes|true)$ ]]; then
        true
    else
        false
    fi
}

debug_execute() {
    if is_boolean_yes "${DEBUG:-false}"; then
        LDAPTLS_REQCERT=never "$@"
    else
        LDAPTLS_REQCERT=never "$@" >/dev/null 2>&1
    fi
}

proxy() {
    for pid in $(lsof -i tcp:"$1" | grep -E -q "kubectl.*?$(whoami).*?localhost:$1"); do
        kill "$pid"
    done

    info "Forwarding -> locahost:$1 -> $3:$2"
    (kubectl port-forward --namespace ds "$3" "$1":"$2" > /dev/null 2>&1) &
}

ldap_add() {
    p=30636
    if [ $# -eq 2 ]; then
	debug_execute ldapadd -o nettimeout=20 -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:"$p" -f "$1" || true
	trap 'debug_execute ldapmodify -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -f "$2"' SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM
    else
	exit 1
    fi
}

ldap_search() {
    DN='cn=admin,dc=example,dc=org'
    if [ $# -eq 3 ]; then
	DN=$1
	shift
    fi
    for p in 30636 40636 41636 42636; do
	if [ $# -eq 1 ]; then
	    debug_execute ldapsearch -o nettimeout=20 -x -D "${DN}" -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:"$p" -b "$1" || true
	elif [ $# -eq 2 ]; then
	    debug_execute ldapsearch -o nettimeout=20 -x -D "${DN}" -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:"$p" -b "$1" | tee "$2" || true
	    trap "rm $2 || true" SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM EXIT
	else
	    exit 1
	fi
    done
}

NAMESPACE=ds

info "Testing the openldap database cluster..."

proxy 30636 1636 service/openldap
proxy 40636 1636 openldap-0
proxy 41636 1636 openldap-1
proxy 42636 1636 openldap-2

info "Fetch the LDAP admin password from k8s"
LDAP_ADMIN_PASSWORD=$(kubectl get secret --namespace ${NAMESPACE} openldap -o jsonpath="{.data.LDAP_ADMIN_PASSWORD}" | base64 --decode; echo)

info "Add a single user"
ldap_add .bin/user.ldif .bin/user-delete.ldif

if false
then
    info "Testing MemberOf"
    ldap_search 'cn=admin,dc=example,dc=org' /tmp/test-memberof.txt
    awk -f .bin/ldif2json /tmp/test-memberof.txt | jq
    [[ $(grep "numResponses" /tmp/test-memberof.txt | cut -d ":" -f 2 | tr -d ' ') -lt 2 ]] && exit 1
    [[ $(grep "uid=test1,ou=People,dc=example,dc=org" /tmp/test-memberof.txt) == "objectClass: ownCloud" ]] || exit 1
fi

if true
then
    info "Search for that user in our cluster"
    ldap_search 'dc=example,dc=org' /tmp/test-write.txt

    #info "Ensure num responses"
    #[[ $(grep "numResponses" /tmp/test-write.txt | cut -d ":" -f 2 | tr -d ' ') -ge 1 ]] || exit 1

    #info "Ensure objectClass"
    #[[ $(grep "objectClass: ownCloud" /tmp/test-write.txt) == "objectClass: ownCloud" ]] || exit 1
fi

info Search for the ownCloud config
# https://github.com/valerytschopp/owncloud-ldap-schema/tree/master?tab=readme-ov-file#installation
#ldapsearch -H ldapi:// -Y EXTERNAL -LLL -b cn=config "(cn={*}owncloud)"
#debug_execute env LDAPTLS_REQCERT=never ldapsearch -o nettimeout=20 -x -D cn=admin,dc=example,dc=org -w Not@SecurePassw0rd -H ldaps://localhost:30636 -LLL -b cn=config "(cn={*}owncloud)" | tee /tmp/test-write.txt
#ldap_search cn=admin,cn=config "(cn={*}owncloud)" /tmp/test-write.txt

cnt=${2:-${1:-10}}
info "Add $cnt entries"
for ((i = 0 ; i < cnt ; i++ )); do
   ( sed 's/dn: uid=einstein,dc=example,dc=org/dn: uid=einstein-'"${i}"',dc=example,dc=org/; s/uid: einstein/uid: einstein-'"${i}"'/; s/uidNumber: 20000/uidNumber: '"$(printf "2%04d" $i)"'/; s|homeDirectory: /home/einstein|homeDirectory: /home/einstein-'"${i}"'|; s/ownCloudUUID:: NGM1MTBhZGEtYzg2Yi00ODE1LTg4MjAtNDJjZGY4MmMzZDUx/ownCloudUUID:: '"$(uuidgen | base64)"'/' .bin/user.ldif | tee | debug_execute ldapadd -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 ) || /bin/true
done

info "Search for each of the new $cnt entries"
for ((i = 0 ; i < cnt ; i++ )); do
    ldap_search "uid=einstein-${i},dc=example,dc=org"
done

if [ -z "${1:-}" ]; then
    info "Remove $cnt entries"
    for ((i = 0 ; i < cnt ; i++ )); do
	sed 's/dn: uid=einstein,dc=example,dc=org/dn: uid=einstein-'"${i}"',dc=example,dc=org/' .bin/user-delete.ldif | debug_execute ldapmodify -x -D 'cn=admin,dc=example,dc=org' -w Not@SecurePassw0rd -H ldaps://localhost:30636
    done
fi

info "Search again for that same user in our cluster"
ldap_search 'dc=example,dc=org'

if [ -z "${1:-}" ]; then
    info "Delete user"
    debug_execute ldapmodify -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -f .bin/user-delete.ldif
fi

info "Successful test run!"
