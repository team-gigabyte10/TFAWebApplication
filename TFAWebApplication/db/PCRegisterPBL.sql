USE EFA
GO

Create Or Alter Proc spRPT_PCRegisterPBL
	@FromDate Date,
	@ToDate Date
As

 -- spRPT_PCRegisterPBL '2024-01-01', '2026-10-27'

 -- PC Register (columns of Doc\PC Register.xlsx)
 -- Data source: PC Disbursement Interface (table PCDisbursementMaster).
 -- Table PCDisbursement has no rows for these loans, so it is only used for the adjustment amount.
 -- One row for each PC/TL record. A record must be authorized (IsCheck = 1) and not deleted.
 -- Disburse date = PCDisburseDate (or else PCCreationDate), between @FromDate and @ToDate.
 -- Customer name and Branch name are plain names, like spRPT_MarginRegisterPBL.
 --   Branch = branch of the group (GroupLC.BankBranchID), or else the branch of the record.
 -- PC/TL Number         = AdditionalFilter (example TOPCBD00101100000126).
 -- Loan Currency        = BDT, because Loan Amount is the taka amount (PCAmountTK).
 -- PC/TL Condition      = MasterDocID (example PC_Condition_1).
 -- PCT of PC Disbursement = DrawdownPercentage.
 -- Loan Amount          = PCAmountTK.
 -- Loan Out Amt         = PRINCIPAL_OS, or Loan Amount when PRINCIPAL_OS is 0 (nothing is repaid yet).
 -- Adjusted Amount      = sum of AdjustmentAmount in PCDisbursement (0 when none).
 -- Adjusted Date        = last update date of the PCDisbursement rows that have an adjustment.
 -- Last Modified by     = UpdatedBy, or else AddedBy.
 -- BranchID and CustomerID are not shown. The Report Viewer menu uses them for its Bank Branch and Customer Name filters
 -- (SystemManager ReportSuiteField, ReportId 1100340), so the procedure has only the two dates.

Begin
	Set NoCount On;

	select
		BPB.BranchName																BranchName,
		CPM.CustomerName															CustomerName,
		CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) As Date)				DisburseDate,
		PCM.AdditionalFilter														PCNumber,
		GLC.GroupRefNo																GroupRefNo,
		'BDT'																		LoanCurrency,
		PCM.InterestRate															InterestRate,
		PCM.ExchangeRate															ExchangeRate,
		PCM.MasterDocID																PCCondition,
		PCM.DrawdownPercentage														PctOfPCDisbursement,
		PCM.PCAmountTK																LoanAmount,
		CAST(PCM.MATURITY_DATE As Date)												MaturityDate,
		ISNULL(NULLIF(PCM.PRINCIPAL_OS, 0), PCM.PCAmountTK)							LoanOutAmt,
		ISNULL(ADJ.AdjustmentAmount, 0)												AdjustedAmount,
		CAST(ADJ.AdjustedDate As Date)												AdjustedDate,
		ISNULL(PCM.UpdatedBy, PCM.AddedBy)											LastModifiedBy,
		ISNULL(GLC.BankBranchID, PCM.BranchID)										BranchID,
		PCM.CustomerID																CustomerID
	from PCDisbursementMaster PCM with(nolock)
		left join
		(
			select
				PCDMID,
				SUM(AdjustmentAmount)														AdjustmentAmount,
				MAX(case when AdjustmentAmount <> 0 then DateUpdated end)					AdjustedDate
			from PCDisbursement with(nolock)
			group by PCDMID
		) ADJ on ADJ.PCDMID = PCM.PCDMID
		left join GroupLC GLC with(nolock) on GLC.GroupSysID = PCM.GroupRefID
		left join SystemManager.dbo.CustomerProfileMaster CPM with(nolock) on CPM.CustomerID = PCM.CustomerID
		left join SystemManager..BankProfileBranch BPB with(nolock) on BPB.BranchID = ISNULL(GLC.BankBranchID, PCM.BranchID)
	where PCM.IsDeleted = 0
		and PCM.IsCheck = 1
		and CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) As Date) >= @FromDate
		and CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) As Date) <= @ToDate
	order by BPB.BranchName, CPM.CustomerName, ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate), PCM.AdditionalFilter
End
GO
