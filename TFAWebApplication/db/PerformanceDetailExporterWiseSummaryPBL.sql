USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_PerformanceDetailExporterWiseSummaryPBL]    Script Date: 11/9/2026 2:45:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_PerformanceDetailExporterWiseSummaryPBL]
	-- SP_RPT_PerformanceDetailExporterWiseSummaryPBL  
AS											 
BEGIN
	SET NOCOUNT ON;

	-- Determine exchange rate for group and USD conversion
	DECLARE @RateForGroup VARCHAR(50);
	SELECT TOP 1 @RateForGroup = ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK);
	IF @RateForGroup IS NULL OR @RateForGroup = ''
		SET @RateForGroup = 'BC SELLING';

	DECLARE @USDRate NUMERIC(18,4);
	SELECT TOP 1 @USDRate = ConvertFactor 
	FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) 
	WHERE RateFor = @RateForGroup AND CurrencyCode = 'USD';

	IF @USDRate IS NULL OR @USDRate = 0
		SELECT TOP 1 @USDRate = ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) WHERE RateFor = 'BC SELLING' AND CurrencyCode = 'USD';
	IF @USDRate IS NULL OR @USDRate = 0
		SET @USDRate = 1.0;

	-- Drop temp tables if they exist
	IF OBJECT_ID('tempdb..#ExportLCDetails') IS NOT NULL DROP TABLE #ExportLCDetails;
	IF OBJECT_ID('tempdb..#AcceptenceInfoSubReport') IS NOT NULL DROP TABLE #AcceptenceInfoSubReport;
	IF OBJECT_ID('tempdb..#PADEDFInformation') IS NOT NULL DROP TABLE #PADEDFInformation;
	IF OBJECT_ID('tempdb..#EDFInfo') IS NOT NULL DROP TABLE #EDFInfo;
	IF OBJECT_ID('tempdb..#PCTimeLoanInformation') IS NOT NULL DROP TABLE #PCTimeLoanInformation;
	IF OBJECT_ID('tempdb..#ExportBillFDBCInformation') IS NOT NULL DROP TABLE #ExportBillFDBCInformation;
	IF OBJECT_ID('tempdb..#MarginInformation') IS NOT NULL DROP TABLE #MarginInformation;
	IF OBJECT_ID('tempdb..#ForceLoan') IS NOT NULL DROP TABLE #ForceLoan;
	IF OBJECT_ID('tempdb..#ExpiredExportLCDetails') IS NOT NULL DROP TABLE #ExpiredExportLCDetails;
	IF OBJECT_ID('tempdb..#ExpiredExportLCDetails15Days') IS NOT NULL DROP TABLE #ExpiredExportLCDetails15Days;

	---  1. Export LC Details (Group Level)
	SELECT 
		GroupSysID,
		TotalAmountFOBINSFREFCUSD = SUM(((CASE WHEN ReplacedLCSC = 1 THEN NULL ELSE FobValue + Insurance + Freight + ForeignCommision END) * ConvertFactor) / @USDRate),
		ReplacedbyLCUSD = SUM((ISNULL((CASE WHEN ReplacedLCSC = 1 THEN ReplacedbyLC ELSE NULL END), 0) * ConvertFactor) / @USDRate),
		FobValueUSD = SUM((ISNULL(CASE WHEN ReplacedLCSC = 1 THEN NULL ELSE FobValue END, 0) * ConvertFactor) / @USDRate)
	INTO #ExportLCDetails
	FROM (
		SELECT
			MD.GroupSysID,
			MD.ReplacedLCSC,
			MD.LCNo AS ExportLCSCNo,
			MD.Incoterm,
			MD.Currency,
			FobValue = CASE
				WHEN IsLienToGroup = 1 THEN
					CASE
						WHEN ReplacedLCSC = 1 THEN 
							CASE
								WHEN Commission.FOBChargesTypeID = 'Percent'
								THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
								ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
							END
						ELSE                              
							CASE WHEN IsSC = 0 THEN
								CASE
									WHEN Commission.FOBChargesTypeID = 'Percent'
									THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
									ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
								END
							ELSE
								CASE
									WHEN ReplacedAmount > LCAmount THEN 0
									ELSE
										CASE
											WHEN Commission.FOBChargesTypeID = 'Percent'
											THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - MD.ReplacedAmount
											ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.ReplacedAmount
										END
								END
							END
					END
				ELSE 0
			END,
			MD.AmountToGroup,
			ISNULL(CLR.ConvertFactor, 1) AS ConvertFactor,
			MD.LCAmount,
			ISNULL(Insurance.FOBChargesValue, 0) AS Insurance,
			ISNULL(Freight.FOBChargesValue, 0) AS Freight,
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
				THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 
				ELSE ISNULL(Commission.FOBChargesValue, 0) 
			END AS ForeignCommision,
			CASE WHEN MD.ReplacedLCSC = 1 THEN MD.LCAmount ELSE 0 END AS ReplacedbyLC
		FROM MasterDoc MD WITH(NOLOCK)
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'ForeignCommission'
		) Commission ON Commission.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'Freight'
		) Freight ON Freight.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'Insurance'
		) Insurance ON Insurance.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = @RateForGroup
		WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0 AND MD.IsLienToGroup = 1
	) X 
	GROUP BY X.GroupSysID;

	--- 2. Acceptance Information
	SELECT 
		X.GroupSysID,
		AcceptanceBillAmountFCYUSD = SUM(X.AcceptanceBillAmountFCYUSD),
		OutstandingAcceptanceAmountFCY = SUM(X.OutstandingAcceptanceAmountFCY),
		OverdueAmount = SUM(X.OverdueAmount)
	INTO #AcceptenceInfoSubReport 
	FROM (
		SELECT
			B.GroupSysID,
			AcceptanceBillAmountFCYUSD = (F.BillAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate,
			OutstandingAcceptanceAmountFCY = CASE 
				WHEN (F.BillAmount - ISNULL(P.PaymentAmountFCY, 0)) < 0 THEN 0 
				ELSE ((F.BillAmount - ISNULL(P.PaymentAmountFCY, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END,
			OverdueAmount = CASE 
				WHEN CAST(F.MATURITY_DATE AS DATE) < CAST(GETDATE() AS DATE) THEN 
					CASE 
						WHEN (F.BillAmount - ISNULL(P.PaymentAmountFCY, 0)) < 0 THEN 0 
						ELSE ((F.BillAmount - ISNULL(P.PaymentAmountFCY, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
					END
				ELSE 0 
			END
		FROM ForeignDocumentAcceptanceMaster F WITH(NOLOCK)
		INNER JOIN BBLCMaster B WITH(NOLOCK) ON B.BBLCID = F.BBLCID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = F.Currency AND CLR.RateFor = @RateForGroup
		LEFT JOIN (
			SELECT FDAID, SUM(AmountFCY) AS PaymentAmountFCY
			FROM (
				SELECT f.FDAID, SUM(ISNULL(v.CreditAmount, 0)) AS AmountFCY
				FROM CustomerVoucherTransDetails v WITH(NOLOCK)
				INNER JOIN ForeignDocumentAcceptanceMaster f WITH(NOLOCK) ON f.ExternalID = v.AdditionalMasterID
				WHERE v.IsDeleted = 0 AND v.AdditionalFilter = 'Foreign Document Acceptance Master'
				GROUP BY f.FDAID
				UNION ALL
				SELECT e.BillOrLoanID AS FDAID, SUM(ISNULL(l.CreditFCY, 0)) AS AmountFCY
				FROM MarginTransactionDetails l WITH(NOLOCK)
				INNER JOIN MarginEncashmentMaster e WITH(NOLOCK) ON e.MAEMID = l.MAEMID
				WHERE l.IsDeleted = 0 AND e.IsDeleted = 0 AND e.IsBill = 1
				GROUP BY e.BillOrLoanID
			) PayAll
			GROUP BY FDAID
		) P ON P.FDAID = F.FDAID
		WHERE F.BillNo IS NOT NULL AND F.IsDeleted = 0 AND ISNULL(F.IsCancelled, 0) = 0
		AND B.IsDeleted = 0 AND ISNULL(B.IsCancelled, 0) = 0
	) X
	GROUP BY X.GroupSysID;

	--- 3. PAD Information
	SELECT
		B.GroupSysID,
		PADEDFAmountFCY = SUM(
			CASE 
				WHEN L.Currency = 'USD' THEN L.LoanAmount 
				ELSE (L.LoanAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END),
		UnpaidPADUSD = SUM(
			CASE 
				WHEN L.Currency = 'USD' THEN ISNULL(L.OutstandingAmount, L.LoanAmount)
				ELSE (ISNULL(L.OutstandingAmount, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END),
		OverdueAmountUSD = SUM(
			CASE 
				WHEN CAST(L.MATURITY_DATE AS DATE) < CAST(GETDATE() AS DATE) THEN
					CASE 
						WHEN L.Currency = 'USD' THEN ISNULL(L.OutstandingAmount, L.LoanAmount)
						ELSE (ISNULL(L.OutstandingAmount, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
					END
				ELSE 0 
			END)
	INTO #PADEDFInformation
	FROM LoanCreation L WITH(NOLOCK)
	INNER JOIN BBLCMaster B WITH(NOLOCK) ON B.BBLCID = L.BBLCID
	LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = L.Currency AND CLR.RateFor = @RateForGroup
	LEFT JOIN SystemManager..EntityFixedVariables loantype WITH(NOLOCK) ON loantype.EntityID = L.LoanAgainst
	WHERE L.IsDeleted = 0 AND B.IsDeleted = 0 AND ISNULL(B.IsCancelled, 0) = 0
	AND (
		L.LoanAgainst IN ('LoanType/PAID', 'PAD')
		OR loantype.DisplayCode IN ('PD01', 'PD03', 'PD04', 'PDOF', 'PAD', 'PADEDF')
		OR L.ExternalID LIKE '%PAD%' OR L.LoanNo LIKE '%PAD%'
	)
	GROUP BY B.GroupSysID;

	--- 4. EDF Information
	SELECT
		B.GroupSysID,
		EDFAmountFCYUSD = SUM(
			CASE 
				WHEN ISNULL(L.LoanCurrency, L.Currency) = 'USD' THEN L.LoanAmount
				ELSE (L.LoanAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END),
		UnpaidFCY = SUM(
			CASE 
				WHEN ISNULL(L.LoanCurrency, L.Currency) = 'USD' THEN ISNULL(L.OutstandingAmount, L.LoanAmount)
				ELSE (ISNULL(L.OutstandingAmount, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END),
		OverdueUSD = SUM(
			CASE 
				WHEN CAST(L.MATURITY_DATE AS DATE) < CAST(GETDATE() AS DATE) THEN 
					CASE 
						WHEN ISNULL(L.LoanCurrency, L.Currency) = 'USD' THEN ISNULL(L.OutstandingAmount, L.LoanAmount)
						ELSE (ISNULL(L.OutstandingAmount, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
					END
				ELSE 0 
			END)
	INTO #EDFInfo
	FROM LoanCreation L WITH(NOLOCK)
	INNER JOIN BBLCMaster B WITH(NOLOCK) ON B.BBLCID = L.BBLCID
	LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(L.LoanCurrency, L.Currency) AND CLR.RateFor = @RateForGroup
	LEFT JOIN SystemManager..EntityFixedVariables loantype WITH(NOLOCK) ON loantype.EntityID = L.LoanAgainst
	WHERE L.IsDeleted = 0 AND B.IsDeleted = 0 AND ISNULL(B.IsCancelled, 0) = 0
	AND (
		L.LoanAgainst = 'LoanType/LEDF' 
		OR loantype.DisplayCode IN ('EDF', 'LEDF') 
		OR loantype.DisplayText LIKE '%EDF%'
		OR L.ExternalID LIKE '%EDF%' 
		OR L.LoanNo LIKE '%EDF%'
	)
	GROUP BY B.GroupSysID;

	--- 5. PC / Time Loan Information
	SELECT
		ISNULL(PC.GroupRefID, G.GroupSysID) AS GroupSysID,
		PCTimeLoanAmountFCYUSD = SUM((PC.PCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate),
		OutstandingAmountFCYUSD = SUM(
			CASE 
				WHEN PC.TOT_OS IS NOT NULL THEN (PC.TOT_OS * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
				WHEN PC.PCAmountTK IS NOT NULL THEN PC.PCAmountTK / @USDRate
				ELSE (PC.PCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
			END),
		OverdueAmountUSD = SUM(
			CASE 
				WHEN CAST(PC.MATURITY_DATE AS DATE) < CAST(GETDATE() AS DATE) THEN 
					CASE 
						WHEN PC.TOT_OS IS NOT NULL THEN (PC.TOT_OS * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
						WHEN PC.PCAmountTK IS NOT NULL THEN PC.PCAmountTK / @USDRate
						ELSE (PC.PCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
					END
				ELSE 0 
			END)
	INTO #PCTimeLoanInformation
	FROM PCDisbursementMaster PC WITH(NOLOCK)
	INNER JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = PC.GroupRefID AND G.IsDeleted = 0
	LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = PC.Currency AND CLR.RateFor = @RateForGroup
	WHERE PC.IsDeleted = 0
	GROUP BY ISNULL(PC.GroupRefID, G.GroupSysID);

	--- 6. ExportBill FDBC Information / ExportMade & Realization
	SELECT 
		X.GroupSysID,
		ExportMade = SUM(X.BillAmountUSD),
		RealizedAmount = SUM(X.RealizedAmountFCY * ISNULL(X.ConvertFactor, 1)) / @USDRate,
		UnrealizedAmount = SUM(X.UnRealizedAmountFCY * ISNULL(X.ConvertFactor, 1)) / @USDRate
	INTO #ExportBillFDBCInformation 
	FROM (
		-- Foreign Export Bills
		SELECT 
			MD.GroupSysID,
			(EBIM.ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS BillAmountUSD,
			ISNULL(PRSM.RealizedValue, 0) + ISNULL(ARV.RMTAdjustedAmount, 0) AS RealizedAmountFCY,
			UnRealizedAmountFCY = CASE 
				WHEN (ISNULL(PRSM.RealizedValue, 0) + ISNULL(ARV.RMTAdjustedAmount, 0) = 0) THEN EBIM.ExportBillAmount
				WHEN (ISNULL(PRSM.RealizedValue, 0) + ISNULL(ARV.RMTAdjustedAmount, 0)) >= EBIM.ExportBillAmount THEN 0
				ELSE EBIM.ExportBillAmount - (ISNULL(PRSM.RealizedValue, 0) + ISNULL(ARV.RMTAdjustedAmount, 0))
			END,
			ISNULL(CLR.ConvertFactor, 1) AS ConvertFactor
		FROM ExportBillInitiationMaster EBIM WITH(NOLOCK)
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = EBIM.MasterDocID AND MD.IsDeleted = 0
		LEFT JOIN (
			SELECT EBIID, SUM(ISNULL(C_Amount, 0)) AS RealizedValue 
			FROM PRSCreationMaster WITH(NOLOCK)
			WHERE IsDeleted = 0
			GROUP BY EBIID
		) PRSM ON PRSM.EBIID = EBIM.EBIID
		LEFT JOIN (
			SELECT ebaa.EBIIRMTD AS EBIID, 
				SUM(ISNULL(ebaa.AdjustmentAmount, 0) + ISNULL(ebaa.ForeignBankCharge, 0) + ISNULL(ebaa.ForeignCommission, 0) + ISNULL(ebaa.DiscountAmount, 0)) AS RMTAdjustedAmount
			FROM ExportBillAgainstRMTAdjustmentDetails ebaa WITH(NOLOCK)
			WHERE ebaa.IsDeleted = 0 AND ISNULL(ebaa.IsCancelled, 0) = 0
			GROUP BY ebaa.EBIIRMTD
		) ARV ON ARV.EBIID = EBIM.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = EBIM.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
		WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND EBIM.ExportBillNo IS NOT NULL

		UNION ALL

		-- Local Export Bills
		SELECT 
			MD.GroupSysID,
			(EBIM.ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS BillAmountUSD,
			ISNULL(PRSM.RealizedValue, 0) AS RealizedAmountFCY,
			UnRealizedAmountFCY = CASE 
				WHEN ISNULL(PRSM.RealizedValue, 0) = 0 THEN EBIM.ExportLocalBillAmount
				WHEN ISNULL(PRSM.RealizedValue, 0) >= EBIM.ExportLocalBillAmount THEN 0
				ELSE EBIM.ExportLocalBillAmount - ISNULL(PRSM.RealizedValue, 0)
			END,
			ISNULL(CLR.ConvertFactor, 1) AS ConvertFactor
		FROM LocalExportBillInitiationMaster EBIM WITH(NOLOCK)
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = EBIM.MasterDocID AND MD.IsDeleted = 0
		LEFT JOIN (
			SELECT EBIID, SUM(ISNULL(C_Amount, 0)) AS RealizedValue 
			FROM PRSCreationMaster WITH(NOLOCK)
			WHERE IsDeleted = 0
			GROUP BY EBIID
		) PRSM ON PRSM.EBIID = EBIM.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = EBIM.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
		WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND EBIM.ExportLocalBillNo IS NOT NULL
	) X
	GROUP BY X.GroupSysID;

	--- 7. Margin Information
	SELECT 
		X.GroupSysID,
		MarginCredit = SUM(X.CalCreditAmount),
		MarginDebit = SUM(X.CalDebitAmount),
		MarginBalance = SUM(X.CalCreditAmount) - SUM(X.CalDebitAmount)
	INTO #MarginInformation 
	FROM (
		-- Margin from PRS Distribution Details
		SELECT 
			MD.GroupSysID,
			CalCreditAmount = CASE 
				WHEN D.DistributedCCY = 'USD' THEN ISNULL(D.DistributedValue, 0) 
				ELSE (ISNULL(D.DistributedValue, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END,
			CalDebitAmount = 0
		FROM PRSCreationDistributionDetails D WITH(NOLOCK)
		INNER JOIN PRSCreationMaster M WITH(NOLOCK) ON M.PRSSysID = D.PRSSysID AND M.IsDeleted = 0
		INNER JOIN (
			SELECT EBIID, MasterDocID FROM ExportBillInitiationMaster WITH(NOLOCK) WHERE IsDeleted = 0
			UNION ALL
			SELECT EBIID, MasterDocID FROM LocalExportBillInitiationMaster WITH(NOLOCK) WHERE IsDeleted = 0
		) Bill ON Bill.EBIID = D.BillRefNo
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = Bill.MasterDocID AND MD.IsDeleted = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = D.DistributedCCY AND CLR.RateFor = @RateForGroup
		WHERE D.IsDeleted = 0 
		AND (
			D.AllocationHead LIKE '%Margin%' 
			OR D.ProductCode LIKE '%Margin%'
			OR D.AC_NO IN (
				SELECT CA.AccountCode FROM SystemManager..CustomerProfileAccounts CA WITH(NOLOCK)
				INNER JOIN SystemManager..EntityFixedVariables EN WITH(NOLOCK) ON EN.EntityID = CA.AccountTypeID
				WHERE CA.IsDeleted = 0 AND EN.ExternalID = 'MARGIN'
			)
		)

		UNION ALL

		-- Margin from PRSAllocationTransaction
		SELECT 
			PAT.MasterID AS GroupSysID,
			CalCreditAmount = ISNULL(PAT.Value, 0),
			CalDebitAmount = 0
		FROM PRSAllocationTransaction PAT WITH(NOLOCK)
		WHERE PAT.IsDeleted = 0 AND PAT.AllocationHead = 'FC BBLC Margin'

		UNION ALL

		-- Margin from Margin Encashment
		SELECT 
			D.GroupSysID,
			CalCreditAmount = CASE 
				WHEN D.DebitCredit = 'Credit' THEN 
					CASE WHEN GLC.CurrencyCode = 'USD' THEN ISNULL(D.NetMarginPosition, 0)
					ELSE (ISNULL(D.NetMarginPosition, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate END
				ELSE 0 
			END,
			CalDebitAmount = CASE 
				WHEN D.DebitCredit = 'Debit' OR D.DebitCredit IS NULL THEN 
					CASE WHEN GLC.CurrencyCode = 'USD' THEN ISNULL(D.NetMarginPosition, 0)
					ELSE (ISNULL(D.NetMarginPosition, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate END
				ELSE 0 
			END
		FROM MarginEncashmentChild D WITH(NOLOCK)
		INNER JOIN MarginEncashmentMaster MD WITH(NOLOCK) ON MD.MAEMID = D.MAEMID AND MD.IsDeleted = 0
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = D.GroupSysID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = GLC.CurrencyCode AND CLR.RateFor = @RateForGroup
		WHERE D.IsDeleted = 0 AND D.GroupSysID IS NOT NULL AND D.GroupSysID <> ''

		UNION ALL

		-- Margin from ViewTransactionLedgerOBL (if entries exist)
		SELECT 
			V.GroupSysID,
			CalCreditAmount = CASE WHEN V.Currency = 'USD' THEN V.CreditAmount ELSE (V.CreditAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate END,
			CalDebitAmount = CASE WHEN V.Currency = 'USD' THEN V.DebitAmount ELSE (V.DebitAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate END
		FROM ViewTransactionLedgerOBL V WITH(NOLOCK)
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = V.Currency AND CLR.RateFor = @RateForGroup
		WHERE V.GroupSysID IS NOT NULL AND (V.CreditAmount > 0 OR V.DebitAmount > 0)
		AND V.AC_NO IN (
			SELECT CA.AccountCode FROM SystemManager..CustomerProfileAccounts CA WITH(NOLOCK)
			INNER JOIN SystemManager..EntityFixedVariables EN WITH(NOLOCK) ON EN.EntityID = CA.AccountTypeID
			WHERE CA.IsDeleted = 0 AND EN.ExternalID = 'MARGIN'
		)
	) X
	GROUP BY X.GroupSysID;

	--- 8. Force Loan Information
	SELECT
		G.GroupSysID,
		ForceLoanAmountUSD = SUM(
			CASE 
				WHEN L.Currency = 'USD' THEN L.LoanAmount
				ELSE (L.LoanAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END),
		OutstandingAmountUSD = SUM(
			CASE 
				WHEN L.Currency = 'USD' THEN ISNULL(L.OutstandingAmount, L.LoanAmount)
				ELSE (ISNULL(L.OutstandingAmount, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			END)
	INTO #ForceLoan
	FROM LoanCreation L WITH(NOLOCK)
	INNER JOIN BBLCMaster B WITH(NOLOCK) ON B.BBLCID = L.BBLCID
	INNER JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = B.GroupSysID
	LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = L.Currency AND CLR.RateFor = @RateForGroup
	LEFT JOIN SystemManager..EntityFixedVariables loantype WITH(NOLOCK) ON loantype.EntityID = L.LoanAgainst
	WHERE L.IsDeleted = 0 AND B.IsDeleted = 0 AND ISNULL(B.IsCancelled, 0) = 0
	AND (
		L.LoanAgainst LIKE '%Force%'
		OR loantype.DisplayCode IN ('FL', 'FORCED', 'TMFL', 'FBL', 'TM13', 'TM14', 'TM11')
		OR loantype.DisplayText LIKE '%Force%'
		OR L.ExternalID LIKE '%FL%' OR L.LoanNo LIKE '%FL%'
	)
	GROUP BY G.GroupSysID;

	--- 9. Expired Export LC Details (Already Expired)
	SELECT 
		GroupSysID,
		TotalAmountFOBINSFREFCUSD = SUM(((CASE WHEN ReplacedLCSC = 1 THEN NULL ELSE FobValue + Insurance + Freight + ForeignCommision END) * ConvertFactor) / @USDRate)
	INTO #ExpiredExportLCDetails
	FROM (
		SELECT
			MD.GroupSysID,
			MD.ReplacedLCSC,			
			FobValue = CASE
				WHEN IsLienToGroup = 1 THEN
					CASE
						WHEN ReplacedLCSC = 1 THEN 
							CASE
								WHEN Commission.FOBChargesTypeID = 'Percent'
								THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
								ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
							END
						ELSE                              
							CASE WHEN IsSC = 0 THEN
								CASE
									WHEN Commission.FOBChargesTypeID = 'Percent'
									THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
									ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
								END
							ELSE
								CASE
									WHEN ReplacedAmount > LCAmount THEN 0
									ELSE
										CASE
											WHEN Commission.FOBChargesTypeID = 'Percent'
											THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - MD.ReplacedAmount
											ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.ReplacedAmount
										END
								END
							END
					END
				ELSE 0
			END,          
			ISNULL(CLR.ConvertFactor, 1) AS ConvertFactor,
			MD.LCAmount,
			ISNULL(Insurance.FOBChargesValue, 0) AS Insurance,
			ISNULL(Freight.FOBChargesValue, 0) AS Freight,
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
				THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 
				ELSE ISNULL(Commission.FOBChargesValue, 0) 
			END AS ForeignCommision
		FROM MasterDoc MD WITH(NOLOCK)
		LEFT JOIN (
			SELECT MasterDocID, MAX(NewExpiryDate) AS ExpiryDate, MAX(NewShipDate) AS ShipmentDate 
			FROM MasterLCAmmendment WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsCancelled = 0 
			GROUP BY MasterDocID
		) MLCAM ON MLCAM.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'ForeignCommission'
		) Commission ON Commission.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'Freight'
		) Freight ON Freight.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'Insurance'
		) Insurance ON Insurance.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = @RateForGroup
		WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0 AND MD.IsLienToGroup = 1
		AND CAST(COALESCE(MLCAM.ExpiryDate, MD.ExpiryDate, MD.ShipmentDate) AS DATE) < CAST(GETDATE() AS DATE)
	) X 
	GROUP BY X.GroupSysID;

	--- 10. Expired Export LC Details within 15 Days
	SELECT 
		GroupSysID,
		TotalAmountFOBINSFREFCUSD = SUM(((CASE WHEN ReplacedLCSC = 1 THEN NULL ELSE FobValue + Insurance + Freight + ForeignCommision END) * ConvertFactor) / @USDRate)
	INTO #ExpiredExportLCDetails15Days
	FROM (
		SELECT
			MD.GroupSysID,
			MD.ReplacedLCSC,			
			FobValue = CASE
				WHEN IsLienToGroup = 1 THEN
					CASE
						WHEN ReplacedLCSC = 1 THEN 
							CASE
								WHEN Commission.FOBChargesTypeID = 'Percent'
								THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
								ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
							END
						ELSE                              
							CASE WHEN IsSC = 0 THEN
								CASE
									WHEN Commission.FOBChargesTypeID = 'Percent'
									THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
									ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
								END
							ELSE
								CASE
									WHEN ReplacedAmount > LCAmount THEN 0
									ELSE
										CASE
											WHEN Commission.FOBChargesTypeID = 'Percent'
											THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - MD.ReplacedAmount
											ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.ReplacedAmount
										END
								END
							END
					END
				ELSE 0
			END,          
			ISNULL(CLR.ConvertFactor, 1) AS ConvertFactor,
			MD.LCAmount,
			ISNULL(Insurance.FOBChargesValue, 0) AS Insurance,
			ISNULL(Freight.FOBChargesValue, 0) AS Freight,
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
				THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 
				ELSE ISNULL(Commission.FOBChargesValue, 0) 
			END AS ForeignCommision
		FROM MasterDoc MD WITH(NOLOCK)
		LEFT JOIN (
			SELECT MasterDocID, MAX(NewExpiryDate) AS ExpiryDate, MAX(NewShipDate) AS ShipmentDate 
			FROM MasterLCAmmendment WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsCancelled = 0 
			GROUP BY MasterDocID
		) MLCAM ON MLCAM.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'ForeignCommission'
		) Commission ON Commission.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'Freight'
		) Freight ON Freight.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation WITH(NOLOCK)
			WHERE TemplateID = 'Insurance'
		) Insurance ON Insurance.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = @RateForGroup
		WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0 AND MD.IsLienToGroup = 1
		AND CAST(COALESCE(MLCAM.ExpiryDate, MD.ExpiryDate, MD.ShipmentDate) AS DATE) BETWEEN CAST(GETDATE() AS DATE) AND CAST(DATEADD(DAY, 15, GETDATE()) AS DATE)
	) X 
	GROUP BY X.GroupSysID;

	--- 11. Final Report Output Dataset
	SELECT * 
	FROM 
	(
		SELECT
			Adbpb.BranchName,
			CPM.CustomerName AS ClientName,	
			GLC.GroupRefNo AS GroupRefNo,
			GLC.CurrencyCode AS GroupCurrency,
			LCSCValue = ExportLCDetails.TotalAmountFOBINSFREFCUSD,				
			ReplacedLCValue = ExportLCDetails.ReplacedbyLCUSD,
			LCnotyetReplaced = ExportLCDetails.TotalAmountFOBINSFREFCUSD - ExportLCDetails.ReplacedbyLCUSD,	
			GroupValue = ExportLCDetails.FobValueUSD,

			BBLCPercent = ISNULL(GLC.EntitlementPercent, 0),
			BBLCEntitlement = CASE 
				WHEN ISNULL(GLC.GrpEntitlementAmt, 0) > 0 
					THEN (GLC.GrpEntitlementAmt * ISNULL(GCLR.ConvertFactor, 1)) / @USDRate
				ELSE ISNULL(ExportLCDetails.FobValueUSD, 0) * (ISNULL(GLC.EntitlementPercent, 0) / 100.0)
			END,
			BBLCValue = ISNULL(Util.AmtUtilizedWithoutTol, 0),
			AllowableBBLCValue = (CASE 
				WHEN ISNULL(GLC.GrpEntitlementAmt, 0) > 0 
					THEN (GLC.GrpEntitlementAmt * ISNULL(GCLR.ConvertFactor, 1)) / @USDRate
				ELSE ISNULL(ExportLCDetails.FobValueUSD, 0) * (ISNULL(GLC.EntitlementPercent, 0) / 100.0)
			END) - ISNULL(Util.AmtUtilizedSQ, 0),

			AcceptanceValue = ISNULL(AcceptenceInfoSubReport.AcceptanceBillAmountFCYUSD, 0),
			UnpaidAcceptance = ISNULL(AcceptenceInfoSubReport.OutstandingAcceptanceAmountFCY, 0),
			OverdueAmount = ISNULL(AcceptenceInfoSubReport.OverdueAmount, 0),

			PADEDF = ISNULL(PADEDFInformation.PADEDFAmountFCY, 0),
			UnpaidPADEDF = ISNULL(PADEDFInformation.UnpaidPADUSD, 0),
			OverduePADEDF = ISNULL(PADEDFInformation.OverdueAmountUSD, 0),

			EDF = ISNULL(EDFInfo.EDFAmountFCYUSD, 0),
			UnpaidEDF = ISNULL(EDFInfo.UnpaidFCY, 0),
			OverdueEDF = ISNULL(EDFInfo.OverdueUSD, 0),

			PCTimeLoanDisbursed = ISNULL(PCTimeLoanInformation.PCTimeLoanAmountFCYUSD, 0),
			PCTimeLoanOutstanding = ISNULL(PCTimeLoanInformation.OutstandingAmountFCYUSD, 0),
			PCTimeLoanOverdue = ISNULL(PCTimeLoanInformation.OverdueAmountUSD, 0),

			ExportMade = ISNULL(ExportBillFDBCInformation.ExportMade, 0),
			ExportNotMade = CASE 
				WHEN (ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExportBillFDBCInformation.ExportMade, 0)) < 0 
				THEN 0 
				ELSE (ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExportBillFDBCInformation.ExportMade, 0)) 
			END,
			RealizedAmount = CASE 
				WHEN ISNULL(ExportBillFDBCInformation.RealizedAmount, 0) > 0 THEN ExportBillFDBCInformation.RealizedAmount
				ELSE (ISNULL(Realized.ProcessReceivedAmount, 0) * ISNULL(GCLR.ConvertFactor, 1)) / @USDRate 
			END,
			UnRealizedAmount = ISNULL(ExportBillFDBCInformation.UnRealizedAmount, 0),

			MarginRetained = ISNULL(MarginInformation.MarginCredit, 0),
			MarginUtilized = ISNULL(MarginInformation.MarginDebit, 0),
			MarginBalance = ISNULL(MarginInformation.MarginBalance, 0),

			MarginBuildupRequirement = ISNULL(ExportLCDetails.FobValueUSD, 0) * 
				((CASE WHEN ISNULL(FCBBLC.Value, 0) > GLC.EntitlementPercent 
				THEN ISNULL(FCBBLC.Value, 0) 
				ELSE GLC.EntitlementPercent END) / 100.0),

			MarginSurplusShortfall = (ISNULL(ExportLCDetails.FobValueUSD, 0) * 
				((CASE WHEN ISNULL(FCBBLC.Value, 0) > GLC.EntitlementPercent 
				THEN ISNULL(FCBBLC.Value, 0) 
				ELSE GLC.EntitlementPercent END) / 100.0)) - ISNULL(MarginInformation.MarginCredit, 0),

			ForcedLoanDisbursed = ISNULL(ForceLoan.ForceLoanAmountUSD, 0),
			OutstandingForceLoan = ISNULL(ForceLoan.OutstandingAmountUSD, 0),

			GroupValueOfLCSC = ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0),
			ExpiredLCSC = ISNULL(ExpiredExportLCDetails.TotalAmountFOBINSFREFCUSD, 0),
			ExpiryWithin15DaysOfLCSC = ISNULL(ExpiredExportLCDetails15Days.TotalAmountFOBINSFREFCUSD, 0),
			ExpiryAfter15DaysOfLCSC = CASE 
				WHEN (ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredExportLCDetails15Days.TotalAmountFOBINSFREFCUSD, 0)) < 0 
				THEN 0 
				ELSE (ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredExportLCDetails15Days.TotalAmountFOBINSFREFCUSD, 0)) 
			END,

			TotalExportMade = ISNULL(ExportBillFDBCInformation.ExportMade, 0),
			TotalExportNotMade = CASE 
				WHEN (ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExportBillFDBCInformation.ExportMade, 0)) < 0 
				THEN 0 
				ELSE (ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExportBillFDBCInformation.ExportMade, 0)) 
			END,

			ExportExecutedagainstExpiredLCSC = ISNULL(ExpiredLCSC.ExportBillAmount, 0),
			UnutilizedExpiredLCSC = CASE 
				WHEN (ISNULL(ExpiredLCSC.LCAmount, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0)) < 0 THEN 0 
				ELSE (ISNULL(ExpiredLCSC.LCAmount, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0)) 
			END,

			ExportExecutedagainstLiveLCSC = ISNULL(LiveLCSC.ExportBillAmount, 0),
			UnutilizedLiveLCSC = CASE 
				WHEN (ISNULL(LiveLCSC.LCAmount, 0) - ISNULL(LiveLCSC.ExportBillAmount, 0)) < 0 THEN 0 
				ELSE (ISNULL(LiveLCSC.LCAmount, 0) - ISNULL(LiveLCSC.ExportBillAmount, 0)) 
			END,

			ExportExecutedagainstLiveLCSCAfter15Days = CASE 
				WHEN (ISNULL(Bill.ExportMade, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.ExportBillAmount, 0)) < 0 THEN 0 
				ELSE (ISNULL(Bill.ExportMade, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.ExportBillAmount, 0)) 
			END,
			UnutilizedLiveLCSCAfter15Days = CASE 
				WHEN ((ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredLCSC.LCAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.LCAmount, 0)) - (ISNULL(Bill.ExportMade, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.ExportBillAmount, 0))) < 0 THEN 0 
				ELSE ((ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredLCSC.LCAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.LCAmount, 0)) - (ISNULL(Bill.ExportMade, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.ExportBillAmount, 0))) 
			END,

			BuyerName = ISNULL(LTRIM(RTRIM(REPLACE(MD.ApplicantName, '&amp;', '&'))), ''),
			BuyerCountry = ISNULL(LTRIM(RTRIM(REPLACE(MD.CountryName, '&amp;', '&'))), ''),
			CustomerID = GLC.CustomerID,
			Applicant = MD.Applicant,
			Branch = Adbpb.BranchName,
			BranchID = GLC.BankBranchID,
			GroupSysID = GLC.GroupSysID,
			GroupStatus = CASE WHEN GLC.IsClosedGroup = 1 THEN 'Closed' ELSE 'Live' END,
			CountryID = MD.CountryID,
			AsOnDate = CONVERT(DATE, GETDATE()),
			GroupDate = GLC.DateAdded,
			LShipmentDate = ld.ShipmentDate,
			LExpirydate = ld.ExpiryDate,
			Glclist = REPLACE(gLClist.gLCList, '&amp;', '&'),
			GroupCreationDate = GLC.DateAdded,
			GroupFromDate = GLC.DateAdded,
			GroupToDate = GLC.DateAdded
		FROM GroupLC GLC WITH(NOLOCK)
		LEFT JOIN (
			SELECT md.GroupSysID, ShipmentDate = MAX(ShipmentDate), ExpiryDate = MAX(ExpiryDate) 
			FROM MasterDoc md WITH(NOLOCK)
			WHERE md.IsDeleted = 0 AND md.IsCancelled = 0
			GROUP BY md.GroupSysID
		) ld ON ld.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT GroupSysID, 
				STUFF((
					SELECT DISTINCT ', ' + REPLACE(CombinedE.LCNo, '&amp;', '&')  
					FROM (
						SELECT DISTINCT MD.LCNo, GroupSysID 
						FROM MasterDoc MD WITH(NOLOCK)						 
						WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0
					) CombinedE 
					WHERE CombinedE.GroupSysID = glc.GroupSysID
					FOR XML PATH('')
				), 1, 2, '') AS gLCList 
			FROM GroupLC glc WITH(NOLOCK)
		) gLClist ON gLClist.GroupSysID = GLC.GroupSysID
		LEFT JOIN SystemManager..CurrencyLatestRate GCLR WITH(NOLOCK) ON GCLR.CurrencyCode = GLC.CurrencyCode AND GCLR.RateFor = @RateForGroup
		LEFT JOIN #ExportLCDetails ExportLCDetails ON ExportLCDetails.GroupSysID = GLC.GroupSysID
		LEFT JOIN #AcceptenceInfoSubReport AcceptenceInfoSubReport ON AcceptenceInfoSubReport.GroupSysID = GLC.GroupSysID
		LEFT JOIN #PADEDFInformation PADEDFInformation ON PADEDFInformation.GroupSysID = GLC.GroupSysID
		LEFT JOIN #EDFInfo EDFInfo ON EDFInfo.GroupSysID = GLC.GroupSysID
		LEFT JOIN #PCTimeLoanInformation PCTimeLoanInformation ON PCTimeLoanInformation.GroupSysID = GLC.GroupSysID
		LEFT JOIN #ExportBillFDBCInformation ExportBillFDBCInformation ON ExportBillFDBCInformation.GroupSysID = GLC.GroupSysID
		LEFT JOIN #MarginInformation MarginInformation ON MarginInformation.GroupSysID = GLC.GroupSysID
		LEFT JOIN #ExpiredExportLCDetails ExpiredExportLCDetails ON ExpiredExportLCDetails.GroupSysID = GLC.GroupSysID
		LEFT JOIN #ExpiredExportLCDetails15Days ExpiredExportLCDetails15Days ON ExpiredExportLCDetails15Days.GroupSysID = GLC.GroupSysID
		LEFT JOIN #ForceLoan ForceLoan ON ForceLoan.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT MasterID, SUM(Value) AS Value
			FROM PRSAllocationTransaction WITH(NOLOCK)
			WHERE IsDeleted = 0 AND AllocationHead = 'FC BBLC Margin'
			GROUP BY MasterID 
		) FCBBLC ON FCBBLC.MasterID = GLC.GroupSysID
		LEFT JOIN (
			SELECT 
				BBLCM.GroupSysID, 
				AmtUtilizedSQ = ISNULL(SUM((BBLCAmount + (BBLCAmount * ISNULL(Toleranace, 0) / 100)) * ISNULL(CLR.ConvertFactor, 1)), 0) / @USDRate, 
				AmtUtilizedWithoutTol = ISNULL(SUM(BBLCAmount * ISNULL(CLR.ConvertFactor, 1)), 0) / @USDRate
			FROM BBLCMaster BBLCM WITH(NOLOCK)
			LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = BBLCM.Currency AND CLR.RateFor = @RateForGroup
			WHERE BBLCM.IsDeleted = 0 AND ISNULL(BBLCM.IsCancelled, 0) = 0
			GROUP BY BBLCM.GroupSysID
		) Util ON Util.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT 
				M.GroupSysID, 
				LCAmount = SUM(M.LCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate, 
				ExportBillAmount = SUM(ISNULL(B.ExportBillAmount, 0)) / @USDRate 
			FROM MasterDoc M WITH(NOLOCK)
			LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = M.Currency AND CLR.RateFor = @RateForGroup
			LEFT JOIN (
				SELECT MasterDocID, SUM(ExportBillAmount) AS ExportBillAmount 
				FROM (
					SELECT eb.MasterDocID, ExportBillAmount = eb.ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)
					FROM ExportBillInitiationMaster eb WITH(NOLOCK)
					INNER JOIN MasterDoc md WITH(NOLOCK) ON md.MasterDocID = eb.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE eb.IsDeleted = 0 AND ISNULL(eb.IsCancelled, 0) = 0 AND eb.ExportBillNo IS NOT NULL AND CAST(eb.BillGenerationDate AS DATE) <= CAST(md.ShipmentDate AS DATE)
					UNION ALL
					SELECT eb.MasterDocID, ExportLocalBillAmount = eb.ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1) 
					FROM LocalExportBillInitiationMaster eb WITH(NOLOCK)
					INNER JOIN MasterDoc md WITH(NOLOCK) ON md.MasterDocID = eb.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE eb.IsDeleted = 0 AND ISNULL(eb.IsCancelled, 0) = 0 AND eb.ExportLocalBillNo IS NOT NULL AND CAST(eb.BillGenerationDate AS DATE) <= CAST(md.ShipmentDate AS DATE)
				) A GROUP BY MasterDocID
			) B ON B.MasterDocID = M.MasterDocID 
			WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND CONVERT(DATE, M.ShipmentDate) < CONVERT(DATE, GETDATE())
			GROUP BY M.GroupSysID
		) ExpiredLCSC ON ExpiredLCSC.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT 
				M.GroupSysID, 
				LCAmount = SUM(M.LCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate, 
				ExportBillAmount = SUM(ISNULL(B.ExportBillAmount, 0)) / @USDRate 
			FROM MasterDoc M WITH(NOLOCK)
			LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = M.Currency AND CLR.RateFor = @RateForGroup
			LEFT JOIN (
				SELECT MasterDocID, SUM(ExportBillAmount) AS ExportBillAmount 
				FROM (
					SELECT MasterDocID, ExportBillAmount = ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)
					FROM ExportBillInitiationMaster eb WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL 
					UNION ALL
					SELECT MasterDocID, ExportLocalBillAmount = ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1)
					FROM LocalExportBillInitiationMaster eb WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
				) A GROUP BY MasterDocID
			) B ON B.MasterDocID = M.MasterDocID 
			WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND CONVERT(DATE, M.ShipmentDate) > CONVERT(DATE, DATEADD(DAY, 15, GETDATE())) 
			GROUP BY M.GroupSysID
		) ExpiryWithin15DaysOfLCSC ON ExpiryWithin15DaysOfLCSC.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT 
				M.GroupSysID, 
				LCAmount = SUM(M.LCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate, 
				ExportBillAmount = SUM(ISNULL(B.ExportBillAmount, 0)) / @USDRate 
			FROM MasterDoc M WITH(NOLOCK)
			LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = M.Currency AND CLR.RateFor = @RateForGroup
			LEFT JOIN (
				SELECT MasterDocID, SUM(ExportBillAmount) AS ExportBillAmount 
				FROM (
					SELECT MasterDocID, ExportBillAmount = ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)
					FROM ExportBillInitiationMaster eb WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL 
					UNION ALL
					SELECT MasterDocID, ExportLocalBillAmount = ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1) 
					FROM LocalExportBillInitiationMaster eb WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
				) A GROUP BY MasterDocID
			) B ON B.MasterDocID = M.MasterDocID 
			WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND CONVERT(DATE, GETDATE()) < CONVERT(DATE, M.ExpiryDate) 
			GROUP BY M.GroupSysID
		) LiveLCSC ON LiveLCSC.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT 
				E.GroupSysID,
				MAX(E.ShipmentDate) AS ShipmentDate,
				MAX(E.ExpiryDate) AS ExpiryDate,
				MAX(E.Applicant) AS Applicant,
				MAX(APP.CountryID) AS CountryID,
				STUFF((
					SELECT DISTINCT ', ' + CombinedC.CountryName 
					FROM (
						SELECT DISTINCT COALESCE(CC.CountryName, C2.CountryName) AS CountryName, MD2.GroupSysID
						FROM MasterDoc MD2 WITH(NOLOCK)
						LEFT JOIN SystemManager..Contacts APP WITH(NOLOCK) ON APP.Code = MD2.Applicant
						LEFT JOIN SystemManager..Country CC WITH(NOLOCK) ON CC.CountryID = APP.CountryID
						LEFT JOIN LcAdvisingPartyInfo P WITH(NOLOCK) ON P.LCReceiveID = MD2.MasterDocID
						LEFT JOIN SystemManager..Contacts UB WITH(NOLOCK) ON UB.Code = P.PartyID
						LEFT JOIN SystemManager..Country C2 WITH(NOLOCK) ON C2.CountryID = UB.CountryID
						WHERE MD2.IsDeleted = 0 AND MD2.IsCancelled = 0
						AND COALESCE(CC.CountryName, C2.CountryName) IS NOT NULL
					) CombinedC
					WHERE CombinedC.GroupSysID = E.GroupSysID
					FOR XML PATH('')
				), 1, 2, '') AS CountryName,
				STUFF((
					SELECT DISTINCT ', ' + CombinedE.Name 
					FROM (
						SELECT DISTINCT COALESCE(APP.Name, UB.Name) AS Name, MD2.GroupSysID 
						FROM MasterDoc MD2 WITH(NOLOCK)
						LEFT JOIN SystemManager..Contacts APP WITH(NOLOCK) ON APP.Code = MD2.Applicant
						LEFT JOIN LcAdvisingPartyInfo P WITH(NOLOCK) ON P.LCReceiveID = MD2.MasterDocID
						LEFT JOIN SystemManager..Contacts UB WITH(NOLOCK) ON UB.Code = P.PartyID
						WHERE MD2.IsDeleted = 0 AND MD2.IsCancelled = 0
						AND COALESCE(APP.Name, UB.Name) IS NOT NULL
					) CombinedE 
					WHERE CombinedE.GroupSysID = E.GroupSysID
					FOR XML PATH('')
				), 1, 2, '') AS ApplicantName
			FROM MasterDoc E WITH(NOLOCK)
			LEFT JOIN SystemManager..Contacts APP WITH(NOLOCK) ON APP.Code = E.Applicant
			WHERE E.IsDeleted = 0 AND E.IsCancelled = 0 
			GROUP BY E.GroupSysID
		) MD ON MD.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT SUM(ProcessReceivedAmount) AS ProcessReceivedAmount, GroupSysID 
			FROM (
				SELECT ISNULL(PRS.ProceedsRecvd, 0) AS ProcessReceivedAmount, MD.GroupSysID 
				FROM PRSCreationMaster PCM WITH(NOLOCK)
				INNER JOIN (
					SELECT PRSSysID, MasterDocID, MAX(ProceedsRecvd) AS ProceedsRecvd 
					FROM PRSCreationDistributionDetails WITH(NOLOCK)
					WHERE IsDeleted = 0 
					GROUP BY PRSSysID, MasterDocID
				) PRS ON PRS.PRSSysID = PCM.PRSSysID 
				INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = PRS.MasterDocID AND MD.IsDeleted = 0
				WHERE PCM.IsDeleted = 0
			) PRSM
			GROUP BY GroupSysID
		) Realized ON Realized.GroupSysID = GLC.GroupSysID
		LEFT JOIN (
			SELECT 
				MD.GroupSysID, 
				ExportMade = SUM(ISNULL(BILL.ExportBillAmount, 0)) / @USDRate, 
				LCAmount = SUM(MD.LCAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
			FROM MasterDoc MD WITH(NOLOCK)
			LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = @RateForGroup
			LEFT JOIN (
				SELECT MasterDocID, SUM(ExportBillAmount) AS ExportBillAmount 
				FROM (
					SELECT eb.MasterDocID, ExportBillAmount = eb.ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)
					FROM ExportBillInitiationMaster eb WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE eb.IsDeleted = 0 AND ISNULL(eb.IsCancelled, 0) = 0 AND eb.ExportBillNo IS NOT NULL
					UNION ALL
					SELECT eb.MasterDocID, ExportLocalBillAmount = eb.ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1)
					FROM LocalExportBillInitiationMaster eb WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = eb.CURRENCY_CODE AND CLR.RateFor = @RateForGroup
					WHERE eb.IsDeleted = 0 AND ISNULL(eb.IsCancelled, 0) = 0 AND eb.ExportLocalBillNo IS NOT NULL
				) A GROUP BY MasterDocID
			) BILL ON BILL.MasterDocID = MD.MasterDocID
			WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0 AND MD.IsLienToGroup = 1
			GROUP BY MD.GroupSysID
		) Bill ON Bill.GroupSysID = GLC.GroupSysID
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = GLC.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch Adbpb WITH(NOLOCK) ON Adbpb.BranchID = GLC.ADBranchID
		WHERE GLC.IsDeleted = 0 AND GLC.IsMigrated = 0
	) A 
	ORDER BY A.GroupDate ASC;

	-- Clean up temp tables
	DROP TABLE IF EXISTS #ExportLCDetails;
	DROP TABLE IF EXISTS #AcceptenceInfoSubReport;
	DROP TABLE IF EXISTS #PADEDFInformation;
	DROP TABLE IF EXISTS #EDFInfo;
	DROP TABLE IF EXISTS #PCTimeLoanInformation;
	DROP TABLE IF EXISTS #ExportBillFDBCInformation;
	DROP TABLE IF EXISTS #MarginInformation;
	DROP TABLE IF EXISTS #ForceLoan;
	DROP TABLE IF EXISTS #ExpiredExportLCDetails;
	DROP TABLE IF EXISTS #ExpiredExportLCDetails15Days;
END
GO
