#!/bin/sh
# Compiles XX_HCM_MOBILE_WS and registers it in the Oracle Integration Repository,
# so it shows up in Integrated SOA Gateway under Human Resources > PL/SQL.
# This is the "Session Action Script" the guide (Create Custom WS.docx) refers to.
#
# Run as the applmgr OS user on the EBS application tier, from this folder,
# after sourcing the EBS environment file, for example:
#   . /u01/oracle/<SID>/apps/apps_st/appl/APPS<SID>_<host>.env
#   ./register_irep.sh
#
# You'll be asked for the APPS password. Nothing is stored in this script.

set -e

PKG=XX_HCM_MOBILE_WS

if [ -z "$FND_TOP" ] || [ -z "$IAS_ORACLE_HOME" ]; then
  echo "Source the EBS environment file first (FND_TOP and IAS_ORACLE_HOME are not set)." >&2
  exit 1
fi

printf "APPS password: "
stty -echo; read APPS_PWD; stty echo; echo

echo "1/3 Compiling the package in the APPS schema"
sqlplus -s "apps/${APPS_PWD}" <<SQL
WHENEVER SQLERROR EXIT FAILURE
@${PKG}.pls
@${PKG}.plb
SHOW ERRORS PACKAGE ${PKG}
SHOW ERRORS PACKAGE BODY ${PKG}
EXIT
SQL

echo "2/3 Parsing the annotations into an iLDT file"
$IAS_ORACLE_HOME/perl/bin/perl $FND_TOP/bin/irep_parser.pl -g -v -username=sysadmin \
  per:patch/115/sql:${PKG}.pls:12.0=${PKG}.pls

echo "3/3 Uploading the iLDT file to the Integration Repository"
FNDLOAD "apps/${APPS_PWD}" 0 Y UPLOAD $FND_TOP/patch/115/import/wfirep.lct ${PKG}_pls.ildt

echo "Done. Log in as SYSADMIN, open Integrated SOA Gateway > Integration Repository,"
echo "find '${PKG}' under Human Resources Suite > PL/SQL, then create grants,"
echo "generate the WSDL and deploy it with Username Token authentication."
