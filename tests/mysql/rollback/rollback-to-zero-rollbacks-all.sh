#!/usr/bin/env sh

BASE_DIR=$(dirname $0)/../../..
BASE_MIGRATION_DIR=$(mktemp -d)
ARGS="$@"
MIGRATION_ID_FIRST=20181207122842
MIGRATION_NAME_FIRST=$(mktemp -u XXXXXX)
TABLE_NAME_FIRST=first_table
MIGRATION_ID_SECOND=20181207122843
MIGRATION_NAME_SECOND=$(mktemp -u XXXXXX)
TABLE_NAME_SECOND=second_table
MIGRATION_ID_THIRD=20181207122845
MIGRATION_NAME_THIRD=$(mktemp -u XXXXXX)
CHECK=
FAILED=0

. ${BASE_DIR}/adapters/mysql/impl.sh

cleanUp()
{
	rm -rf ${BASE_MIGRATION_DIR}
	${MYSQL_CONNECTION} -e"
	DROP TABLE IF EXISTS ${TABLE_NAME_FIRST};
	DROP TABLE IF EXISTS ${TABLE_NAME_SECOND};
	DROP TABLE migration"
}

failWithMessage()
{
	FAILED=1
	echo >&2 $1
}

createDownMigration()
{
	local MIGRATION_FULLPATH=${BASE_MIGRATION_DIR}/$2_$3
	mkdir ${MIGRATION_FULLPATH}
	echo "$1" >${MIGRATION_FULLPATH}/down.sh
}

checkTools || exit 1

while [ "$1" != "" ]; do
	parseAdapterOptions "$@"
	shift
done

validateOptions || exit 1
prepareConnection
checkConnection || exit 1


createDownMigration \
"\${MYSQL_CONNECTION} -e\"DROP TABLE ${TABLE_NAME_FIRST}\"" \
${MIGRATION_ID_FIRST} ${MIGRATION_NAME_FIRST}

createDownMigration \
"\${MYSQL_CONNECTION} -e\"DROP TABLE ${TABLE_NAME_SECOND}\"" \
 ${MIGRATION_ID_SECOND} ${MIGRATION_NAME_SECOND}

createDownMigration \
"\${MYSQL_CONNECTION} -e\"ALTER TABLE ${TABLE_NAME_FIRST} DROP field\"" \
 ${MIGRATION_ID_THIRD} ${MIGRATION_NAME_THIRD}

ensureMigrationTableExists

${MYSQL_CONNECTION} -e"CREATE TABLE ${TABLE_NAME_FIRST}
 (id INT PRIMARY KEY, field INT(10) UNSIGNED NOT NULL DEFAULT '0')"
${MYSQL_CONNECTION} -e"CREATE TABLE ${TABLE_NAME_SECOND} (id INT PRIMARY KEY, test VARCHAR(20))"
${MYSQL_CONNECTION} -e"INSERT INTO migration VALUES
(${MIGRATION_ID_FIRST}, now()),
(${MIGRATION_ID_SECOND}, now()),
(${MIGRATION_ID_THIRD}, now())"

MIGRATION_DIR=${BASE_MIGRATION_DIR} ADAPTER=mysql ${BASE_DIR}/rollback.sh \
${ARGS} 0 2>/dev/null >/dev/null

for migrationId in ${MIGRATION_ID_FIRST} ${MIGRATION_ID_SECOND} ${MIGRATION_ID_THIRD}; do
	CHECK=$(${MYSQL_CONNECTION} --skip-column-names \
		-e"SELECT count(*) FROM migration WHERE id = ${migrationId}\G" 2>&1 | tail -1)
	[ "${CHECK}" = 0 ] || failWithMessage "Migration [${migrationId}] should be reverted"
done

for tableName in ${TABLE_NAME_FIRST} ${TABLE_NAME_SECOND}; do
	CHECK=$(${MYSQL_CONNECTION} --skip-column-names \
		-e"SELECT count(*) FROM information_schema.tables WHERE table_schema='${DB}' and table_name='${tableName}'\G" \
		| tail -1)
	[ "${CHECK}" = 0 ] || failWithMessage "Table [${tableName}] should be reverted"
done

cleanUp

exit ${FAILED}
