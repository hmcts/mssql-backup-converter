-- Lifted from https://github.com/grrlgeek/bak-to-bacpac/blob/main/container/Docker/create_procedure_restoreheaderonly.sql

USE master; 
GO 

-- Create the stored procedure to create the headeronly output 
SET NOCOUNT ON 
GO 
CREATE PROCEDURE dbo.restoreheaderonly 
	@backuplocation VARCHAR(MAX)  
AS 
	BEGIN
		RESTORE FILELISTONLY 
		FROM DISK = @backuplocation 
	END
GO