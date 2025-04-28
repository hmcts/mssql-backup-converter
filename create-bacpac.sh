# loop until SQL is ready
# lifted from https://github.com/grrlgeek/bak-to-bacpac/blob/main/container/Docker/create-bacpacs.sh

for i in {1..60}; do
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $MSSQL_SA_PASSWORD -Q "SELECT Name FROM SYS.DATABASES" -C
    if [ $? -eq 0 ]; then
        echo "sql server ready"
        break
    else
        echo "not ready yet..."
        sleep 1
    fi
done

/opt/mssql-tools18/bin/sqlcmd -l 300 -S localhost -U sa -P $MSSQL_SA_PASSWORD -d master -i "/sql-scripts/create_procedure_restoreheaderonly.sql" -C
/opt/mssql-tools18/bin/sqlcmd -l 300 -S localhost -U sa -P $MSSQL_SA_PASSWORD -d master -i "/sql-scripts/create_procedure_restoredatabase.sql" -C

for f in /mnt/external/*.bak; do
    s=${f##*/}
    name="${s%.*}"
    extension="${s#*.}"
    echo "Restoring $f..."
    /opt/mssql-tools18/bin/sqlcmd -l 300 -S localhost -U sa -P $MSSQL_SA_PASSWORD -d master -q "EXEC dbo.restoredatabase '/mnt/external/$name.$extension', '$name'" -C

    # Check if there is an extra sql script we should run prior to running sqlpackage
    scriptName="${name}_EXEC"
    scriptPath=${!scriptName}
    if [ ! -z "$scriptPath" ]; then
        if [ -f $scriptPath ]; then
            echo "Running $scriptPath..."
            /opt/mssql-tools18/bin/sqlcmd -l 300 -S localhost -U sa -P $MSSQL_SA_PASSWORD -d "$name" -i "$scriptPath" -C
        else
            echo "Script $scriptPath does not exist, skipping..."
        fi
    else
        echo "No extra script to run for $name"
    fi

    echo "Creating bacpac..."
    /sqlpackage/sqlpackage /Action:"Export" /SourceServerName:"localhost" /SourceUser:"sa" /SourcePassword:"$MSSQL_SA_PASSWORD" /SourceDatabaseName:"$name" /TargetFile:"/mnt/external/$name.bacpac" /SourceTrustServerCertificate:True
done
