#!/bin/bash
set -e

# Ensure a backup file argument is provided
if [ -z "$4" ]; then
    echo "❌ No backup file provided. Usage: $0 <SQLCMD_PATH> <SQLPACKAGE_PATH> <SQL_SCRIPTS_PATH> <BAK_FILE>"
    exit 1
fi

# Set default paths for sqlcmd and sqlpackage
SQLCMD_PATH=${1:-"/opt/mssql-tools/bin/sqlcmd"}
SQLPACKAGE_PATH=${2:-"/sqlpackage/sqlpackage"}
SQL_SCRIPTS_PATH=${3:-"sql-scripts/"}
BAK_FILE=$4

# Extract the base database name (remove numeric suffix and extension)
DB_NAME=$(echo "$BAK_FILE" | sed -E 's/-[0-9]+\.bak$//')
BAK_FILE_PATH="/mnt/external/$BAK_FILE"

# Preserve original filename for Bacpac export
BACPAC_FILE="/mnt/external/${BAK_FILE%.bak}.bacpac"

echo "🔹 Using sqlcmd at: $SQLCMD_PATH"
echo "🔹 Using sqlpackage at: $SQLPACKAGE_PATH"
echo "🔹 Using SQL scripts from: $SQL_SCRIPTS_PATH"
echo "🔹 Processing backup file: $BAK_FILE"
echo "🔹 Target database name: $DB_NAME"
echo "🔹 Bacpac export will be named: $BACPAC_FILE"

# Loop until SQL Server is ready
for i in {1..60}; do
    $SQLCMD_PATH -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SET NOCOUNT ON; SELECT Name FROM SYS.DATABASES" -C
    if [ $? -eq 0 ]; then
        echo "✅ SQL Server is ready!"
        break
    else
        echo "⏳ Waiting for SQL Server..."
        sleep 1
    fi
done

# Run SQL scripts for setup using provided or default path
echo "🔹 Running SQL Setup Scripts..."
$SQLCMD_PATH -l 300 -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d master -i "${SQL_SCRIPTS_PATH}create_procedure_restoreheaderonly.sql" -C
$SQLCMD_PATH -l 300 -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d master -i "${SQL_SCRIPTS_PATH}create_procedure_restoredatabase.sql" -C

# Restore database from provided backup file
echo "📂 Restoring database: $DB_NAME from $BAK_FILE_PATH..."

nohup $SQLCMD_PATH -l 300 -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d master \
    -q "EXEC dbo.restoredatabase '$BAK_FILE_PATH', '$DB_NAME'" -C > restore_$DB_NAME.log 2>&1 &
    
RESTORE_PID=$!
echo "🔹 Restore started with PID: $RESTORE_PID"

# Poll SQL Server until restore is fully completed
while true; do
    RESTORE_STATUS=$($SQLCMD_PATH -l 300 -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d master -Q "
    SET NOCOUNT ON;
    SELECT COUNT(*) FROM sys.dm_exec_requests WHERE command LIKE 'RESTORE%';
    " -h -1 | tr -d '[:space:]' | grep -o '[0-9]*' | head -n 1)

    if [ "$RESTORE_STATUS" -eq 0 ]; then
        echo "✅ Restore verified as complete for $DB_NAME!"
        break
    else
        echo "⏳ Restore still in progress for $DB_NAME..."
        sleep 5
    fi
done

wait $RESTORE_PID
echo "✅ Background restore process completed!"
sleep 10

# Verify database is online before proceeding
DB_STATUS=$($SQLCMD_PATH -l 300 -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d master -Q "
SET NOCOUNT ON;
SELECT state_desc FROM sys.databases WHERE name = '$DB_NAME';
" -h -1 | tr -d '[:space:]' | grep -o 'ONLINE\|RESTORING\|RECOVERY_PENDING\|SUSPECT' | head -n 1)

if [ "$DB_STATUS" != "ONLINE" ]; then
    echo "❌ Database $DB_NAME is not ONLINE, exiting pipeline..."
    exit 1
fi

echo "✅ Database $DB_NAME is ONLINE, executing cleanup script before export..."

# 🔹 Run GAPS_DROP_PROBLEMATIC.sql to remove problematic views/procedures
echo "⚠ Running cleanup script: GAPS_DROP_PROBLEMATIC.sql"
$SQLCMD_PATH -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$DB_NAME" -i "${SQL_SCRIPTS_PATH}GAPS_DROP_PROBLEMATIC.sql" -C

echo "✅ Cleanup completed, proceeding with Bacpac export..."

# Run SQLPackage export
echo "🔹 Exporting Database to Bacpac: $BACPAC_FILE..."
$SQLPACKAGE_PATH /Action:"Export" /TargetFile:"$BACPAC_FILE" /Quiet:True \
  /SourceConnectionString:"Data Source=localhost;Initial Catalog=$DB_NAME;User ID=sa;Password=$MSSQL_SA_PASSWORD;TrustServerCertificate=True"

if [ $? -ne 0 ]; then
    echo "❌ Bacpac export failed for $DB_NAME, exiting pipeline..."
    exit 1
fi

echo "✅ Bacpac export completed: $BACPAC_FILE"
