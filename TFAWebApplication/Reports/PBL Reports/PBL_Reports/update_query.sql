--1. BTB LC Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 224;

--2. LC Amendment Advising Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 386;

--3. Customer Profile

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 1213;

--4. Lien Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 503;

--5. PC Calculation

INSERT INTO [SystemManager].[dbo].[ReportSuite] (
    [ReportId],
    [ApplicationId],
    [ParentId],
    [DisplayName],
    [ReportName],
    [ReportPath],
    [ConName],
    [SeqNo],
    [IsVisible]
)
VALUES (1218, 2, 380, 'PC Calculation', 'PCCalculationPBL.rdl', '\\Reports\Transaction\', 'OTS', 5, 1);

INSERT INTO [SystemManager].[dbo].[ReportSuiteField] (
    [ReportFieldId],
    [ReportId],
    [ValueField],
    [LabelField],
    [Label],
    [DefaultValue],
    [FieldType],
    [MapField],
    [IsSysParameter],
    [ReferenceSource],
    [Operators],
    [FilterOnly],
    [SeqNo],
    [MultiSelect]
)

VALUES (1341, 1218, 'FromDate',     'FromDate',     'From Date',   NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 1, 0),
       (1342, 1218, 'ToDate',       'ToDate',       'To Date',     NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 2, 0),
       (1343, 1218, 'BranchID', 'BranchName', 'Bank Branch', NULL, 'String',   NULL, 0, 'SELECT DISTINCT BPB.BranchID, BPB.BranchName FROM [SystemManager]..[BankProfileBranch] BPB WITH(NOLOCK) WHERE BPB.IsDeleted = 0 ORDER BY BPB.BranchName ASC', NULL, 0, 3, 0), 
       (1344, 1218, 'CustomerID',       'CustomerName',       ' Customer Name',   NULL, 'String',   NULL, 0, 'SELECT DISTINCT CPM.CustomerName + '' - '' + CPM.CIF AS CustomerName, CPM.CustomerID FROM SystemManager..CustomerProfileMaster CPM WHERE CPM.IsDeleted = 0', NULL, 0, 4, 0);
