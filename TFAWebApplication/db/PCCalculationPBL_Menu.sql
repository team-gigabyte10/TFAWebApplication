USE [SystemManager]
GO

DECLARE @ReportId INT = 1100342;

DELETE FROM ReportSuiteField
WHERE ReportId = @ReportId;

DELETE FROM ReportSuite
WHERE ReportId = @ReportId;

INSERT INTO ReportSuite
	(ReportId, ApplicationId, ParentId, DisplayName, ReportName, ReportPath, ConName, SeqNo, IsVisible)
VALUES
	(@ReportId, 2, 380, 'PC Calculation', 'PCCalculationPBL.rdl', '\\Reports\Transaction\', 'OTS', 22, 1);

INSERT INTO ReportSuiteField
	(ReportFieldId, ReportId, ValueField, LabelField, Label, DefaultValue, FieldType, MapField, IsSysParameter, ReferenceSource, Operators, FilterOnly, SeqNo, MultiSelect)
VALUES
	(@ReportId * 100 + 1, @ReportId, 'FromDate', 'FromDate', 'From Disburse Date', NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 1, 0),
	(@ReportId * 100 + 2, @ReportId, 'ToDate', 'ToDate', 'To Disburse Date', NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 2, 0),
	(@ReportId * 100 + 3, @ReportId, 'BranchID', 'BranchName', 'Branch Name', NULL, 'String', NULL, 0, 'SELECT DISTINCT BPB.BranchID, BPB.BranchName FROM SystemManager..BankProfileBranch BPB WHERE BPB.IsDeleted = 0', NULL, 0, 3, 1),
	(@ReportId * 100 + 4, @ReportId, 'CustomerID', 'CustomerName', 'Customer Name', NULL, 'String', NULL, 0, 'SELECT DISTINCT CPM.CustomerID, CPM.CustomerName FROM SystemManager..CustomerProfileMaster CPM WHERE CPM.IsDeleted = 0', NULL, 0, 4, 1);
GO

