USE EFA
GO

Create Or Alter Proc spRPT_StatementOfOverdueAcceptedBills
	@FromDate Date,
	@ToDate Date,
	@BranchID Varchar(50) = NULL,
	@CustomerID Varchar(50)
As

 -- spRPT_StatementOfOverdueAcceptedBills '2024-01-01', '2026-12-31', 'BPB/22/14', '100369732'
 -- spRPT_StatementOfOverdueAcceptedBills '2024-01-01', '2026-12-31', NULL, 'CPM/23/3'

 -- Three kinds of overdue bills are listed together:
 --   1) Import:        accepted import bills, not paid, Maturity Date before today.
 --                     Comments = remarks of the Local Export Bill Monitoring of the export LC behind the back-to-back LC.
 --   2) Foreign export: ExportBillInitiationMaster bills (Export Bill Initiation Register).
 --   3) Local export:   LocalExportBillInitiationMaster bills.
 --                     2 and 3 are overdue when Maturity Date (Export Bill Monitoring) is before today
 --                     and less than 95 percent of the bill is received.
 --                     Reason for Overdue = Export Bill Monitoring remarks, Comments = bill remarks.
 -- Delay = today minus Maturity Date, in days.
 -- Branch (shown and filtered): import = ISNULL(LC group/request branch, bill branch);
 --                              export = ISNULL(LC branch, bill branch);
 --                              if still empty = default branch of the customer (CustomerBranchMap).

Begin
	Set NoCount On;

	-- Branch when the LC and the bill have no branch: the default branch of the customer
	Declare @DefaultBranchID Varchar(50)
	select Top 1 @DefaultBranchID = BM.BranchID
	from SystemManager..CustomerBranchMap BM WITH(NOLOCK)
	where BM.CustomerID = @CustomerID and BM.IsDefault = 1
	order by BM.BranchID

	-- Step 1: money received so far for each export bill (same logic as the export overdue statement)
	select X.EBIID, SUM(X.RealizedValue) RealizedAmount
	into #Realized
	from
	(
		select M.BillRefNo EBIID, SUM(M.ProceedsRecvd) RealizedValue
		from
		(
			select P.BillRefNo, P.Date, MAX(P.ProceedsRecvd * CLRR.ConvertFactor) ProceedsRecvd
			from EFA..PRSCreationDistributionDetails P WITH(NOLOCK)
				Inner Join EFA..PRSCreationMaster PM WITH(NOLOCK) ON PM.PRSSysID = P.PRSSysID
				Left Join SystemManager..CurrencyLatestRate CLRR WITH(NOLOCK) ON CLRR.CurrencyCode = ISNULL(P.Currency, '') AND CLRR.RateFor = 'BC SELLING'
			where P.IsDeleted = 0 and P.PRSNCADID = 'NOT_NCA'
			group by P.BillRefNo, P.Date
		) M
		group by M.BillRefNo
	) X
	group by X.EBIID

	-- Step 2: export LC list. The export bill holds MasterDocID, which is a MasterDoc id or an LCAdvisingRegister id.
	-- All LC types and sales contracts are included, so a bill is not lost because of its LC type.
	select MasterDocID LCID, LCNo, Currency, LCAmount, IssueDate, AdvisingBankCode AdvisingBankID, AdvisingBankBranchId AdvisingBankBranchID, Applicant, ADBranchID
	into #ExportLC
	from EFA..MasterDoc WITH(NOLOCK)
	Union All
	select LCReceiveID, LCNumber, Currency, LCAmount, IssueDate, AdvisingBankID, AdvisingBankBranchID, Applicant, ADBranchID
	from EFA..LCAdvisingRegister WITH(NOLOCK)

	-- Step 3: all overdue bills in one list
	;With Bills As
	(
		-- 1) Import
		select
			BPB.BranchName											LCIssuingBranch,
			LC.LCNo													LCNo,
			LC.Currency												LCCurrency,
			LC.LCAmount												LCValue,
			CONVERT(Date, LC.IssueDate)								LCDate,
			LC.AdvisingBankCode										AdvisingBank,
			ISNULL(NULLIF(FDAM.NegoBankBillRef, ''), FDAM.BillNo)	BillNo,
			FDAM.Currency											BillCurrency,
			FDAM.BillAmount											BillValue,
			CONVERT(Date, FDAM.BillGenerationDate)					BillDate,
			CONVERT(Date, FDAM.AcceptanceDate)						AcceptanceDate,
			CONVERT(Date, FDAM.MATURITY_DATE)						MaturityDate,
			CP.CustomerName											Importer,
			ISNULL(EXP.Name, LC.Benificiary)						Exporter,
			FDAM.Remarks											ReasonForOverdue,
			CM.Comments												Comments
		from EFA..ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK)
			-- LC: back-to-back LCs and cash LCs in one list
			Inner Join
			(
				select BBLCID LCID, BBLCNo LCNo, Currency, BBLCAmount LCAmount, IssueDate, AdvisingBankCode, Benificiary, MasterDocID, GroupSysID
				from EFA..BBLCMaster WITH(NOLOCK)
				Union All
				select ImportLCID, ImportLCNo, Currency, ImportLCAmount, IssueDate, AdvisingBankCode, Benificiary, NULL, NULL
				from EFA..ImportLCMaster WITH(NOLOCK)
			) LC ON LC.LCID = FDAM.BBLCID
			Left Join EFA..GroupLC GL WITH(NOLOCK) ON GL.GroupSysID = LC.GroupSysID
			Left Join EFA..BBLCRequestMaster RM WITH(NOLOCK) ON RM.BBLCID = LC.LCID
			Left Join SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(ISNULL(GL.ADBranchID, RM.ADBranchID), ISNULL(FDAM.BranchID, @DefaultBranchID))
			Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON CP.CustomerID = FDAM.CustomerID AND CP.IsDeleted = 0
			Left Join SystemManager..Contacts EXP WITH(NOLOCK) ON EXP.Code = LC.Benificiary
			-- Remarks of Local Export Bill Monitoring (all remarks of the linked local export bills)
			Outer Apply
			(
				select STRING_AGG(CAST(X.Remarks As NVarchar(Max)), ', ') Comments
				from
				(
					select Distinct EBM.Remarks
					from EFA..LocalExportBillInitiationMaster LEB WITH(NOLOCK)
						Inner Join EFA..ExportBillMonitoring EBM WITH(NOLOCK) ON EBM.EBIID = LEB.EBIID AND EBM.IsDeleted = 0
					where LEB.MasterDocID = LC.MasterDocID
					  and LEB.IsDeleted = 0 and ISNULL(LEB.IsCancelled, 0) = 0
					  and ISNULL(EBM.Remarks, '') <> ''
				) X
			) CM
		where FDAM.IsDeleted = 0 and FDAM.IsCancelled = 0
		  and FDAM.BillNo Is Not Null
		  and FDAM.MATURITY_DATE Is Not Null
		  and FDAM.AcceptanceIDNo Is Not Null
		  and FDAM.IsUPAS = 0
		  and FDAM.RemittedAmount = 0 and FDAM.RemittedThrough Is Null
		  -- overdue: maturity date has passed
		  and CAST(FDAM.MATURITY_DATE As Date) < CAST(GETDATE() As Date)
		  -- not paid: no payment voucher and no import-payment margin encashment
		  and Not Exists
			(
				select 1
				from EFA..CustomerVoucherTransDetails V WITH(NOLOCK)
					Inner Join SystemManager..BankProfileNostroAccounts N WITH(NOLOCK) ON N.AccountNo = V.CreditAccountNo AND N.IsDeleted = 0
				where V.AdditionalFilter = 'Foreign Document Acceptance Master' and V.AdditionalMasterID = FDAM.ExternalID
			)
		  and Not Exists
			(
				select 1
				from EFA..MarginEncashmentMaster E WITH(NOLOCK)
					Inner Join EFA..MarginTransactionDetails T WITH(NOLOCK) ON T.MAEMID = E.MAEMID AND T.IsSendTransactionToCBS = 1
					Inner Join SystemManager..BankProfileNostroAccounts N WITH(NOLOCK) ON N.AccountNo = T.AccountNo AND N.IsDeleted = 0
					Inner Join SystemManager..EntityFixedVariables EV WITH(NOLOCK) ON EV.EntityID = E.ExportBillType AND EV.DisplayCode = 'Import Payment'
				where E.BillOrLoanID = FDAM.FDAID and E.IsBill = 1
			)
		  -- report filters
		  and CAST(FDAM.BillGenerationDate As Date) between @FromDate and @ToDate
		  and (@BranchID Is Null or @BranchID = '' or ISNULL(ISNULL(GL.ADBranchID, RM.ADBranchID), ISNULL(FDAM.BranchID, @DefaultBranchID)) = @BranchID)
		  and FDAM.CustomerID = @CustomerID

		Union All

		-- 2) Foreign export bills
		select
			BPB.BranchName,
			LC.LCNo,
			LC.Currency,
			LC.LCAmount,
			CONVERT(Date, LC.IssueDate),
			ISNULL(AdvBank.Name, '') + ', ' + ISNULL(AdvBranch.Name, ''),
			EB.ExportBillNo,
			EB.CURRENCY_CODE,
			EB.ExportBillAmount,
			CONVERT(Date, EB.BillGenerationDate),
			CONVERT(Date, EBM.AcceptanceReceivedOnDate),
			CONVERT(Date, EBM.MaturityDate),
			Applicant.Name,
			CP.CustomerName,
			EBM.Remarks,
			EB.Remarks
		from EFA..ExportBillInitiationMaster EB WITH(NOLOCK)
			Inner Join EFA..ExportBillMonitoring EBM WITH(NOLOCK) ON EBM.EBIID = EB.EBIID AND EBM.IsDeleted = 0
			Left Join #ExportLC LC ON LC.LCID = EB.MasterDocID
			Left Join #Realized R ON R.EBIID = EB.EBIID
			Left Join SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(ISNULL(LC.ADBranchID, EB.BranchID), @DefaultBranchID)
			Left Join SystemManager..Contacts AdvBank WITH(NOLOCK) ON AdvBank.Code = ISNULL(LC.AdvisingBankID, '')
			Left Join SystemManager..Contacts AdvBranch WITH(NOLOCK) ON AdvBranch.Code = ISNULL(LC.AdvisingBankBranchID, '')
			Left Join SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = ISNULL(LC.Applicant, '')
			Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON CP.CustomerID = EB.CustomerCode
		where ISNULL(EB.IsCancelled, 0) = 0 and EB.IsDeleted = 0
		  and EBM.MaturityDate Is Not Null
		  and CAST(EBM.MaturityDate As Date) < CAST(GETDATE() As Date)
		  and (ISNULL(R.RealizedAmount, 0) / NULLIF(EB.ExportBillAmount, 0)) * 100 < 95
		  and CAST(EB.BillGenerationDate As Date) between @FromDate and @ToDate
		  and (@BranchID Is Null or @BranchID = '' or ISNULL(ISNULL(LC.ADBranchID, EB.BranchID), @DefaultBranchID) = @BranchID)
		  and EB.CustomerCode = @CustomerID

		Union All

		-- 3) Local export bills
		select
			BPB.BranchName,
			LC.LCNo,
			LC.Currency,
			LC.LCAmount,
			CONVERT(Date, LC.IssueDate),
			ISNULL(AdvBank.Name, '') + ', ' + ISNULL(AdvBranch.Name, ''),
			LEB.ExportLocalBillNo,
			LEB.CURRENCY_CODE,
			LEB.ExportLocalBillAmount,
			CONVERT(Date, LEB.BillGenerationDate),
			CONVERT(Date, EBM.AcceptanceReceivedOnDate),
			CONVERT(Date, EBM.MaturityDate),
			Applicant.Name,
			CP.CustomerName,
			EBM.Remarks,
			LEB.Remarks
		from EFA..LocalExportBillInitiationMaster LEB WITH(NOLOCK)
			Inner Join EFA..ExportBillMonitoring EBM WITH(NOLOCK) ON EBM.EBIID = LEB.EBIID AND EBM.IsDeleted = 0
			Left Join #ExportLC LC ON LC.LCID = LEB.MasterDocID
			Left Join #Realized R ON R.EBIID = LEB.EBIID
			Left Join SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(ISNULL(LC.ADBranchID, LEB.BranchID), @DefaultBranchID)
			Left Join SystemManager..Contacts AdvBank WITH(NOLOCK) ON AdvBank.Code = ISNULL(LC.AdvisingBankID, '')
			Left Join SystemManager..Contacts AdvBranch WITH(NOLOCK) ON AdvBranch.Code = ISNULL(LC.AdvisingBankBranchID, '')
			Left Join SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = ISNULL(LC.Applicant, '')
			Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON CP.CustomerID = LEB.CustomerCode
		where ISNULL(LEB.IsCancelled, 0) = 0 and LEB.IsDeleted = 0
		  and EBM.MaturityDate Is Not Null
		  and CAST(EBM.MaturityDate As Date) < CAST(GETDATE() As Date)
		  and (ISNULL(R.RealizedAmount, 0) / NULLIF(LEB.ExportLocalBillAmount, 0)) * 100 < 95
		  and CAST(LEB.BillGenerationDate As Date) between @FromDate and @ToDate
		  and (@BranchID Is Null or @BranchID = '' or ISNULL(ISNULL(LC.ADBranchID, LEB.BranchID), @DefaultBranchID) = @BranchID)
		  and LEB.CustomerCode = @CustomerID
	)

	-- Step 4: final report columns
	select
		[Sl]										= ROW_NUMBER() OVER (ORDER BY B.MaturityDate, B.BillNo),
		[Name of the LC Issuing Branch]				= B.LCIssuingBranch,
		[LC/ Contract Number]						= B.LCNo,
		[LC Quoted Currency]						= B.LCCurrency,
		[LC/ Contract Value]						= B.LCValue,
		[LC/ Contract date]							= B.LCDate,
		[Name of the LC Advising Bank & Branch]		= B.AdvisingBank,
		[Bill No.]									= B.BillNo,
		[Bill Quoted Currency]						= B.BillCurrency,
		[Bill Value]								= B.BillValue,
		[Date of Bill]								= B.BillDate,
		[Date of Acceptance]						= B.AcceptanceDate,
		[Date of Maturity]							= B.MaturityDate,
		[Delay]										= DATEDIFF(DAY, B.MaturityDate, GETDATE()),
		[Name of the Importer]						= B.Importer,
		[Name of the Exporter]						= B.Exporter,
		[Reason for Overdue]						= B.ReasonForOverdue,
		[Comments]									= B.Comments
	from Bills B
	order by B.MaturityDate, B.BillNo

	Drop Table #Realized
	Drop Table #ExportLC
End
GO
