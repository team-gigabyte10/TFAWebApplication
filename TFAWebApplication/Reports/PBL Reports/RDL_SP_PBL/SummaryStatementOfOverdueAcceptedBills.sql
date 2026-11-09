USE EFA
GO

Create Or Alter Proc spRPT_SummaryStatementOfOverdueAcceptedBills
	@FromDate Date,
	@ToDate Date
As

 -- spRPT_SummaryStatementOfOverdueAcceptedBills '2025-01-01', '2025-04-30'

 -- One row for each overdue bill, with its customer and branch (like spRPT_LCAdvisingReport).
 -- The report filters the rows by Customer and Branch (both optional) and adds them up into 9 lines:
 --   1,2 Local payables        4,5 Foreign payables        7,8 Local receivables
 --   3 = 1+2                   6 = 4+5                     9 = 7+8
 -- Sl in this result: 1 = Local payable, 4 = Foreign payable, 7 = Local receivable, 8 = Local receivable (court case)
 -- Payables   = overdue accepted import bills (same rule as spRPT_StatementOfOverdueAcceptedBills),
 --              Local when ForeignDocumentAcceptanceMaster.Origin = 'Local', otherwise Foreign.
 -- Receivables = overdue local export bills (ExportBillMonitoring), split by IsCourtCase.
 -- There is no court case flag on accepted import bills, so lines 2 and 5 are always 0.
 -- Only bills with BillGenerationDate between @FromDate and @ToDate are counted.
 -- A bill is overdue when its maturity date is on or before @ToDate.

Begin
	Set NoCount On;

	Declare @USDSelling Numeric(18, 4), @USDMid Numeric(18, 4)
	select @USDSelling = ConvertFactor from SystemManager..CurrencyLatestRate WITH(NOLOCK) where RateFor = 'BC SELLING' and CurrencyCode = 'USD'
	select @USDMid     = ConvertFactor from SystemManager..CurrencyLatestRate WITH(NOLOCK) where RateFor = 'MID RATE'   and CurrencyCode = 'USD'

	-- Money received so far for each local export bill (same logic as the export overdue statement)
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

	-- Payables (Sl 1 and 4): overdue accepted import bills that are not paid
	select
		Case When ISNULL(FDAM.Origin, '') = 'Local' Then 1 Else 4 End	Sl,
		FDAM.CustomerID													CustomerID,
		CP.CustomerName													Customer,
		FDAM.BranchID													BranchID,
		BPB.BranchName													Branch,
		CAST(ISNULL(ISNULL(FDAM.BillAmount, 0) * ISNULL(CLR.ConvertFactor, 0) / NULLIF(@USDSelling, 0), 0) As Numeric(18, 2))	BillValueUSD
	from EFA..ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK)
		Left Join SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = FDAM.Currency AND CLR.RateFor = 'BC SELLING'
		Left Join SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON FDAM.BranchID = BPB.BranchID AND BPB.IsDeleted = 0
		Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON FDAM.CustomerID = CP.CustomerID AND CP.IsDeleted = 0
	where FDAM.IsDeleted = 0 and FDAM.IsCancelled = 0
	  and FDAM.BillNo Is Not Null
	  and FDAM.MATURITY_DATE Is Not Null
	  and FDAM.AcceptanceIDNo Is Not Null
	  and FDAM.IsUPAS = 0
	  and FDAM.RemittedAmount = 0 and FDAM.RemittedThrough Is Null
	  and CAST(FDAM.MATURITY_DATE As Date) <= @ToDate
	  and CAST(FDAM.BillGenerationDate As Date) between @FromDate and @ToDate
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

	Union All

	-- Receivables (Sl 7 and 8): overdue local export bills, split by court case
	select
		Case When EBM.IsCourtCase = 1 Then 8 Else 7 End					Sl,
		LEB.CustomerCode												CustomerID,
		CP.CustomerName													Customer,
		LEB.BranchID													BranchID,
		BPB.BranchName													Branch,
		CAST(ISNULL(ISNULL(LEB.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 0) / NULLIF(@USDMid, 0), 0) As Numeric(18, 2))	BillValueUSD
	from EFA..LocalExportBillInitiationMaster LEB WITH(NOLOCK)
		Inner Join EFA..ExportBillMonitoring EBM WITH(NOLOCK) ON EBM.EBIID = LEB.EBIID AND EBM.IsDeleted = 0
		Left Join #Realized R ON R.EBIID = LEB.EBIID
		Left Join SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = LEB.CURRENCY_CODE AND CLR.RateFor = 'MID RATE'
		Left Join SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON LEB.BranchID = BPB.BranchID AND BPB.IsDeleted = 0
		Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON LEB.CustomerCode = CP.CustomerID AND CP.IsDeleted = 0
	where LEB.IsDeleted = 0 and ISNULL(LEB.IsCancelled, 0) = 0
	  and EBM.MaturityDate Is Not Null
	  and CAST(EBM.MaturityDate As Date) <= @ToDate
	  and CAST(LEB.BillGenerationDate As Date) between @FromDate and @ToDate
	  -- overdue: less than 95 percent received
	  and (ISNULL(R.RealizedAmount, 0) / NULLIF(LEB.ExportLocalBillAmount, 0)) * 100 < 95

	Drop Table #Realized
End
GO
