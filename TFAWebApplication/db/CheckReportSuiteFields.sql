USE SystemManager
GO

-- Shows how the Report Viewer menu defines the parameters (Customer Name, Bank Branch) of a report.
-- It only reads data. Run it in SSMS and send the 2 result sets to Claude.

-- Result 1: the report entries
select RS.ReportId, RS.DisplayName, RS.ReportName, RS.ReportPath, RS.ConName, RS.IsVisible
from ReportSuite RS WITH(NOLOCK)
where RS.DisplayName in ('Margin Register', 'Summary Statement Of Overdue Accepted Bills')
   or RS.DisplayName like '%LC Advising%'
   or RS.ReportName like '%MarginRegister%'
   or RS.ReportName like '%LCAdvising%'
   or RS.ReportName like '%SummaryStatementOfOverdue%'

-- Result 2: the parameters of those reports
select RS.DisplayName, RF.ReportFieldId, RF.ValueField, RF.LabelField, RF.Label, RF.DefaultValue, RF.FieldType,
	RF.MapField, RF.IsSysParameter, RF.Operators, RF.FilterOnly, RF.SeqNo, RF.MultiSelect,
	CAST(RF.ReferenceSource As Varchar(2000)) ReferenceSource
from ReportSuite RS WITH(NOLOCK)
	Inner Join ReportSuiteField RF WITH(NOLOCK) ON RF.ReportId = RS.ReportId
where RS.DisplayName in ('Margin Register', 'Summary Statement Of Overdue Accepted Bills')
   or RS.DisplayName like '%LC Advising%'
   or RS.ReportName like '%MarginRegister%'
   or RS.ReportName like '%LCAdvising%'
   or RS.ReportName like '%SummaryStatementOfOverdue%'
order by RS.DisplayName, RF.SeqNo
