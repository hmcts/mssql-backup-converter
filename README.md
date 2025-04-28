# mssql-backup-converter

This is a utility that converts .bak files from MSSQL Servers to the .bacpac format. This is mostly based on https://github.com/grrlgeek/bak-to-bacpac/ with some modifications to make it work with our particular use case.

## Prerequisites
The .bak file must be from a SQL Server no older than 2008.
The SQL Package utility may run into issues converting databases with certain types of data, or that are using certain features. You may need to provide an additional SQL script to drop problematic objects.

## Running

### Required Parameters

| Parameter              | Description                                                                                                                                                                                                                                                                                                                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ACCEPT_EULA`          | Set to `Y` to accept the MSSQL Server EULA.                                                                                                                                                                                                                                                                                                                                                                   |
| `MSSQL_SA_PASSWORD`    | The password for the SA user. This is only used for the SQL Server instance created inside the container, can be set to a value of your choice.                                                                                                                                                                                                                                                               |
| `<database_name>_EXEC` | The path of a SQL Script to run against the database once its been restored but before SQL Package is run. The variable name must be in the format `<database_name>_EXEC`. For example, if your database is called `Alexs_Database`, the variable must be called `Alexs_Database_EXEC`. This path must also be accessible to the container, so should be mounted or in the same directory as the .bak file(s) |

### Example

The example below assumes both your additional script and .bak file are in the same directory. These could be separated if desired.

```bash
docker run --rm -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD=asupersecurepassword -e Alexs_Database_EXEC=/mnt/external/my_sql_script.sql -v ~/Documents/Workspace/bak-to-bacpac-test:/mnt/external --name bak-to-bacpac mssql-backup-converter:latest
```

## How to import to Azure SQL

First create a database of a specific size and tier. The example below creates a database with 2 vCores in the General Purpose tier.

```bash
az sql db create --name your_database_name --resource-group your_resource_group --server your_sql_server -e GeneralPurpose -f Gen5 -c 2
```

Upload your bacpac file to a storage account, and generate a SAS token for it. The example below uses the Azure CLI to generate a SAS token for a blob container.

```bash
az storage blob generate-sas --account-name your_storage_account -c your_container_name -n your_backup.bacpac --permissions rw --expiry 2025-04-28T21:00:00Z --https-only
```

Run the az sql db import command to import the bacpac file into your database. The example below uses the Azure CLI to import a bacpac file from a storage account.

```bash
az sql db import -s your_sql_server -n your_database_name -g your_resource_group -p your_sql_server_admin_password -u your_sql_server_admin_login \
--storage-key "<your SAS token goes here" \
--storage-key-type SharedAccessKey \
--storage-uri https://your_storage_account.blob.core.windows.net/your_container_name/your_backup.bacpac
```