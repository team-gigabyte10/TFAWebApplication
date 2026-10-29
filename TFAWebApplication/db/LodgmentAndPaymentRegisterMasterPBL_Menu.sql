USE SystemManager
GO

-- "FDBC - Lodgment and Payment Register-Master" (ReportId 1100). The Excel "FDBC - Lodgment and Payment Register" has no
-- Non-AD Branch parameter, and the report has no Non-AD Branch column now. Remove the filter.
-- The other filters of the Excel are already in ReportSuiteField.

Delete From ReportSuiteField
Where ReportId = 1100 And ReportFieldId = 11007 And ValueField = 'BranchID'
GO
