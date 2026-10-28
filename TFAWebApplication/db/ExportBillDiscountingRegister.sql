USE EFA
GO

Create Or Alter Proc spRPT_ExportBillDiscountingRegister
	@FromDate Date,
	@ToDate Date,
	@CustomerID Varchar(50) = NULL,
	@Status Varchar(50) = NULL
As

 -- spRPT_ExportBillDiscountingRegister '2024-01-01', '2026-12-31'
 -- spRPT_ExportBillDiscountingRegister '2024-01-01', '2026-12-31', NULL, 'expired'

Begin
	Set NoCount On;

	-- Step 1: join the tables and work out the Status of each loan
	;With Loan As
	(
		select
			LN.LoanCreationID,
			LN.ACCOUNT_NUMBER						LoanAccountNo,
			CP.CIF									Customer,
			CP.CustomerName							AccountTitle,
			ISNULL(EB.ExportBillNo, LN.BillNumber)	ExportBillNo,
			ISNULL(EB.ISSUE_DT, EB.DocReceiveDate)	ExportBillDate,
			ISNULL(EB.BILL_CCY, LN.Currency)		BillCCY,
			ISNULL(EB.ExportBillAmount, LN.BillAmount) BillAmount,
			EB.Commodity							Commodity,
			EB.EXP_NO								BillTFNumber,
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
			Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON LN.Customer = CP.CustomerID AND CP.IsDeleted = 0
			-- OUTER APPLY TOP 1 so a loan never repeats if two bills share a number
			Outer Apply
			(
				select Top 1 B.ExportBillNo, B.ISSUE_DT, B.DocReceiveDate, B.BILL_CCY, B.ExportBillAmount, B.Commodity, B.EXP_NO
				from EFA..ExportBillInitiationMaster B WITH(NOLOCK)
				where B.ExportBillNo = LN.BillNumber AND B.IsDeleted = 0
				order by B.DateAdded Desc
			) EB
		where LN.IsDeleted = 0
		  and LN.LoanAgainst = 'ExportBill'
		  and CAST(LN.LoanCreationDate As Date) between @FromDate and @ToDate
		  and (@CustomerID Is Null or LN.Customer = @CustomerID)
	)

	-- Step 2: final report columns (in the order of the register)
	select
		[SL no.]					= ROW_NUMBER() OVER (ORDER BY L.DisbursementDate, L.LoanAccountNo),
		[LN Account Number]			= L.LoanAccountNo,
		[Customer]					= L.Customer,
		[Account Title]				= L.AccountTitle,
		[Export Bill no.]			= L.ExportBillNo,
		[Export Bill Date]			= L.ExportBillDate,
		[Bill CCY]					= L.BillCCY,
		[Bill Amount]				= L.BillAmount,
		[Commodity]					= L.Commodity,
		[Bill TF Number]			= L.BillTFNumber,
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
