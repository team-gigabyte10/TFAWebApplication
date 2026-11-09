USE EFA
GO

Create Or Alter Proc spRPT_FDBCOutstandingReportPBL
	@FromDate Date,
	@ToDate Date
As

 -- spRPT_FDBCOutstandingReportPBL '2022-01-01', '2026-12-31'

 -- FDBC Outstanding Report for export bills. Used by FDBCOutstandingReportPBL.rdl.
 -- One row for each outstanding export bill (ExportBillInitiationMaster).
 -- Lodgment date = BillGenerationDate, between @FromDate and @ToDate.
 -- Outstanding bill = the bill is not deleted, not cancelled, and has no realization:
 --   no PRS distribution row sent to CBS (and not reversed), and no ARV (export proceeds against RMT) adjustment.
 -- Overdue_Days = days after the maturity date (today - maturity date). The value is empty when the bill is not yet due.
 -- Out_Amt_In_Tk = Bill Amount * MID RATE (SystemManager..CurrencyLatestRate). BDT uses rate 1.
 --   The value is empty when the currency has no MID RATE.
 -- Branch Name = branch of the bill (ebim.BranchID). The LC/SC branches are the fallback.
 -- Transaction_Ref = ExternalID, or CBSRefNo when ExternalID is empty.
 -- Maturity date and Banks Accept Date come from Export Bill Monitoring. Export Bill Initiation is the fallback.
 -- BranchID, CustomerID, ApplicantID, EBIID and other ID columns are not shown. The Report Viewer filters use them.

Begin
	Set NoCount On;

	select
		SlNo				= row_number() over (order by Rtrim(Ltrim(ebim.ExportBillNo)), ebim.EBIID),
		BranchName			= isnull(BillBranch.BranchName, isnull(isnull(ADBranch.BranchName, ADBranch2.BranchName), isnull(Branch.BranchName, Branch2.BranchName))),
		Customer_ID			= client.CIF,
		CustomerName		= isnull(client.CustomerName, ebim.CustomerCode),
		CustomerType		= Seg.DisplayCode,
		Transaction_Ref		= isnull(nullif(ebim.ExternalID, ''), nullif(ebim.CBSRefNo, '')),
		FDBCNumber			= Rtrim(Ltrim(ebim.ExportBillNo)),
		IssueDate			= ebim.BillGenerationDate,
		InstrumentType		= case when (md.IsSC = 1 or lcar.LCSCTypeId = 'SC') then 'SC' else 'LC' end,
		BillCurr			= ebim.CURRENCY_CODE,
		BillAmount			= ebim.ExportBillAmount,
		BillType			= isnull(BillNature.DisplayCode, ebim.BillNature),
		PaymentTermFromTenor = case
			when ebim.TenorType = 'Deferred' then concat(cast(ebim.TENOR_DAYS as varchar(10)), ' Days ', TenorDes.DisplayCode)
			else tenor.DisplayCode
		end,
		MaturityDate		= isnull(ebm.MaturityDate, ebim.MaturityDate),
		Overdue_Days		= case
			when convert(date, isnull(ebm.MaturityDate, ebim.MaturityDate)) < convert(date, getdate())
			then datediff(day, isnull(ebm.MaturityDate, ebim.MaturityDate), getdate())
		end,
		LCorSCNumber		= isnull(md.LCNo, lcar.LCNumber),
		LCSC_Date			= LCAD.IssueDate,
		LCSC_Value			= LCAD.LCAmount,
		BuyerorApplicantName = isnull(applicant.Name, isnull(md.Applicant, lcar.Applicant)),
		IssuingBank			= isnull(issueingBank.Name, OpeningBank.Name),
		IssuingBranch		= IssuingBranch.Name,
		Job_Number			= GLC.GroupRefNo,
		BankAcceptDate		= isnull(ebm.AcceptanceReceivedOnDate, ebim.AcceptanceReceivedOnDate),
		Out_Amt_In_Tk		= ebim.ExportBillAmount * case when ebim.CURRENCY_CODE = 'BDT' then 1 else MR.ConvertFactor end,
		-- Parameters--
		ebim.EBIID,		-- FDBC No
		CustomerID			= isnull(ebim.CustomerCode, lcar.Beneficiary),
		ApplicantID			= isnull(md.Applicant, lcar.Applicant),
		ADBranchID			= isnull(ADBranch.BranchID, ADBranch2.BranchID),
		BranchID			= isnull(Branch.BranchID, Branch2.BranchID),
		EPZnonEPZ			= case when isnull(client.IsUsed, 0) = 1 then 'EPZ' else 'Non-EPZ' end,
		PaymentTerm			= ebim.TenorType,
		MasterDocID			= isnull(md.MasterDocID, lcar.LCReceiveID)
	from ExportBillInitiationMaster ebim with(nolock)
		LEFT JOIN ExportBillMonitoring ebm with(nolock) on ebm.EBIID = ebim.EBIID
		LEFT JOIN SystemManager..EntityFixedVariables tenor on tenor.EntityID = ebim.TenorType
		LEFT JOIN SystemManager..EntityFixedVariables tenordes on tenordes.EntityID = ebim.TenorDescription
		LEFT JOIN SystemManager..EntityFixedVariables BillNature on BillNature.EntityID = ebim.BillNature
		LEFT JOIN MasterDoc md with(nolock) on md.MasterDocID = ebim.MasterDocID
		LEFT JOIN LCAdvisingRegister lcar with(nolock) on lcar.LCReceiveID = isnull(md.LCReceiveID, ebim.MasterDocID)
		LEFT JOIN LCAdvisingRegister LCAD with(nolock) on LCAD.LCReceiveID = isnull(md.LCReceiveID, ebim.MasterDocID)
		LEFT JOIN GROUPLC GLC with(nolock) on GLC.GroupSysID = md.GroupSysID
		LEFT JOIN SystemManager..BankProfileBranch BillBranch on BillBranch.BranchID = ebim.BranchID
		LEFT JOIN SystemManager..BankProfileBranch Branch on Branch.BranchID = GLC.BankBranchID
		LEFT JOIN SystemManager..BankProfileBranch ADBranch on ADBranch.BranchID = GLC.ADBranchID
		LEFT JOIN SystemManager..BankProfileBranch Branch2 on Branch2.BranchID = LCAD.BranchID
		LEFT JOIN SystemManager..BankProfileBranch ADBranch2 on ADBranch2.BranchID = LCAD.ADBranchID
		LEFT JOIN SystemManager..Contacts applicant on applicant.Code = isnull(md.Applicant, lcar.Applicant)
		LEFT JOIN SystemManager..Contacts OpeningBank on OpeningBank.Code = isnull(md.OpeningBankCode, lcar.BankID)
		LEFT JOIN SystemManager..Contacts issueingBank on issueingBank.Code = lcar.BankID
		LEFT JOIN SystemManager..Contacts IssuingBranch on IssuingBranch.Code = lcar.BankBranchID
		LEFT JOIN SystemManager..CustomerProfileMaster client with(nolock) on client.CustomerID = ebim.CustomerCode
		LEFT JOIN SystemManager..EntityFixedVariables Seg on Seg.EntityID = client.SegmentID and Seg.EntityTypeID = 'CSEG/17/1' and Seg.IsDeleted = 0
		LEFT JOIN SystemManager..CurrencyLatestRate MR on MR.CurrencyCode = ebim.CURRENCY_CODE and rtrim(MR.RateFor) = 'MID RATE' and MR.IsDeleted = 0
	where ebim.IsDeleted = 0 and ebim.IsCancelled = 0
		and cast(ebim.BillGenerationDate as date) between @FromDate and @ToDate
		-- no PRS realization
		and not exists (
			select 1 from PRSCreationDistributionDetails P with(nolock)
			where P.BillRefNo = ebim.EBIID and P.IsDeleted = 0 and P.IsSendTransactionToCBS = 1 and P.IsReversedFromCBS = 0
		)
		-- no ARV adjustment
		and not exists (
			select 1 from ExportBillAgainstRMTAdjustmentDetails A with(nolock)
			where A.EBIIRMTD = ebim.EBIID and A.IsDeleted = 0 and A.IsCancelled = 0
		)
	order by FDBCNumber asc
End
GO
