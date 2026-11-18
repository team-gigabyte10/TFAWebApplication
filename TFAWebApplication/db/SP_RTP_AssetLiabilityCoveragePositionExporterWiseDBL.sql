USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RTP_AssetLiabilityCoveragePositionExporterWiseDBL]    Script Date: 11/18/2026 05:55:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RTP_AssetLiabilityCoveragePositionExporterWiseDBL]
	@BranchID    VARCHAR(50),
	@CustomerID	 VARCHAR(50)
AS									
	-- SP_RTP_AssetLiabilityCoveragePositionExporterWiseDBL 'OBPB/2020/9', '21Aug202C/1379'
BEGIN
	SET NOCOUNT ON;

	-- USD Exchange Rate (BC Selling)
	DECLARE @USDRate DECIMAL(18,4);
	SELECT @USDRate = ConvertFactor 
	FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) 
	WHERE RateFor = 'BC SELLING' AND CurrencyCode = 'USD';

	IF @USDRate IS NULL OR @USDRate <= 0
		SET @USDRate = 1.0;

	DECLARE @Amount2Million DECIMAL(18,6) = 0.000001;

	--------------------------------------------------------------------------------------
	-- Customer and Branch Information
	--------------------------------------------------------------------------------------
	DECLARE @CustomerName VARCHAR(250) = '';
	SELECT TOP 1 @CustomerName = CPM.CustomerName + ' - ' + ISNULL(CPM.CIF, '')
	FROM SystemManager..CustomerProfileMaster CPM WITH(NOLOCK)
	WHERE CPM.CustomerID = @CustomerID AND CPM.IsDeleted = 0;

	--------------------------------------------------------------------------------------
	-- 1. ASSETS: Documents Under Collection (Unrealized Export Bills)
	--------------------------------------------------------------------------------------
	DECLARE @DocUnderCollection_USD DECIMAL(18,2) = 0, @DocUnderCollection_BDT DECIMAL(18,2) = 0;

	SELECT 
		@DocUnderCollection_USD = SUM(DocUSD),
		@DocUnderCollection_BDT = SUM(DocBDT)
	FROM (
		-- Foreign Export Bills
		SELECT 
			((E.ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS DocUSD,
			(E.ExportBillAmount * ISNULL(CLR.ConvertFactor, 1)) AS DocBDT
		FROM ExportBillInitiationMaster E WITH(NOLOCK)
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = E.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN PRSCreationDistributionDetails d WITH(NOLOCK) ON d.BillRefNo = E.EBIID AND d.PRSNCADID != 'NOT_NCA' AND d.IsDeleted = 0
		WHERE E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0 AND E.ExportBillNo IS NOT NULL AND ISNULL(E.IsARVAdjusted, 0) = 0
		  AND d.BillRefNo IS NULL
		  AND E.BranchID = @BranchID AND E.CustomerCode = @CustomerID

		UNION ALL

		-- Local Export Bills
		SELECT 
			((E.ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS DocUSD,
			(E.ExportLocalBillAmount * ISNULL(CLR.ConvertFactor, 1)) AS DocBDT
		FROM LocalExportBillInitiationMaster E WITH(NOLOCK)
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = E.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN PRSCreationDistributionDetails d WITH(NOLOCK) ON d.BillRefNo = E.EBIID AND d.PRSNCADID != 'NOT_NCA' AND d.IsDeleted = 0
		WHERE E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0 AND E.ExportLocalBillNo IS NOT NULL
		  AND d.BillRefNo IS NULL
		  AND E.BranchID = @BranchID AND E.CustomerCode = @CustomerID
	) DocColl;

	SET @DocUnderCollection_USD = ISNULL(@DocUnderCollection_USD, 0);
	SET @DocUnderCollection_BDT = ISNULL(@DocUnderCollection_BDT, 0);

	--------------------------------------------------------------------------------------
	-- 2. ASSETS: Export LC in hand / Confirmed Sales Contract in hand (Condition 3: Live & Unexpired Only)
	--------------------------------------------------------------------------------------
	DECLARE @ExportLCInHand_USD DECIMAL(18,2) = 0;

	SELECT @ExportLCInHand_USD = SUM(LCOutUSD)
	FROM (
		SELECT 
			CASE 
				WHEN ((M.LCAmount + (M.LCAmount * ISNULL(M.TolerancePercent, 0) / 100.0)) - (ISNULL(Bill.ExportBillAmount, 0) + ISNULL(Closed.CLOSED_VALUE, 0))) > 0
				THEN (((M.LCAmount + (M.LCAmount * ISNULL(M.TolerancePercent, 0) / 100.0)) - (ISNULL(Bill.ExportBillAmount, 0) + ISNULL(Closed.CLOSED_VALUE, 0))) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
				ELSE 0 
			END AS LCOutUSD
		FROM MasterDoc M WITH(NOLOCK)
		INNER JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = M.GroupSysID AND G.IsDeleted = 0 AND G.IsClosedGroup = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(M.Currency, '') AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN (
			SELECT UBS_CONT_REF_NO, SUM(ISNULL(CLOSED_VALUE, 0)) AS CLOSED_VALUE 
			FROM ClosureTransaction WITH(NOLOCK) WHERE IsDeleted = 0 GROUP BY UBS_CONT_REF_NO
		) Closed ON Closed.UBS_CONT_REF_NO = M.ExternalID
		LEFT JOIN (
			SELECT MasterDocID, SUM(BillAmt) AS ExportBillAmount
			FROM (
				SELECT MasterDocID, ExportBillAmount AS BillAmt FROM ExportBillInitiationMaster WITH(NOLOCK) WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL
				UNION ALL
				SELECT MasterDocID, ExportLocalBillAmount AS BillAmt FROM LocalExportBillInitiationMaster WITH(NOLOCK) WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
			) B
			GROUP BY MasterDocID
		) Bill ON Bill.MasterDocID = M.MasterDocID
		WHERE M.IsDeleted = 0 AND M.IsCancelled = 0
		  -- Condition 3: Live LC/Contract which have valid, unexpired expiry date
		  AND M.ExpiryDate IS NOT NULL 
		  AND CAST(M.ExpiryDate AS DATE) >= CAST(GETDATE() AS DATE)
		  AND G.BankBranchID = @BranchID AND G.CustomerID = @CustomerID
	) ExpLC;

	SET @ExportLCInHand_USD = ISNULL(@ExportLCInHand_USD, 0);

	--------------------------------------------------------------------------------------
	-- 3. ASSETS: FC Held Balance / DFC Balance
	--------------------------------------------------------------------------------------
	DECLARE @FCHeldBalance_USD DECIMAL(18,2) = 0, @DFCBalance_BDT DECIMAL(18,2) = 0;

	--------------------------------------------------------------------------------------
	-- 4. LIABILITIES: BTB LC Outstanding (BBLC Amount - Bills - SG - Closed)
	--------------------------------------------------------------------------------------
	DECLARE @BTBLC_USD DECIMAL(18,2) = 0, @BBLCOut_BDT DECIMAL(18,2) = 0;

	SELECT 
		@BTBLC_USD = SUM(BBLC_USD),
		@BBLCOut_BDT = SUM(BBLC_BDT)
	FROM (
		SELECT 
			CASE 
				WHEN (BBLCTotal - ISNULL(Bill.BillAmount, 0) - ISNULL(SG.Amount, 0) - ISNULL(Closed.CLOSED_VALUE, 0)) > 0
				THEN ((BBLCTotal - ISNULL(Bill.BillAmount, 0) - ISNULL(SG.Amount, 0) - ISNULL(Closed.CLOSED_VALUE, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
				ELSE 0 
			END AS BBLC_USD,
			CASE 
				WHEN (BBLCTotal - ISNULL(Bill.BillAmount, 0) - ISNULL(SG.Amount, 0) - ISNULL(Closed.CLOSED_VALUE, 0)) > 0
				THEN ((BBLCTotal - ISNULL(Bill.BillAmount, 0) - ISNULL(SG.Amount, 0) - ISNULL(Closed.CLOSED_VALUE, 0)) * ISNULL(CLR.ConvertFactor, 1))
				ELSE 0 
			END AS BBLC_BDT
		FROM (
			SELECT 
				m.BBLCID, m.ExternalID, m.Currency,
				(m.BBLCAmount + (m.BBLCAmount * ISNULL(m.Toleranace, 0) / 100.0)) AS BBLCTotal,
				g.BankBranchID, g.CustomerID
			FROM BBLCMaster m WITH(NOLOCK)
			INNER JOIN GroupLC g WITH(NOLOCK) ON g.GroupSysID = m.GroupSysID AND g.IsDeleted = 0 AND g.IsClosedGroup = 0
			WHERE m.IsDeleted = 0 AND m.IsCancelled = 0 AND m.BBLCNo IS NOT NULL
			  AND g.BankBranchID = @BranchID AND g.CustomerID = @CustomerID
		) m
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = m.Currency AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN (
			SELECT UBS_CONT_REF_NO, SUM(ISNULL(CLOSED_VALUE, 0)) AS CLOSED_VALUE 
			FROM ClosureTransaction WITH(NOLOCK) WHERE IsDeleted = 0 GROUP BY UBS_CONT_REF_NO
		) Closed ON Closed.UBS_CONT_REF_NO = m.ExternalID
		LEFT JOIN (
			SELECT BBLCID, SUM(ISNULL(BillAmount, 0)) AS BillAmount 
			FROM ForeignDocumentAcceptanceMaster WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsCancelled = 0 AND BillNo IS NOT NULL
			GROUP BY BBLCID
		) Bill ON Bill.BBLCID = m.BBLCID
		LEFT JOIN (
			SELECT ImportOrBBLCID, SUM(Amount) AS Amount
			FROM ShippingGuaranteeMaster sm WITH(NOLOCK)
			LEFT JOIN ForeignDocumentShippingGuaranteeMap fsm WITH(NOLOCK) ON fsm.SGMID = sm.SGMID AND fsm.IsDeleted = 0 AND fsm.IsCancelled = 0
			WHERE sm.IsDeleted = 0 AND sm.IsCancelled = 0 AND sm.SGRefNo IS NOT NULL AND fsm.SGMID IS NULL
			GROUP BY ImportOrBBLCID
		) SG ON SG.ImportOrBBLCID = m.BBLCID
	) BBLCOuts;

	SET @BTBLC_USD = ISNULL(@BTBLC_USD, 0);
	SET @BBLCOut_BDT = ISNULL(@BBLCOut_BDT, 0);

	--------------------------------------------------------------------------------------
	-- 5. LIABILITIES: BTB BILL Outstanding (Accepted Bills - Payments)
	--------------------------------------------------------------------------------------
	DECLARE @BTBBill_USD DECIMAL(18,2) = 0, @BTBBill_BDT DECIMAL(18,2) = 0;

	SELECT 
		@BTBBill_USD = SUM(BillUSD),
		@BTBBill_BDT = SUM(BillBDT)
	FROM (
		SELECT 
			(( (ISNULL(FDAM.BillAmount, 0) - ISNULL(FDPM.PaymentAmount, 0)) * ISNULL(CLR.ConvertFactor, 1) ) / @USDRate) AS BillUSD,
			( (ISNULL(FDAM.BillAmount, 0) - ISNULL(FDPM.PaymentAmount, 0)) * ISNULL(CLR.ConvertFactor, 1) ) AS BillBDT
		FROM ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK)
		INNER JOIN BBLCMaster BBLCM WITH(NOLOCK) ON BBLCM.BBLCID = FDAM.BBLCID AND BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 AND BBLCM.BBLCNo IS NOT NULL
		INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = BBLCM.GroupSysID AND GLC.IsDeleted = 0 AND GLC.IsClosedGroup = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(FDAM.Currency, '') AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN (
			SELECT FDAID, SUM(ISNULL(PaymentAmount, 0)) AS PaymentAmount
			FROM ForeignDocumentPaymentMaster WITH(NOLOCK)
			WHERE IsDeleted = 0 AND ISNULL(PaymentAmount, 0) > 0
			GROUP BY FDAID
		) FDPM ON FDPM.FDAID = FDAM.FDAID
		WHERE FDAM.IsDeleted = 0 AND FDAM.IsCancelled = 0 AND FDAM.BillNo IS NOT NULL 
		  AND ISNULL(FDAM.BillAmount, 0) > 0 AND ISNULL(FDAM.IsImportLC, 0) = 0
		  AND (ISNULL(FDAM.BillAmount, 0) - ISNULL(FDPM.PaymentAmount, 0)) > 0
		  AND GLC.BankBranchID = @BranchID AND GLC.CustomerID = @CustomerID
	) BTBBills;

	SET @BTBBill_USD = ISNULL(@BTBBill_USD, 0);
	SET @BTBBill_BDT = ISNULL(@BTBBill_BDT, 0);

	--------------------------------------------------------------------------------------
	-- 6. LIABILITIES: EDF Loan Outstanding
	--------------------------------------------------------------------------------------
	DECLARE @EDFLoan_USD DECIMAL(18,2) = 0, @EDFLoan_BDT DECIMAL(18,2) = 0;

	SELECT 
		@EDFLoan_USD = SUM(EDFUSD),
		@EDFLoan_BDT = SUM(EDFBDT)
	FROM (
		SELECT 
			((ISNULL(L.TOT_OS, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS EDFUSD,
			(ISNULL(L.TOT_OS, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) AS EDFBDT
		FROM LoanCreation L WITH(NOLOCK)
		INNER JOIN BBLCMaster BBLCM WITH(NOLOCK) ON BBLCM.BBLCID = L.BBLCID AND BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 AND BBLCM.BBLCNo IS NOT NULL
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(L.LoanCurrency, ISNULL(L.Currency, 'USD')) AND CLR.RateFor = 'BC SELLING'
		WHERE L.IsDeleted = 0 AND L.Product = 'LEDF' AND L.LoanNo IS NOT NULL
		  AND L.BankBranchID = @BranchID AND L.Customer = @CustomerID
	) EDF;

	SET @EDFLoan_USD = ISNULL(@EDFLoan_USD, 0);
	SET @EDFLoan_BDT = ISNULL(@EDFLoan_BDT, 0);

	--------------------------------------------------------------------------------------
	-- 7. LIABILITIES: PC Loan Outstanding
	--------------------------------------------------------------------------------------
	DECLARE @PC_USD DECIMAL(18,2) = 0;

	SELECT @PC_USD = SUM(PCUSD)
	FROM (
		SELECT 
			CASE 
				WHEN P.UBSSyncProcessID > 0 THEN P.TOT_OS / @USDRate 
				ELSE P.PCAmountTK / @USDRate 
			END AS PCUSD
		FROM PCDisbursementMaster P WITH(NOLOCK)
		WHERE P.IsDeleted = 0 AND P.BranchID = @BranchID AND P.CustomerID = @CustomerID
	) PCD;

	SET @PC_USD = ISNULL(@PC_USD, 0);

	--------------------------------------------------------------------------------------
	-- 8. LIABILITIES: OD (Others) / Short Term Loan Working Capital
	--------------------------------------------------------------------------------------
	DECLARE @ODOthers_USD DECIMAL(18,2) = 0;

	SELECT @ODOthers_USD = SUM(ODUSD)
	FROM (
		SELECT 
			CASE 
				WHEN P.UBSSyncProcessID > 0 THEN ((P.TOT_OS * ISNULL(CLR.ConvertFactor, 1)) / @USDRate)
				ELSE ((P.DisbursedAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate)
			END AS ODUSD
		FROM PurchaseDiscountForeignDocumentMaster P WITH(NOLOCK)
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(P.AC_CCY, 'BDT') AND CLR.RateFor = 'BC SELLING'
		WHERE P.IsDeleted = 0 AND P.IsExportLoan = 1 AND P.LoanNumber IS NOT NULL 
		  AND P.PRODUCT_CODE IN ('STLN', 'STLO', 'OSTL')
		  AND P.BranchID = @BranchID AND P.CustomerID = @CustomerID
	) OD;

	SET @ODOthers_USD = ISNULL(@ODOthers_USD, 0);

	--------------------------------------------------------------------------------------
	-- 9. LIABILITIES: FDBP (Purchased & Discounted Bills)
	--------------------------------------------------------------------------------------
	DECLARE @FDBP_USD DECIMAL(18,2) = 0;

	SELECT @FDBP_USD = SUM(FDBPUSD)
	FROM (
		-- Foreign FDBP
		SELECT ((PDFDM.DisbursedAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS FDBPUSD
		FROM (
			SELECT EBIID, SUM(ISNULL(DisbursedAmount, 0)) AS DisbursedAmount
			FROM PurchaseDiscountForeignDocumentMaster WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsCancelled = 0 AND LoanNumber IS NOT NULL AND ISNULL(IsExportLoan, 0) = 0
			GROUP BY EBIID
		) PDFDM
		INNER JOIN ExportBillInitiationMaster E WITH(NOLOCK) ON E.EBIID = PDFDM.EBIID AND E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
		WHERE E.BranchID = @BranchID AND E.CustomerCode = @CustomerID

		UNION ALL

		-- Local FDBP
		SELECT ((PDFDM.DisbursedAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS FDBPUSD
		FROM (
			SELECT EBIID, SUM(ISNULL(DisbursedAmount, 0)) AS DisbursedAmount
			FROM LDBCPurchase WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsCancelled = 0 AND LoanNumber IS NOT NULL
			GROUP BY EBIID
		) PDFDM
		INNER JOIN LocalExportBillInitiationMaster E WITH(NOLOCK) ON E.EBIID = PDFDM.EBIID AND E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
		WHERE E.BranchID = @BranchID AND E.CustomerCode = @CustomerID
	) FDBPTbl;

	SET @FDBP_USD = ISNULL(@FDBP_USD, 0);

	--------------------------------------------------------------------------------------
	-- 10. LIABILITIES: Time Loan
	--------------------------------------------------------------------------------------
	DECLARE @TimeLoan_USD DECIMAL(18,2) = 0;

	SELECT @TimeLoan_USD = SUM(TLUSD)
	FROM (
		SELECT 
			CASE 
				WHEN P.UBSSyncProcessID > 0 THEN ((P.TOT_OS * ISNULL(CLR.ConvertFactor, 1)) / @USDRate)
				ELSE ((P.DisbursedAmount * ISNULL(CLR.ConvertFactor, 1)) / @USDRate)
			END AS TLUSD
		FROM PurchaseDiscountForeignDocumentMaster P WITH(NOLOCK)
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(P.AC_CCY, 'BDT') AND CLR.RateFor = 'BC SELLING'
		WHERE P.IsDeleted = 0 AND P.IsExportLoan = 1 AND P.LoanNumber IS NOT NULL 
		  AND P.PRODUCT_CODE IN ('TMLN', 'OTML')
		  AND P.BranchID = @BranchID AND P.CustomerID = @CustomerID
	) TL;

	SET @TimeLoan_USD = ISNULL(@TimeLoan_USD, 0);

	--------------------------------------------------------------------------------------
	-- 11. LIABILITIES: Forced Loan (FLAB)
	--------------------------------------------------------------------------------------
	DECLARE @ForcedLoan_USD DECIMAL(18,2) = 0;

	SELECT @ForcedLoan_USD = SUM(FLABUSD)
	FROM (
		SELECT ((ISNULL(L.TOT_OS, L.LoanAmount) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS FLABUSD
		FROM LoanCreation L WITH(NOLOCK)
		INNER JOIN BBLCMaster BBLCM WITH(NOLOCK) ON BBLCM.BBLCID = L.BBLCID AND BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 AND BBLCM.BBLCNo IS NOT NULL
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(L.LoanCurrency, ISNULL(L.Currency, 'BDT')) AND CLR.RateFor = 'BC SELLING'
		WHERE L.IsDeleted = 0 AND L.Product = 'FLAB' AND L.LoanNo IS NOT NULL
		  AND L.BankBranchID = @BranchID AND L.Customer = @CustomerID
	) FLABTbl;

	SET @ForcedLoan_USD = ISNULL(@ForcedLoan_USD, 0);

	--------------------------------------------------------------------------------------
	-- 12. CONDITION 4: Next Three Months Accepted Liabilities (BTB Lodgment in Eqv. USD)
	--------------------------------------------------------------------------------------
	DECLARE @Next3MonthsAcceptedLiabilities_USD DECIMAL(18,2) = 0;

	SELECT @Next3MonthsAcceptedLiabilities_USD = SUM(Next3LiabUSD)
	FROM (
		SELECT ((ISNULL(FDAM.BillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS Next3LiabUSD
		FROM ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK)
		INNER JOIN BBLCMaster BBLCM WITH(NOLOCK) ON BBLCM.BBLCID = FDAM.BBLCID AND BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 AND BBLCM.BBLCNo IS NOT NULL
		INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = BBLCM.GroupSysID AND GLC.IsDeleted = 0 AND GLC.IsClosedGroup = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(FDAM.Currency, '') AND CLR.RateFor = 'BC SELLING'
		WHERE FDAM.IsDeleted = 0 AND FDAM.IsCancelled = 0 AND FDAM.BillNo IS NOT NULL
		  AND FDAM.MATURITY_DATE IS NOT NULL
		  AND CAST(FDAM.MATURITY_DATE AS DATE) >= CAST(GETDATE() AS DATE)
		  AND CAST(FDAM.MATURITY_DATE AS DATE) <= DATEADD(MONTH, 3, CAST(GETDATE() AS DATE))
		  AND GLC.BankBranchID = @BranchID AND GLC.CustomerID = @CustomerID
	) N3L;

	SET @Next3MonthsAcceptedLiabilities_USD = ISNULL(@Next3MonthsAcceptedLiabilities_USD, 0);

	--------------------------------------------------------------------------------------
	-- 13. CONDITION 5: Next Three Months Accepted Receivables (Export Bills in Eqv. USD)
	--------------------------------------------------------------------------------------
	DECLARE @Next3MonthsAcceptedReceivables_USD DECIMAL(18,2) = 0;

	SELECT @Next3MonthsAcceptedReceivables_USD = SUM(Next3RecvUSD)
	FROM (
		-- Foreign Export Bills
		SELECT ((ISNULL(E.ExportBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS Next3RecvUSD
		FROM ExportBillInitiationMaster E WITH(NOLOCK)
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = E.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
		INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD.GroupSysID AND GLC.IsDeleted = 0 AND GLC.IsClosedGroup = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
		WHERE E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0 AND E.ExportBillNo IS NOT NULL
		  AND E.MaturityDate IS NOT NULL
		  AND CAST(E.MaturityDate AS DATE) >= CAST(GETDATE() AS DATE)
		  AND CAST(E.MaturityDate AS DATE) <= DATEADD(MONTH, 3, CAST(GETDATE() AS DATE))
		  AND GLC.BankBranchID = @BranchID AND GLC.CustomerID = @CustomerID

		UNION ALL

		-- Local Export Bills
		SELECT ((ISNULL(E.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate) AS Next3RecvUSD
		FROM LocalExportBillInitiationMaster E WITH(NOLOCK)
		INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = E.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
		INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD.GroupSysID AND GLC.IsDeleted = 0 AND GLC.IsClosedGroup = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
		WHERE E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0 AND E.ExportLocalBillNo IS NOT NULL
		  AND E.MaturityDate IS NOT NULL
		  AND CAST(E.MaturityDate AS DATE) >= CAST(GETDATE() AS DATE)
		  AND CAST(E.MaturityDate AS DATE) <= DATEADD(MONTH, 3, CAST(GETDATE() AS DATE))
		  AND GLC.BankBranchID = @BranchID AND GLC.CustomerID = @CustomerID
	) N3R;

	SET @Next3MonthsAcceptedReceivables_USD = ISNULL(@Next3MonthsAcceptedReceivables_USD, 0);

	--------------------------------------------------------------------------------------
	-- Subtotals and Totals Calculations
	--------------------------------------------------------------------------------------
	-- Table 1: Subtotals and Totals (Eqv. USD)
	DECLARE @TotalImportLiability_USD DECIMAL(18,2) = @BTBLC_USD + @BTBBill_USD + @EDFLoan_USD;
	DECLARE @TotalAssets_USD DECIMAL(18,2) = @DocUnderCollection_USD + @ExportLCInHand_USD + @FCHeldBalance_USD;
	DECLARE @TotalLiabilities_USD DECIMAL(18,2) = @TotalImportLiability_USD + @PC_USD + @ODOthers_USD + @FDBP_USD + @TimeLoan_USD + @ForcedLoan_USD;
	DECLARE @NetPosition_USD DECIMAL(18,2) = @TotalAssets_USD - @TotalLiabilities_USD;

	-- Table 2: BDT in Million
	DECLARE @BBLCOuts_M DECIMAL(18,2) = CAST(@BBLCOut_BDT * @Amount2Million AS DECIMAL(18,2));
	DECLARE @BTBBillOuts_M DECIMAL(18,2) = CAST(@BTBBill_BDT * @Amount2Million AS DECIMAL(18,2));
	DECLARE @EDFOuts_M DECIMAL(18,2) = CAST(@EDFLoan_BDT * @Amount2Million AS DECIMAL(18,2));
	DECLARE @TotalImportLiability_M DECIMAL(18,2) = @BBLCOuts_M + @BTBBillOuts_M + @EDFOuts_M;
	DECLARE @DFCBalance_M DECIMAL(18,2) = CAST(@DFCBalance_BDT * @Amount2Million AS DECIMAL(18,2));
	DECLARE @DocUnderCollection_M DECIMAL(18,2) = CAST(@DocUnderCollection_BDT * @Amount2Million AS DECIMAL(18,2));
	DECLARE @Coverage_M DECIMAL(18,2) = @DFCBalance_M + @DocUnderCollection_M;

	--------------------------------------------------------------------------------------
	-- Final Result Set
	--------------------------------------------------------------------------------------
	SELECT
		@CustomerName AS CustomerName,
		@BranchID AS BranchID,
		@CustomerID AS CustomerID,

		-- Table 1: Assets (Eqv. USD)
		@DocUnderCollection_USD AS DocumentsUnderCollection,
		@ExportLCInHand_USD AS ExportLC_in_hand_ConfirmedSales_contract_in_hand,
		@FCHeldBalance_USD AS DFCBalance,
		@TotalAssets_USD AS TotalAssets,

		-- Table 1: Liabilities (Eqv. USD)
		@BTBLC_USD AS BBLC,
		@BTBBill_USD AS ABP,
		@EDFLoan_USD AS EDF,
		@TotalImportLiability_USD AS TotalImportLiability,
		@PC_USD AS PC,
		@ODOthers_USD AS STLWC,
		@FDBP_USD AS FDBP,
		@TimeLoan_USD AS TimeLoan,
		@ForcedLoan_USD AS FLAB,
		@TotalLiabilities_USD AS TotalLiabilities,

		-- Table 1: Net Position (Condition 2)
		@NetPosition_USD AS NetPosition,

		-- Table 2: Summary of BBLC O/S and Coverage Position (BDT in Million)
		@BBLCOuts_M AS OutstandingBBLCAmount,
		@BTBBillOuts_M AS ABP_M,
		@EDFOuts_M AS EDF_M,
		@TotalImportLiability_M AS TotalImportLiability_M,
		@DFCBalance_M AS DFCBalance_M,
		@DocUnderCollection_M AS Documents_under_collection_unpurchased_M,
		@Coverage_M AS Coverage_M,

		-- Conditions 4 & 5: Next 3 Months Horizon (Eqv. USD)
		@Next3MonthsAcceptedLiabilities_USD AS Next3MonthsAcceptedLiabilities_USD,
		@Next3MonthsAcceptedReceivables_USD AS Next3MonthsAcceptedReceivables_USD,

		-- Legacy compatibility aliases
		@USDRate AS ConvertFactor,
		'USD' AS CURRENCY_CODE,
		0 AS DocNotLodgeYet,
		0 AS DocNotLodgeYet_M,
		0 AS SG,
		0 AS SG_M,
		0 AS FLAB_M,
		@DocUnderCollection_USD AS Documents_under_collection_unpurchased,
		0 AS BBLCWithTolAmount,
		0 AS SavedAndGeneratedBTBBillAmount,
		0 AS OutstandingSGAmount;
END
GO
