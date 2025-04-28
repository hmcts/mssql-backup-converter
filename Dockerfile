FROM mcr.microsoft.com/mssql/server:2022-CU18-ubuntu-22.04

USER root

RUN apt-get -y update && apt-get install -y curl unzip

COPY . /
RUN chmod 777 /sql-scripts/*.sql
RUN chown -R mssql:root /sql-scripts/*.sql

RUN curl -o sqlpackage-linux.zip -L https://aka.ms/sqlpackage-linux
RUN unzip /sqlpackage-linux.zip -d /sqlpackage
RUN chmod 777 -R /sqlpackage

RUN rm /sqlpackage-linux.zip

RUN mkdir /mnt/external
RUN chown -R mssql:root /mnt

#Set permissions on script file
RUN chmod a+x ./create-bacpac.sh

# Switch back to mssql user and run the entrypoint script
USER mssql
ENTRYPOINT ["/bin/bash", "./entrypoint.sh"]