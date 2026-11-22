USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spLocalExportBillRealizationRegisterPBL]    Script Date: 11/22/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[spLocalExportBillRealizationRegisterPBL] 
	@FromDate DATE, 
	@ToDate DATE
AS
	-- EXEC spLocalExportBillRealizationRegisterPBL '2024-08-01', '2025-03-03'
BEGIN  
	SET NOCOUNT ON;

	DECLARE @USDRate DECIMAL(18,4);
	SELECT @USDRate = ConvertFactor 
	FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) 
	WHERE RateFor = 'BC SELLING' AND CurrencyCode = 'USD';

	IF @USDRate IS NULL OR @USDRate = 0
		SET @USDRate = 1;

	SELECT
		COALESCE(
			NULLIF(BPB.BranchName, ''), 
			NULLIF(ADbpb.BranchName, ''), 
			NULLIF(BPB_MD.BranchName, ''), 
			NULLIF(ADbpb_MD.BranchName, ''), 
			NULLIF(BPB_G.BranchName, ''),
			''
		) AS BranchName,
		COALESCE(NULLIF(LEB.ExternalID, ''), NULLIF(MD.ExternalID, ''), '') AS T24Reference,
		CONCAT_WS(', ', NULLIF(CPM.CustomerName, ''), NULLIF(CPM.CustomerAddress, '')) AS ExporterNameAddr,
		COALESCE(NULLIF(CPM.CIF, ''), NULLIF(LEB.CustomerCode, ''), '') AS CustomerID,
		CONCAT_WS(', ', 
			NULLIF(COALESCE(NULLIF(Issue.Name, ''), NULLIF(OpenBank.Name, ''), NULLIF(LEBIssueBank.Name, ''), NULLIF(DocSendBank.Name, '')), ''), 
			NULLIF(COALESCE(NULLIF(IssueBranch.Name, ''), NULLIF(DocSendBranch.Name, ''), NULLIF(OpenBankBranch.Name, '')), '')
		) AS ImporterBankBranch,
		COALESCE(NULLIF(MD.LCNo, ''), NULLIF(Advi.LCNumber, ''), '') AS LCNumber, 
		ISNULL(PUR.StartDate, '') AS DateOfDiscounting,
		LEB.CURRENCY_CODE AS Currency,
		ISNULL(LEB.ExportLocalBillAmount, 0) AS DocumentAmount,
		ISNULL(PRSM.RealizationAmount, 0) AS ReceivedAmount,
		COALESCE(EBM.MaturityDate, LEB.MaturityDate) AS DueDate,
		COALESCE(PAY.CreditDate, PRSM.Date) AS PaymentDate,
		CASE 
			WHEN COALESCE(EBM.MaturityDate, LEB.MaturityDate) IS NOT NULL 
				AND COALESCE(PAY.CreditDate, PRSM.Date) > COALESCE(EBM.MaturityDate, LEB.MaturityDate)
				THEN DATEDIFF(DAY, COALESCE(EBM.MaturityDate, LEB.MaturityDate), COALESCE(PAY.CreditDate, PRSM.Date))
			ELSE 0 
		END AS OverdueDay,
		ISNULL(PUR.LoanNumber, '') AS LDNumber,
		ISNULL(LEB.ExportLocalBillNo, '') AS IDBCNumber,
		COALESCE(LEB.BillGenerationDate, LEB.DocReceiveDate, LEB.DateAdded) AS IDBCDate,
		ISNULL(AIT.AitAmount, 0) AS AitInlandBills,
		ISNULL(MD.LCAmount, 0) AS LCValue,
		COALESCE(MD.IssueDate, MD.DateOfLien, Advi.IssueDate) AS LCDate,
		CAST(ISNULL(LEB.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1) AS DECIMAL(18, 2)) AS BillValueEquivalentBDT,
		CAST(ISNULL(PRSM.RealizationAmount, 0) * ISNULL(CLR.ConvertFactor, 1) AS DECIMAL(18, 2)) AS RealizedValueEquivalentBDTOnRealizationDate,
		CASE 
			WHEN UPPER(CPM.CustomerName) LIKE '%LTD%' OR UPPER(CPM.CustomerName) LIKE '%LIMITED%' THEN 'LTD'
			ELSE 'Other than LTD'
		END AS CustomerTypeLTDOthethanLTD,
		CASE 
			WHEN ISNULL(PRSM.IsReversed, 0) = 1 OR ISNULL(LEB.IsAgainstCancelledBill, 0) = 1 OR ISNULL(LEB.IsCancelled, 0) = 1 THEN 'Reversed'
			ELSE 'Regular'
		END AS StatusRegularReversed,
		CAST(
			CASE 
				WHEN @USDRate > 0 
					THEN (ISNULL(LEB.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
				ELSE 0 
			END AS DECIMAL(18, 2)
		) AS BillValueEquivalentUSD,
		COALESCE(NULLIF(PRSM.Currency, ''), LEB.CURRENCY_CODE, 'USD') AS RealizationCurrency,
		CAST(ISNULL(PRSM.RealizationAmount, 0) * ISNULL(CLR.ConvertFactor, 1) AS DECIMAL(18, 2)) AS EquivalentRealizationAmountInBDT,
		CAST(
			CASE 
				WHEN @USDRate > 0 
					THEN (ISNULL(PRSM.RealizationAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
				ELSE 0 
			END AS DECIMAL(18, 2)
		) AS EquivalentRealizationAmountInUSD,
		COALESCE(NULLIF(LEB.AddedBy, ''), NULLIF(LEB.MakeBy, ''), '') AS Inputter,
		COALESCE(NULLIF(LEB.CheckBy, ''), '') AS Authorizer,
		CAST(
			CASE 
				WHEN @USDRate > 0 
					THEN (ISNULL(LEB.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
				ELSE 0 
			END AS DECIMAL(18, 2)
		) AS EquivelentBillAmountUSD,
		ISNULL(Commo.CommodityName, '') AS CommodityName,
		COALESCE(EBM.AcceptanceReceivedOnDate, LEB.DateOfBillAccepted, LEB.AcceptanceReceivedOnDate) AS AcceptanceDate,
		COALESCE(EBM.MaturityDate, LEB.MaturityDate) AS MaturityDate,
		COALESCE(NULLIF(Issue.Name, ''), NULLIF(OpenBank.Name, ''), NULLIF(LEBIssueBank.Name, ''), NULLIF(DocSendBank.Name, ''), '') AS IssuingBankName,
		COALESCE(NULLIF(IssueBranch.Name, ''), NULLIF(DocSendBranch.Name, ''), NULLIF(OpenBankBranch.Name, ''), '') AS IssuingBranch,
		COALESCE(NULLIF(IssueBranch.AgentName, ''), NULLIF(DocSendBranch.AgentName, ''), NULLIF(OpenBankBranch.AgentName, ''), NULLIF(OpenBank.AgentName, ''), '') AS IssuingBankADCode,
		COALESCE(NULLIF(LEB.TransferringBankReferenceNumber, ''), NULLIF(EBM.OtherMessageID, ''), NULLIF(LEB.CBSRefNo, ''), NULLIF(LEB.RPA_REFERENCE_NO, ''), '') AS BangladeshBankAcceptanceID,
		COALESCE(NULLIF(tenor.DisplayCode, ''), NULLIF(ten.DisplayCode, ''), '') AS LCTypeSightOrDeffered,
		COALESCE(LEB.TENOR_DAYS, MD.Tenor, 0) AS Tenor,
		COALESCE(
			NULLIF(LEB.BASE_DATE_DESC, ''), 
			FORMAT(COALESCE(LEB.BASE_DATE, Advi.DeliveryDate, EBM.AcceptanceReceivedOnDate, LEB.DateOfBillAccepted, LEB.DocReceiveDate), 'dd-MMM-yyyy'), 
			''
		) AS AcceptanceCalculationBasis,
		CASE 
			WHEN ISNULL(LEB.IsAgainstCancelledBill, 0) = 1 THEN 'Reversed'
			WHEN ISNULL(LEB.IsCancelled, 0) = 1 THEN 'Cancelled'
			WHEN ISNULL(PRSM.IsReversed, 0) = 1 THEN 'Reversed'
			WHEN Advi.LiabilityReversalDate IS NOT NULL THEN 'Reversed'
			WHEN ISNULL(EBM.IsClosedCancelWOLiq, 0) = 1 THEN 'Cancelled Without Liquidation'
			ELSE 'Regular'
		END AS ReversalStatus,
		CASE WHEN PUR.EBIID IS NOT NULL THEN 'Purchased' ELSE 'Unpurchased' END AS PurchaseStatus,
		COALESCE(NULLIF(PRSM.ExternalID, ''), NULLIF(LEB.ExternalID, ''), NULLIF(PRSM.CBSTransactionResponseRef, ''), '') AS BangladeshBankPaymentID,
		CASE WHEN PRC.ExportBillID IS NOT NULL THEN 'Issued' ELSE 'Not Issued' END AS PRCIssueStatus,
		ISNULL(PRC.PRCNo, '') AS BBPRCID,
		ISNULL(PRSM.ExchangeRate, 0) AS EchangeRateAppliedOnRealizaiton,
		ISNULL(LEB.ExportLocalBillNo, '') AS LBCNo
	FROM LocalExportBillInitiationMaster LEB WITH(NOLOCK)
		LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON 
			BPB.BranchID = LEB.BranchID
			OR BPB.BranchID = REPLACE(LEB.BranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', LEB.BranchID) > 0 
				AND CHARINDEX('/', BPB.BranchID) > 0
				AND RIGHT(LEB.BranchID, CHARINDEX('/', REVERSE(LEB.BranchID) + '/') - 1) = RIGHT(BPB.BranchID, CHARINDEX('/', REVERSE(BPB.BranchID) + '/') - 1)
			)
		LEFT JOIN SystemManager..BankProfileBranch ADbpb WITH(NOLOCK) ON 
			ADbpb.BranchID = LEB.ADBranchID
			OR ADbpb.BranchID = REPLACE(LEB.ADBranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', LEB.ADBranchID) > 0 
				AND CHARINDEX('/', ADbpb.BranchID) > 0
				AND RIGHT(LEB.ADBranchID, CHARINDEX('/', REVERSE(LEB.ADBranchID) + '/') - 1) = RIGHT(ADbpb.BranchID, CHARINDEX('/', REVERSE(ADbpb.BranchID) + '/') - 1)
			)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = LEB.CustomerCode
		LEFT JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = LEB.MasterDocID
		LEFT JOIN SystemManager..BankProfileBranch BPB_MD WITH(NOLOCK) ON 
			BPB_MD.BranchID = MD.BranchID
			OR BPB_MD.BranchID = REPLACE(MD.BranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', MD.BranchID) > 0 
				AND CHARINDEX('/', BPB_MD.BranchID) > 0
				AND RIGHT(MD.BranchID, CHARINDEX('/', REVERSE(MD.BranchID) + '/') - 1) = RIGHT(BPB_MD.BranchID, CHARINDEX('/', REVERSE(BPB_MD.BranchID) + '/') - 1)
			)
		LEFT JOIN SystemManager..BankProfileBranch ADbpb_MD WITH(NOLOCK) ON 
			ADbpb_MD.BranchID = MD.ADBranchID
			OR ADbpb_MD.BranchID = REPLACE(MD.ADBranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', MD.ADBranchID) > 0 
				AND CHARINDEX('/', ADbpb_MD.BranchID) > 0
				AND RIGHT(MD.ADBranchID, CHARINDEX('/', REVERSE(MD.ADBranchID) + '/') - 1) = RIGHT(ADbpb_MD.BranchID, CHARINDEX('/', REVERSE(ADbpb_MD.BranchID) + '/') - 1)
			)
		LEFT JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = MD.GroupSysID
		LEFT JOIN SystemManager..BankProfileBranch BPB_G WITH(NOLOCK) ON 
			BPB_G.BranchID = G.ADBranchID
			OR BPB_G.BranchID = REPLACE(G.ADBranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', G.ADBranchID) > 0 
				AND CHARINDEX('/', BPB_G.BranchID) > 0
				AND RIGHT(G.ADBranchID, CHARINDEX('/', REVERSE(G.ADBranchID) + '/') - 1) = RIGHT(BPB_G.BranchID, CHARINDEX('/', REVERSE(BPB_G.BranchID) + '/') - 1)
			)
		LEFT JOIN LCAdvisingRegister Advi WITH(NOLOCK) ON Advi.LCReceiveID = COALESCE(NULLIF(MD.LCReceiveID, ''), NULLIF(LEB.MasterDocID, ''), NULLIF(MD.MasterDocID, ''))
		LEFT JOIN SystemManager..Contacts Issue WITH(NOLOCK) ON Issue.Code = Advi.BankID
		LEFT JOIN SystemManager..Contacts IssueBranch WITH(NOLOCK) ON IssueBranch.Code = Advi.BankBranchID
		LEFT JOIN SystemManager..Contacts OpenBank WITH(NOLOCK) ON OpenBank.Code = MD.OpeningBankCode
		LEFT JOIN SystemManager..Contacts OpenBankBranch WITH(NOLOCK) ON OpenBankBranch.Code = MD.OpeningBankBranchID
		LEFT JOIN SystemManager..Contacts LEBIssueBank WITH(NOLOCK) ON LEBIssueBank.Code = LEB.IssueingBankCode
		LEFT JOIN SystemManager..Contacts DocSendBank WITH(NOLOCK) ON DocSendBank.Code = COALESCE(LEB.DocSendToBank, LEB.DocumentSendingBank)
		LEFT JOIN SystemManager..Contacts DocSendBranch WITH(NOLOCK) ON DocSendBranch.Code = LEB.DocumentSendingBranch
		LEFT JOIN ExportBillMonitoring EBM WITH(NOLOCK) ON EBM.EBIID = LEB.EBIID AND EBM.IsDeleted = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = LEB.CURRENCY_CODE AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN SystemManager..CommodityMaster Commo WITH(NOLOCK) ON Commo.CommodityMasterID = MD.Commodity
		LEFT JOIN SystemManager..EntityFixedVariables tenor WITH(NOLOCK) ON tenor.EntityID = LEB.TenorType
		LEFT JOIN SystemManager..EntityFixedVariables ten WITH(NOLOCK) ON ten.EntityID = MD.TenorType
		INNER JOIN (
			SELECT 
				M.BillRefNo, 
				MAX(M.Date) AS Date, 
				SUM(M.ProceedsRecvd) AS RealizationAmount, 
				MAX(M.Currency) AS Currency,
				MAX(M.ExchangeRate) AS ExchangeRate,
				MAX(CAST(M.IsReversedFromCBS AS INT)) AS IsReversed,
				MAX(M.ExternalID) AS ExternalID,
				MAX(M.CBSTransactionResponseRef) AS CBSTransactionResponseRef
			FROM
			(
				SELECT 
					BillRefNo, 
					Date, 
					ProceedsRecvd, 
					Currency, 
					ExchangeRate, 
					IsReversedFromCBS,
					ExternalID,
					CBSTransactionResponseRef
				FROM PRSCreationDistributionDetails WITH(NOLOCK)
				WHERE IsDeleted = 0
			) M
			GROUP BY BillRefNo
		) PRSM ON PRSM.BillRefNo = LEB.EBIID
		LEFT JOIN (
			SELECT 
				P.EBIID,
				STUFF((SELECT ', ' + CAST(CONVERT(DATE, PP.StartDate) AS VARCHAR(10))
					FROM LDBCPurchase PP WITH(NOLOCK)
					WHERE PP.IsDeleted = 0 AND PP.IsCancelled = 0 AND PP.EBIID = P.EBIID
					FOR XML PATH(''), TYPE)
				.value('.','NVARCHAR(MAX)'),1,2,' ') AS StartDate,
				STUFF((SELECT ', ' + PP.LoanNumber
					FROM LDBCPurchase PP WITH(NOLOCK)
					WHERE PP.IsDeleted = 0 AND PP.IsCancelled = 0 AND PP.EBIID = P.EBIID
					FOR XML PATH(''), TYPE)
				.value('.','NVARCHAR(MAX)'),1,2,' ') AS LoanNumber
			FROM LDBCPurchase P WITH(NOLOCK)
			WHERE P.IsDeleted = 0 AND P.IsCancelled = 0
			GROUP BY P.EBIID
		) PUR ON PUR.EBIID = LEB.EBIID
		LEFT JOIN (
			SELECT MAX(CreditDate) AS CreditDate, EBIID
			FROM (
				SELECT DISTINCT CreditDate, EBIID 
				FROM LDBCPayment P WITH(NOLOCK)
				WHERE P.IsDeleted = 0 AND IsCancelled = 0
			) A
			GROUP BY EBIID
		) PAY ON PAY.EBIID = LEB.EBIID
		LEFT JOIN (
			SELECT 
				BillRefNo, 
				SUM(DistributedValue) AS AitAmount
			FROM PRSCreationDistributionDetails WITH(NOLOCK)
			WHERE IsDeleted = 0 AND (AllocationHead LIKE '%AIT%' OR AllocationHead LIKE '%Tax%')
			GROUP BY BillRefNo
		) AIT ON AIT.BillRefNo = LEB.EBIID
		LEFT JOIN (
			SELECT 
				PID.ExportBillID, 
				MAX(PIM.PRCNo) AS PRCNo
			FROM PRCIssuanceInvoiceDetails PID WITH(NOLOCK)
			INNER JOIN PRCIssuanceMaster PIM WITH(NOLOCK) ON PIM.PRCSystemID = PID.PRCSystemID
			WHERE PID.IsDeleted = 0 AND PIM.IsDeleted = 0 AND PIM.IsCancelled = 0
			GROUP BY PID.ExportBillID
		) PRC ON PRC.ExportBillID = LEB.EBIID
	WHERE LEB.IsDeleted = 0 
		AND ISNULL(LEB.IsCancelled, 0) = 0 
		AND LEB.ExportLocalBillNo IS NOT NULL
		AND CONVERT(DATE, PRSM.Date) BETWEEN @FromDate AND @ToDate;
END
GO
