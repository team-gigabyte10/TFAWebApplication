USE EFA
GO

Create Or Alter Proc spRPT_ImportBillDiscountingRegister
	@FromDate Date,
	@ToDate Date,
	@CustomerID Varchar(50) = NULL,
	@Status Varchar(50) = NULL
As

 -- spRPT_ImportBillDiscountingRegister '2024-01-01', '2026-12-31'
 -- spRPT_ImportBillDiscountingRegister '2024-01-01', '2026-12-31', NULL, 'expired'

Begin
	Set NoCount On;

	-- Step 1: join the tables and work out the Status of each loan
	;With Loan As
	(
		select
			LN.LoanCreationID,
			LN.Customer								CustomerID,
			LN.ACCOUNT_NUMBER						LoanAccountNo,
			CP.CIF									Customer,
			CP.CustomerName							AccountTitle,
			LC.BBLCNo								LCNo,
			LC.IssueDate							LCIssueDate,
			LC.Currency								LCCurrency,
			LC.BBLCAmount							LCAmount,
			LC.Commodity							Commodity,
			LN.BillNumber							BillTFNumber,
			LN.BillAmount							BillAmount,
			LN.LoanCreationDate						DisbursementDate,
			ISNULL(LN.LoanExpiry, LN.MATURITY_DATE)	ExpiryDate,
			ISNULL(LN.LoanCurrency, LN.Currency)	DisbursementCCY,
			LN.LoanAmount							Disbursement,
			LN.PRINCIPAL_OS							Outstanding,
			LN.INTEREST_RATE						RegularRate,
			LN.PENAL_IN								ODIntRate,
			LN.PENAL_PR								PenaltyRate,
			LN.INT_OS								IntAmt,
			LN.DUE_ACCRUED_AMOUNT					ODIntAmt,
			LN.CAL_AMT								PenaltyIntAmt,
			LN.AdjustedDate							LastAdjustmentDate,
			LN.AdjustmentAmount						AmountAdjusted,
			Case
				When ISNULL(LN.LoanNo, '') = ''                                 Then 'not disbursed'
				When LN.PRINCIPAL_OS = 0                                        Then 'closed'
				When ISNULL(LN.LoanExpiry, LN.MATURITY_DATE) < GETDATE()        Then 'expired'
				Else 'current'
			End										LoanStatus
		from EFA..LoanCreation LN WITH(NOLOCK)
			Left Join EFA..BBLCMaster LC WITH(NOLOCK) ON LN.BBLCID = LC.BBLCID AND LC.IsDeleted = 0
			Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON LN.Customer = CP.CustomerID AND CP.IsDeleted = 0
		where LN.IsDeleted = 0
		  and LN.LoanType = 'IBD'
		  and CAST(LN.LoanCreationDate As Date) between @FromDate and @ToDate
		  and (@CustomerID Is Null or LN.Customer = @CustomerID)
	)

	-- Step 2: final report columns (in the order of the register)
	select
		[SL no.]					= ROW_NUMBER() OVER (ORDER BY L.DisbursementDate, L.LoanAccountNo),
		[LN Account Number]			= L.LoanAccountNo,
		[Customer]					= L.Customer,
		[Account Title]				= L.AccountTitle,
		[LC no.]					= L.LCNo,
		[LC Issue Date]				= L.LCIssueDate,
		[CCY]						= L.LCCurrency,
		[LC Amount]					= L.LCAmount,
		[Commodity]					= L.Commodity,
		[Bill TF Number]			= L.BillTFNumber,
		[Bill Amount]				= L.BillAmount,
		[Disbursement Date]			= L.DisbursementDate,
		[Expiry Date]				= L.ExpiryDate,
		[Disbursement CCY]			= L.DisbursementCCY,
		[Disbursement]				= L.Disbursement,
		-- outstanding after the expiry date is the overdue (OD) outstanding
		[OD Outstanding]			= Case When L.LoanStatus = 'expired' Then L.Outstanding End,
		[Outstanding_DR]			= L.Outstanding,
		[Regular Rate]				= L.RegularRate,
		[OD_Int Rate]				= L.ODIntRate,
		[Penalty Rate]				= L.PenaltyRate,
		[Int. Amt]					= L.IntAmt,
		[OD Int. Amt]				= L.ODIntAmt,
		[Penalty Int. Amt]			= L.PenaltyIntAmt,
		[Total Interest]			= ISNULL(L.IntAmt, 0) + ISNULL(L.ODIntAmt, 0) + ISNULL(L.PenaltyIntAmt, 0),
		[Total Charge]				= CAST(NULL As Decimal(18, 2)),  -- no source column yet
		[Last Date of Adjustment]	= L.LastAdjustmentDate,
		[Amount Adjusted]			= L.AmountAdjusted,
		[Status]					= L.LoanStatus
	from Loan L
	where @Status Is Null or @Status = '' or L.LoanStatus = @Status
	order by L.DisbursementDate, L.LoanAccountNo
End
GO
