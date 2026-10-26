USE master;
GO

IF DB_ID(N'MLOpsDB_25280091') IS NOT NULL
BEGIN
	ALTER DATABASE MLOpsDB_25280091 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE MLOpsDB_25280091;
END;
GO

CREATE DATABASE MLOpsDB_25280091
ON PRIMARY
(
	NAME = N'MLOpsDB_25280091_Primary',
	FILENAME = N'/var/opt/mssql/data/MLOpsDB_25280091_Primary.mdf'
);
GO

USE MLOpsDB_25280091;
GO

-- 1) Filegroups (F1..F4)
ALTER DATABASE MLOpsDB_25280091 ADD FILEGROUP FG_F1;
ALTER DATABASE MLOpsDB_25280091 ADD FILEGROUP FG_F2;
ALTER DATABASE MLOpsDB_25280091 ADD FILEGROUP FG_F3;
ALTER DATABASE MLOpsDB_25280091 ADD FILEGROUP FG_F4;
GO

-- 2) Files per filegroup placed across the 4 volumes (V1..V4)
ALTER DATABASE MLOpsDB_25280091 ADD FILE
(
	NAME = N'MLOps_F1_01',
	FILENAME = N'/var/opt/mssql/data/MLOps_F1_01.ndf'
) TO FILEGROUP FG_F1;

ALTER DATABASE MLOpsDB_25280091 ADD FILE
(
	NAME = N'MLOps_F2_01',
	FILENAME = N'/var/opt/mssql/v2/MLOps_F2_01.ndf'
) TO FILEGROUP FG_F2;

ALTER DATABASE MLOpsDB_25280091 ADD FILE
(
	NAME = N'MLOps_F3_01',
	FILENAME = N'/var/opt/mssql/v3/MLOps_F3_01.ndf'
) TO FILEGROUP FG_F3;

ALTER DATABASE MLOpsDB_25280091 ADD FILE
(
	NAME = N'MLOps_F4_01',
	FILENAME = N'/var/opt/mssql/v4/MLOps_F4_01.ndf'
) TO FILEGROUP FG_F4;
GO

-- 3) Partition functions
CREATE PARTITION FUNCTION PF_T1_ByYear (DATE)
AS RANGE LEFT FOR VALUES ('2024-12-31');
GO

CREATE PARTITION FUNCTION PF_T2_ByYear (DATE)
AS RANGE LEFT FOR VALUES ('2023-12-31', '2024-12-31');
GO

-- 4) Partition schemes mapping partitions -> filegroups
-- T1: P1 -> FG_F1 (V1), P2 -> FG_F2 (V2)
CREATE PARTITION SCHEME PS_T1_ByYear
AS PARTITION PF_T1_ByYear
TO (FG_F1, FG_F2);
GO

-- T2: P1 -> FG_F1 (V1), P2 -> FG_F3 (V3), P3 -> FG_F4 (V4)
CREATE PARTITION SCHEME PS_T2_ByYear
AS PARTITION PF_T2_ByYear
TO (FG_F1, FG_F3, FG_F4);
GO
-- Two tables (T1, T2) partitioned by date on their schemes.
CREATE TABLE dbo.T1
(
	Id INT IDENTITY(1, 1) NOT NULL,
	DataDate DATE NOT NULL,
	Payload NVARCHAR(100) NULL
) ON PS_T1_ByYear (DataDate);

CREATE TABLE dbo.T2
(
	Id INT IDENTITY(1, 1) NOT NULL,
	DataDate DATE NOT NULL,
	Payload NVARCHAR(100) NULL
) ON PS_T2_ByYear (DataDate);
GO





INSERT INTO dbo.T1 (DataDate, Payload)
VALUES
	('2023-06-01', N'a'),
	('2024-06-01', N'b'),
	('2025-06-01', N'c'),
	('2026-06-01', N'd');

INSERT INTO dbo.T2 (DataDate, Payload)
VALUES
	('2023-12-31', N'x'),
	('2024-12-31', N'y'),
	('2025-12-31', N'z'),
	('2026-01-01', N'w');
GO

-- Show filegroup per partition for each table
SELECT
	OBJECT_NAME(p.object_id) AS TableName,
	p.partition_number AS PartitionNumber,
	fg.name AS FilegroupName,
	p.rows AS NumberOfRows
FROM sys.partitions p
JOIN sys.indexes i
	ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.destination_data_spaces dds
	ON dds.partition_scheme_id = i.data_space_id AND dds.destination_id = p.partition_number
JOIN sys.filegroups fg
	ON fg.data_space_id = dds.data_space_id
WHERE OBJECT_NAME(p.object_id) IN ('T1', 'T2')
	AND i.index_id IN (0, 1)
ORDER BY TableName, PartitionNumber;