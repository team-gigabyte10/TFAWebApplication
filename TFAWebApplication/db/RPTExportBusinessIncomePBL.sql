USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spRPTExportBusinessIncomePBL]    Script Date: 11/5/2026 3:37:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[spRPTExportBusinessIncomePBL] @FromDate date, @ToDate date
AS
	-- spRPTExportBusinessIncomePBL '2024-05-23', '2026-05-23'
BEGIN
	DECLARE @USDRate NUMERIC(18,4);
	SELECT @USDRate = ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) WHERE RateFor = 'MID RATE' AND CurrencyCode = 'USD'

	SELECT CustomerCode, AC_NO, SUM(CreditTK) CreditTK into #GLAmount
	FROM (
		SELECT D.CustomerCode, CONVERT(DATE, D.TransactionSendingTimeToCBS) SyncDate, D.FCCPer CreditTK, D.AC_NO
		FROM PRSCreationDistributionDetails D WITH(NOLOCK)
			INNER JOIN PRSCreationMaster M WITH(NOLOCK) ON M.PRSSysID = D.PRSSysID AND M.IsDeleted = 0
		WHERE M.IsCheck = 1 AND D.IsDeleted = 0 AND D.IsSendTransactionToCBS = 1 AND D.DRCR_IND = 'C' AND CONVERT(DATE, D.TransactionSendingTimeToCBS) BETWEEN @FromDate AND @ToDate

		UNION ALL

		SELECT D.CustomerID, CONVERT(DATE, D.TransactionSendingTimeToCBS) SyncDate, D.CreditTK, D.AccountNo
		FROM MarginTransactionDetails D WITH(NOLOCK)
			INNER JOIN MarginEncashmentMaster M WITH(NOLOCK) ON M.MAEMID = D.MAEMID AND M.IsDeleted 
			 = 0
		WHERE M.IsCheck = 1 AND D.IsDeleted = 0 AND D.IsSendTransactionToCBS = 1 AND D.DRCR_IND = 'C' AND CONVERT(DATE, D.TransactionSendingTimeToCBS) BETWEEN @FromDate AND @ToDate

		UNION ALL

		SELECT M.Customer, CONVERT(DATE, D.DateUpdated) SyncDate, D.CreditAmount, D.CreditAccountNo
		FROM CustomerVoucherTransDetails D WITH(NOLOCK)
			INNER JOIN LCAdvisingRegister M WITH(NOLOCK) ON M.ExternalId = D.AdditionalMasterID AND M.IsDeleted = 0 AND M.IsCancelled = 0
		WHERE D.IsDeleted = 0 AND D.CreditAmount > 0 AND D.AdditionalFilter = 'LC Advising Register' AND CONVERT(DATE, D.DateUpdated) BETWEEN @FromDate AND @ToDate

		UNION ALL

		SELECT D.CustomerID, CONVERT(DATE, D.TransactionSendingTimeToCBS) SyncDate, D.CreditTK, D.AccountNo
		FROM VoucherInterfaceChild D WITH(NOLOCK)
			INNER JOIN VoucherInterfaceMaster M ON M.MAEMID = D.MAEMID AND M.IsDeleted = 0
		WHERE M.IsCheck = 1 AND D.IsDeleted = 0 AND D.IsSendTransactionToCBS = 1 AND D.DRCR_IND = 'C' AND M.EventName IN(151, 152, 202, 153, 162, 235, 165, 166, 189, 163, 164, 214, 158, 159, 203, 228, 229, 204, 239, 240, 174, 183, 206, 211, 212, 209, 210, 175, 182, 184, 185, 186, 187, 1) AND CONVERT(DATE, D.TransactionSendingTimeToCBS) BETWEEN @FromDate AND @ToDate
	) GL
	GROUP BY CustomerCode, AC_NO

	SELECT *
	FROM (
		SELECT
			CPM.CustomerID,
			CPM.CIF,
			RM.EmployeeName,
			CPM.CustomerName,
			AD.BranchCode ADBranchCode,
			AD.BranchName ADBranchName,
			NonAD.BranchCode NonADBranchCode,
			NonAD.BranchName NonADBranchName,
			CPM.BusinessUnit,
			@USDRate USDRate,
			ISNULL(LC.LCAmountBDT, 0) LCAmountBDT,
			CONVERT(DECIMAL(18, 2), ISNULL(LC.LCAmountBDT, 0)/@USDRate) LCAmountUSD,
			ISNULL(LBill.LocalBillAmountBDT, 0) LocalBillAmountBDT,
			CONVERT(DECIMAL(18, 2), ISNULL(LBill.LocalBillAmountBDT, 0)/@USDRate) LocalBillAmountUSD,
			ISNULL(EBill.ExportBillAmountBDT, 0) ExportBillAmountBDT,
			CONVERT(DECIMAL(18, 2), ISNULL(EBill.ExportBillAmountBDT, 0)/@USDRate) ExportBillAmountUSD,
			AC_303010205 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010205'), 0),
			AC_303010206 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010206'), 0),
			AC_303010211 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010211'), 0),
			AC_303010220 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010220'), 0),
			AC_303010231 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010231'), 0),
			AC_303010238 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010238'), 0),
			AC_303010243 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '303010243'), 0),
			AC_304010310 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010310'), 0),
			AC_304010312 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010312'), 0),
			AC_304010313 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010313'), 0),
			AC_304010316 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010316'), 0),
			AC_304010322 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010322'), 0),
			AC_304010323 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010323'), 0),
			AC_304010325 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010325'), 0),
			AC_304010326 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010326'), 0),
			AC_304010333 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010333'), 0),
			AC_304010334 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010334'), 0),
			AC_304010335 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010335'), 0),
			AC_304010338 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010338'), 0),
			AC_304010340 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010340'), 0),
			AC_304010343 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010343'), 0),
			AC_304010344 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010344'), 0),
			AC_304010357 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010357'), 0),
			AC_304010359 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010359'), 0),
			AC_304010360 = ISNULL((SELECT CreditTK FROM #GLAmount WHERE CustomerCode = CPM.CustomerID AND AC_NO = '304010360'), 0)
		FROM SystemManager..CustomerProfileMaster CPM WITH(NOLOCK)
			LEFT JOIN SystemManager..t_Employee RM WITH(NOLOCK) ON RM.EmployeeCode = CPM.RMID
			LEFT JOIN SystemManager..CustomerBranchMap BM WITH(NOLOCK) ON BM.CustomerID = CPM.CustomerID AND BM.IsDeleted = 0 AND BM.IsDefault = 1
			LEFT JOIN SystemManager..BankProfileBranch AD WITH(NOLOCK) ON AD.BranchID = BM.BranchID AND AD.IsADCode = 1
			LEFT JOIN SystemManager..BankProfileBranch NonAD WITH(NOLOCK) ON NonAD.BranchID = BM.BranchID AND NonAD.IsADCode = 0
			LEFT JOIN (
				SELECT A.CustomerID, SUM(A.LCAmount * CLR.ConvertFactor) LCAmountBDT
				FROM (
					SELECT
						GLC.CustomerID,
						MD.LCAmount,
						MD.Currency
					FROM MasterDoc MD WITH(NOLOCK)
						INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD.GroupSysID
						LEFT JOIN MasterLCAmmendment AMD WITH(NOLOCK) ON AMD.MasterDocID = MD.MasterDocID AND AMD.IsDeleted 
							= 0 AND AMD.IsCancelled = 0
					WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0 AND MD.IsConformed = 1 AND MD.IsLienToGroup = 1 AND MD.ReplacedLCSC = 0 AND AMD.MasterDocID IS NULL AND CONVERT(DATE, MD.DateOfLien) BETWEEN @FromDate AND @ToDate
			
					UNION ALL
			
					SELECT
						GLC.CustomerID,
						ValuAmd = CASE WHEN AMD.IncreaseAmount > 0 THEN AMD.IncreaseAmount WHEN AMD.DecreaseAmount > 0 THEN -AMD.DecreaseAmount ELSE 0 END,
						AMD.CONTRACT_CCY
					FROM MasterLCAmmendment AMD WITH(NOLOCK)
						INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = AMD.GroupSysID
					WHERE AMD.IsDeleted = 0 AND AMD.IsCancelled = 0 AND AMD.IsConformed = 1 AND CONVERT(DATE, AMD.AmmendmentDate) BETWEEN @FromDate AND @ToDate
				) A
				LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = A.Currency AND CLR.RateFor = 'MID RATE'
				GROUP BY A.CustomerID
			) LC ON LC.CustomerID = CPM.CustomerID
			LEFT JOIN (
				SELECT	
					B.CustomerCode, SUM(B.ExportLocalBillAmount * CLR.ConvertFactor) LocalBillAmountBDT
				FROM LocalExportBillInitiationMaster B WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = B.CURRENCY_CODE AND CLR.RateFor = 'MID RATE'
				WHERE B.IsDeleted = 0 AND ISNULL(B.IsCancelled, 0) = 0 AND B.ExportLocalBillNo IS NOT NULL AND CONVERT(DATE, B.BillGenerationDate) BETWEEN @FromDate AND @ToDate
				GROUP BY B.CustomerCode
			) LBill ON LBill.CustomerCode = CPM.CustomerID
			LEFT JOIN (
				SELECT	
					B.CustomerCode, SUM(B.ExportBillAmount * CLR.ConvertFactor) ExportBillAmountBDT
				FROM ExportBillInitiationMaster B WITH(NOLOCK)
					LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = B.CURRENCY_CODE AND CLR.RateFor = 'MID RATE'
				WHERE B.IsDeleted = 0 AND ISNULL(B.IsCancelled, 0) = 0 AND B.ExportBillNo IS NOT NULL AND CONVERT(DATE, B.BillGenerationDate) BETWEEN @FromDate AND @ToDate
				GROUP BY B.CustomerCode
			) EBill ON EBill.CustomerCode = CPM.CustomerID
		WHERE CPM.IsDeleted = 0 
	) A
	WHERE LCAmountBDT > 0 OR (LocalBillAmountBDT + ExportBillAmountBDT) > 0 OR ((AC_303010205 + AC_303010206 + AC_303010211 + AC_303010220 + AC_303010231 + AC_303010238 + AC_303010243 + AC_304010310 + AC_304010312 + AC_304010313 + AC_304010316 + AC_304010322 + AC_304010323 + AC_304010325 + AC_304010326 + AC_304010333 + AC_304010334 + AC_304010335 + AC_304010338 + AC_304010340 + AC_304010343 + AC_304010344 + AC_304010357 + AC_304010359 + AC_304010360) > 0)
	ORDER BY CustomerName
END