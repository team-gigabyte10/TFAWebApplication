USE [SystemManager]
GO

/****** 
  Script: CustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL_Menu_Fix.sql
  Purpose: 
    1. Fixes slow/hanging customer dropdown by optimizing ReferenceSource with WITH(NOLOCK)
    2. Ensures AsOnDate, CustomerID, and BranchID parameters are properly registered in ReportSuiteField
******/

DECLARE @ReportName VARCHAR(200) = 'CustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL.rdl';
DECLARE @ReportId INT;

SELECT @ReportId = ReportId 
FROM ReportSuite WITH(NOLOCK) 
WHERE ReportName LIKE '%' + @ReportName + '%' OR DisplayName LIKE '%Customer Wise BTB LC, Accepted Bills%';

IF @ReportId IS NOT NULL
BEGIN
    PRINT 'Found ReportId: ' + CAST(@ReportId AS VARCHAR(20));

    -- 1. Ensure AsOnDate parameter exists
    IF NOT EXISTS (SELECT 1 FROM ReportSuiteField WHERE ReportId = @ReportId AND ValueField = 'AsOnDate')
    BEGIN
        INSERT INTO ReportSuiteField (ReportFieldId, ReportId, ValueField, LabelField, Label, DefaultValue, FieldType, MapField, IsSysParameter, ReferenceSource, Operators, FilterOnly, SeqNo, MultiSelect)
        VALUES (@ReportId * 100 + 1, @ReportId, 'AsOnDate', 'AsOnDate', 'As On Date', NULL, 'DateTime', NULL, 0, NULL, NULL, 0, 1, 0);
        PRINT 'Added AsOnDate parameter.';
    END

    -- 2. Ensure BranchID parameter exists with fast NOLOCK query
    IF NOT EXISTS (SELECT 1 FROM ReportSuiteField WHERE ReportId = @ReportId AND ValueField = 'BranchID')
    BEGIN
        INSERT INTO ReportSuiteField (ReportFieldId, ReportId, ValueField, LabelField, Label, DefaultValue, FieldType, MapField, IsSysParameter, ReferenceSource, Operators, FilterOnly, SeqNo, MultiSelect)
        VALUES (@ReportId * 100 + 2, @ReportId, 'BranchID', 'BranchName', 'Branch Name', NULL, 'String', NULL, 0, 
                'SELECT DISTINCT BPB.BranchID, BPB.BranchName FROM SystemManager..BankProfileBranch BPB WITH(NOLOCK) WHERE BPB.IsDeleted = 0 ORDER BY BPB.BranchName', 
                NULL, 0, 2, 0);
        PRINT 'Added BranchID parameter.';
    END
    ELSE
    BEGIN
        UPDATE ReportSuiteField
        SET ReferenceSource = 'SELECT DISTINCT BPB.BranchID, BPB.BranchName FROM SystemManager..BankProfileBranch BPB WITH(NOLOCK) WHERE BPB.IsDeleted = 0 ORDER BY BPB.BranchName'
        WHERE ReportId = @ReportId AND ValueField = 'BranchID';
        PRINT 'Updated BranchID dropdown ReferenceSource.';
    END

    -- 3. Ensure CustomerID parameter exists with fast indexed NOLOCK query (resolves UI hanging)
    IF NOT EXISTS (SELECT 1 FROM ReportSuiteField WHERE ReportId = @ReportId AND ValueField = 'CustomerID')
    BEGIN
        INSERT INTO ReportSuiteField (ReportFieldId, ReportId, ValueField, LabelField, Label, DefaultValue, FieldType, MapField, IsSysParameter, ReferenceSource, Operators, FilterOnly, SeqNo, MultiSelect)
        VALUES (@ReportId * 100 + 3, @ReportId, 'CustomerID', 'CustomerName', 'Customer Name', NULL, 'String', NULL, 0, 
                'SELECT DISTINCT CPM.CustomerID, CPM.CustomerName FROM SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) WHERE CPM.IsDeleted = 0 ORDER BY CPM.CustomerName', 
                NULL, 0, 3, 0);
        PRINT 'Added CustomerID parameter.';
    END
    ELSE
    BEGIN
        UPDATE ReportSuiteField
        SET ReferenceSource = 'SELECT DISTINCT CPM.CustomerID, CPM.CustomerName FROM SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) WHERE CPM.IsDeleted = 0 ORDER BY CPM.CustomerName'
        WHERE ReportId = @ReportId AND ValueField = 'CustomerID';
        PRINT 'Updated CustomerID dropdown ReferenceSource with fast non-locking query.';
    END

    -- Display current parameters for verification
    SELECT 
        RS.ReportId,
        RS.DisplayName,
        RS.ReportName,
        RF.ReportFieldId,
        RF.ValueField,
        RF.LabelField,
        RF.Label,
        RF.FieldType,
        CAST(RF.ReferenceSource AS VARCHAR(2000)) AS ReferenceSource,
        RF.SeqNo
    FROM ReportSuite RS WITH(NOLOCK)
    INNER JOIN ReportSuiteField RF WITH(NOLOCK) ON RF.ReportId = RS.ReportId
    WHERE RS.ReportId = @ReportId
    ORDER BY RF.SeqNo;
END
ELSE
BEGIN
    PRINT 'Report ' + @ReportName + ' was not found in ReportSuite. Please check the report name in ReportSuite table.';
END
GO
