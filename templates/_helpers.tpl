{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "openldap.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "openldap.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Release.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openldap.chart" -}}
{{- printf "%s-%s" .Release.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "openldap.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ .Release.Name }}-{{ .Release.Namespace }}-sa
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Generate chart secret name
*/}}
{{- define "openldap.secretName" -}}
{{ default (include "openldap.fullname" .) .Values.global.existingSecret }}
{{- end -}}

{{/*
Generate olcServerID list
*/}}
{{- define "olcServerIDs" }}
{{- $name := (include "openldap.fullname" .) }}
{{- $namespace := .Release.Namespace }}
{{- $cluster := .Values.replication.clusterName }}
{{- $nodeCount := .Values.replicaCount | int }}
  {{- range $index0 := until $nodeCount }}
    {{- $index1 := $index0 | add1 }}
    olcServerID: {{ $index1 }} ldap://{{ $name }}-{{ $index0 }}.{{ $name }}-headless.{{ $namespace }}.svc.{{ $cluster }}:1389
  {{- end -}}
{{- end -}}

{{/*
Generate olcSyncRepl list
*/}}
{{- define "olcSyncRepls" -}}
{{- $name := (include "openldap.fullname" .) }}
{{- $namespace := .Release.Namespace }}
{{- $domain := ternary (include "global.baseDomain" .) "cn=config" (empty .Values.global.ldapDomain) }}
{{- $bindDNUser := .Values.global.adminUser }}
{{- $cluster := .Values.replication.clusterName }}
{{- $configPassword :=  ternary .Values.global.configPassword "%%CONFIG_PASSWORD%%" (empty .Values.global.existingSecret) }}
{{- $retry := .Values.replication.retry }}
{{- $timeout := .Values.replication.timeout }}
{{- $starttls := .Values.replication.starttls }}
{{- $tls_reqcert := .Values.replication.tls_reqcert }}
{{- $nodeCount := .Values.replicaCount | int }}
  {{- range $index0 := until $nodeCount }}
    {{- $index1 := $index0 | add1 }}
    olcSyncRepl: rid=00{{ $index1 }} provider=ldap://{{ $name }}-{{ $index0 }}.{{ $name }}-headless.{{ $namespace }}.svc.{{ $cluster }}:1389 binddn="{{ printf "cn=%s,%s" $bindDNUser $domain }}" bindmethod=simple credentials={{ $configPassword }} searchbase="cn=config" type=refreshAndPersist retry="{{ $retry }} +" timeout={{ $timeout }} starttls={{ $starttls }} tls_reqcert={{ $tls_reqcert }}
  {{- end -}}
{{- end -}}

{{/*
Generate olcSyncRepl list
*/}}
{{- define "olcSyncRepls2" -}}
{{- $name := (include "openldap.fullname" .) }}
{{- $domain := (include "global.baseDomain" .) }}
{{- $bindDNUser := .Values.global.adminUser }}
{{- $namespace := .Release.Namespace }}
{{- $cluster := .Values.replication.clusterName }}
{{- $adminPassword := ternary .Values.global.adminPassword "%%ADMIN_PASSWORD%%" (empty .Values.global.existingSecret) }}
{{- $retry := .Values.replication.retry }}
{{- $timeout := .Values.replication.timeout }}
{{- $starttls := .Values.replication.starttls }}
{{- $tls_reqcert := .Values.replication.tls_reqcert }}
{{- $interval := .Values.replication.interval }}
{{- $nodeCount := .Values.replicaCount | int }}
  {{- range $index0 := until $nodeCount }}
    {{- $index1 := $index0 | add1 }}
    olcSyncrepl:
      rid=10{{ $index1 }}
      provider=ldap://{{ $name }}-{{ $index0 }}.{{ $name }}-headless.{{ $namespace }}.svc.{{ $cluster }}:1389
      binddn={{ printf "cn=%s,%s" $bindDNUser $domain }}
      bindmethod=simple
      credentials={{ $adminPassword }}
      searchbase={{ $domain }}
      type=refreshAndPersist
      interval={{ $interval }}
      network-timeout=0
      retry="{{ $retry }} +"
      timeout={{ $timeout }}
      starttls={{ $starttls }}
      tls_reqcert={{ $tls_reqcert }}
  {{- end -}}
{{- end -}}

{{/*
Renders a value that contains template.
Usage:
{{ include "openldap.tplValue" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "openldap.tplValue" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}

{{/*
Return the proper OpenLDAP image name
*/}}
{{- define "openldap.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "openldap.imagePullSecrets" -}}
{{ include "common.images.pullSecrets" (dict "images" (list .Values.image ) "global" .Values.global) }}
{{- end -}}


{{/*
Return the proper OpenLDAP init TLS Secret container image name
*/}}
{{- define "openldap.initTLSSecretImage" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.initTLSSecret.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper OpenLDAP init container image name
*/}}
{{- define "openldap.initSchemaImage" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.initSchema.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper OpenLDAP volume permissions init container image name
*/}}
{{- define "openldap.volumePermissionsImage" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.volumePermissions.image "global" .Values.global) -}}
{{- end -}}


{{/*
Return the list of builtin schema files to mount
Cannot return list => return string comma separated
*/}}
{{- define "openldap.builtinSchemaFiles" -}}
  {{- $schemas := "" -}}
  {{- print $schemas -}}
{{- end -}}

{{/*
Return the list of builtin replication files to mount
Cannot return list => return string comma separated
*/}}
{{- define "openldap.replicationConfigFiles" -}}
  {{- $schemas := "" -}}
  {{- if .Values.replication.enabled -}}
    {{- $schemas = "01_serverid-modify,02_rep-modify,03_brep-modify,04_acls-modify" -}}
  {{- else -}}
    {{- $schemas = "acls" -}}
  {{- end -}}
  {{- print $schemas -}}
{{- end -}}

{{/*
Return the list of custom schema files to use
Cannot return list => return string comma separated
*/}}
{{- define "openldap.customSchemaFiles" -}}
  {{- $schemas := "" -}}
  {{- $schemas := ((join "," (.Values.customSchemaFiles | keys | sortAlpha))  | replace ".ldif" "") -}}
  {{- print $schemas -}}
{{- end -}}

{{/*
Return the list of all schema files to use
Cannot return list => return string comma separated
*/}}
{{- define "openldap.schemaFiles" -}}
  {{- $schemas := (include "openldap.builtinSchemaFiles" .) -}}
  {{- print $schemas -}}
{{- end -}}

{{/*
Return the proper base domain
*/}}
{{- define "global.baseDomain" -}}
{{- $bd := include "tmp.baseDomain" .}}
{{- printf "%s" $bd | trimSuffix "," -}}
{{- end }}

{{/*
tmp method to iterate through the ldapDomain
*/}}
{{- define "tmp.baseDomain" -}}
{{- if regexMatch ".*=.*" .Values.global.ldapDomain }}
{{- printf "%s" .Values.global.ldapDomain }}
{{- else }}
{{- $parts := split "." .Values.global.ldapDomain }}
  {{- range $index, $part := $parts }}
  {{- $index1 := $index | add 1 -}}
dc={{ $part }},
  {{- end}}
  {{- end -}}
{{- end -}}

{{/*
Return the server name
*/}}
{{- define "global.server" -}}
{{- printf "%s.%s" .Release.Name .Release.Namespace  -}}
{{- end -}}

{{/*
Return the admin bindDN
*/}}
{{- define "global.bindDN" -}}
{{- printf "cn=%s,%s" .Values.global.adminUser (include "global.baseDomain" .) -}}
{{- end -}}

{{/*
Return the ldaps port
*/}}
{{- define "global.ldapsPort" -}}
{{- printf "%d" .Values.global.sslLdapPort  -}}
{{- end -}}

{{/*
Return the ldap port
*/}}
{{- define "global.ldapPort" -}}
{{- printf "%d" .Values.global.ldapPort  -}}
{{- end -}}
