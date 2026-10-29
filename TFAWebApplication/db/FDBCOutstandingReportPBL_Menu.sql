USE SystemManager
GO

-- Report Viewer menu entry and filters for "FDBC - Outstanding Report" (FDBCOutstandingReportPBL.rdl).
-- Run db/FDBCOutstandingReportPBL.sql first. The filters use the ID columns returned by spRPT_FDBCOutstandingReportPBL.
-- The script can run more than once. It removes the old rows of the report first.

Declare @ReportId int = 1100341

Delete From ReportSuiteField Where ReportId = @ReportId
Delete From ReportSuite Where ReportId = @ReportId

Insert Into ReportSuite (ReportId, ApplicationId, ParentId, DisplayName, ReportName, ReportPath, ConName, SeqNo, IsVisible)
Values (@ReportId, 2, 380, 'FDBC - Outstanding Report', 'FDBCOutstandingReportPBL.rdl', '\\Reports\Transaction\', 'OTS', 21, 1)

Insert Into ReportSuiteField
	(ReportFieldId, ReportId, ValueField, LabelField, Label, DefaultValue, FieldType, MapField, IsSysParameter, ReferenceSource, Operators, FilterOnly, SeqNo, MultiSelect)
Values
	(@ReportId * 100 + 1, @ReportId, 'FromDate', 'FromDate', 'From Lodgement Date', NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 1, 0),
	(@ReportId * 100 + 2, @ReportId, 'ToDate', 'ToDate', 'To Lodgement Date', NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 2, 0),
	-- All FDBC numbers, cancelled bills too (no IsCancelled filter)
	(@ReportId * 100 + 3, @ReportId, 'EBIID', 'ExportBillNo', 'FDBC Number', NULL, 'String', NULL, 0,
		'Select ebim.EBIID,ebim.ExportBillNo from efa..ExportBillInitiationMaster ebim where ebim.ExportBillNo is not null', NULL, 0, 3, 1),
	(@ReportId * 100 + 4, @ReportId, 'CustomerID', 'CustomerName', 'Client''s Name', NULL, 'String', NULL, 0,
		'SELECT DISTINCT CPM.CustomerName,CPM.CustomerID FROM SystemManager..CustomerProfileMaster CPM
	Union
	Select BeneficiaryName=c.Name,BMID=c.Code
	from SystemManager..contacts c
	Inner Join SystemManager..ContactPersonChild ct on ct.Code = c.Code
	where ct.ContactType=''Beneficiary''', NULL, 0, 4, 1),
	(@ReportId * 100 + 5, @ReportId, 'ApplicantID', 'Name', 'Buyer''s/Applicant''s Name', NULL, 'String', NULL, 0,
		'SELECT DISTINCT c.Name,c.Code ApplicantID FROM SystemManager..Contacts c', NULL, 0, 5, 1),
	(@ReportId * 100 + 6, @ReportId, 'ADBranchID', 'BranchName', 'AD Branch Name', NULL, 'String', NULL, 0,
		'SELECT BranchID ADBranchID, BranchName FROM SystemManager..BankProfileBranch BPB WHERE BPB.IsDeleted = 0 and isadcode=1', NULL, 0, 6, 1),
	(@ReportId * 100 + 7, @ReportId, 'EPZnonEPZ', 'EPZnonEPZ', 'EPZ/NON-EPZ', NULL, 'String', NULL, 0,
		'SELECT EPZnonEPZ=''EPZ'' Union SELECT EPZnonEPZ=''NON-EPZ''', NULL, 0, 7, 1),
	(@ReportId * 100 + 8, @ReportId, 'PaymentTerm', 'PaymentTermName', 'Payment Term', NULL, 'String', NULL, 0,
		'SELECT PaymentTerm=''AtSight'' ,PaymentTermName=''At Sight'' union SELECT PaymentTerm=''Deferred'',PaymentTermName=''Deferred'' union SELECT PaymentTerm=''Mixed'' ,PaymentTermName=''Mixed'' union SELECT PaymentTerm=''Advanced'',PaymentTermName=''Advanced''', NULL, 0, 8, 1),
	(@ReportId * 100 + 9, @ReportId, 'MasterDocID', 'LCNo', 'LC Number', NULL, 'String', NULL, 0,
		'SELECT distinct md.MasterDocID,md.LCNo FROM ExportBillInitiationMaster ebim
left Join EFA..MasterDoc md on ebim.MasterDocID=md.MasterDocID
LEFT Join EFA..LCAdvisingRegister lca on lca.LCReceiveID=ebim.MasterDocID
WHERE md.IsDeleted = 0 AND md.IsCancelled = 0', NULL, 0, 9, 1)
GO
