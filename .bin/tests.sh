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

ldap_search() {
    for p in 30636 40636 41636 42636; do
	if [ $# -eq 1 ]; then
	    debug_execute ldapsearch -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:"$p" -b "$1" || true
	elif [ $# -eq 2 ]; then
	    debug_execute ldapsearch -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:"$p" -b "$1" | tee "$2" || true
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
debug_execute ldapadd -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -f .bin/user.ldif
trap 'debug_execute ldapmodify -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -f .bin/user-delete.ldif' SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM

info "Search for that user in our cluster"
ldap_search 'dc=example,dc=org' /tmp/test-write.txt

# info "Ensure num responses"
#[[ $(grep "numResponses" /tmp/test-write.txt | cut -d ":" -f 2 | tr -d ' ') -eq 4 ]] || exit 1

# info "Ensure objectClass"
#[[ $(grep "objectClass: ownCloud" /tmp/test-write.txt) == "objectClass: ownCloud" ]] || exit 1

cnt=${2:-${1:-10}}
info "Add $cnt entries"
for ((i = 0 ; i < cnt ; i++ )); do
    sed 's/dn: uid=einstein,dc=example,dc=org/dn: uid=einstein-'"${i}"',dc=example,dc=org/; s/uid: einstein/uid: einstein-'"${i}"'/; s/uidNumber: 20000/uidNumber: '"$(printf "2%04d" $i)"'/; s|homeDirectory: /home/einstein|homeDirectory: /home/einstein-'"${i}"'|; s/ownCloudUUID:: NGM1MTBhZGEtYzg2Yi00ODE1LTg4MjAtNDJjZGY4MmMzZDUx/ownCloudUUID:: '"$(uuidgen | base64)"'/' .bin/user.ldif | debug_execute ldapadd -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636
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
