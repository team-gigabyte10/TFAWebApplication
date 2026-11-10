USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spIDBCRegisterExportOutstandingPBL]    Script Date: 11/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[spIDBCRegisterExportOutstandingPBL] 
	@FromDate DATE, 
	@ToDate DATE
AS
	-- spIDBCRegisterExportOutstandingPBL '2024-08-01','2025-03-03'
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
		CPM.CIF AS CustomerID,
		ISNULL(CPM.CustomerName, '') AS CustomerName,
		COALESCE(
			NULLIF(cus.DisplayCode, ''), 
			CASE WHEN ISNULL(CPM.IsUsed, 0) = 1 THEN 'EPZ' ELSE 'Non-EPZ' END
		) AS CustomerType,
		COALESCE(
			NULLIF(LEB.ExternalID, ''), 
			NULLIF(MD.ExternalID, ''), 
			NULLIF(LEB.REFERENCE_LC_COLL, ''), 
			NULLIF(LEB.AdditionalFilter, ''), 
			NULLIF(LEB.ExportLocalBillNo, ''), 
			''
		) AS TransactionRef,
		LEB.ExportLocalBillNo AS IDBPIDBCNo,
		LEB.BillGenerationDate AS IssueDate,
		COALESCE(
			NULLIF(Advi.LCSCTypeId, ''), 
			CASE WHEN MD.IsSC = 1 THEN 'SC' ELSE 'LC' END
		) AS LCType,
		LEB.CURRENCY_CODE AS Currency,
		ISNULL(LEB.ExportLocalBillAmount, 0) AS BillAmount,
		ISNULL(FORMAT(LEB.ExptRelsDate, 'dd/MM/yyyy'), '') AS ExpRelsDate,
		COALESCE(EBM.MaturityDate, LEB.MaturityDate) AS ActualMaturityDate,
		CASE 
			WHEN COALESCE(EBM.MaturityDate, LEB.MaturityDate) IS NOT NULL 
				THEN DATEDIFF(DAY, COALESCE(EBM.MaturityDate, LEB.MaturityDate), GETDATE())
			ELSE 0 
		END AS OverdueDays,
		MD.LCNo AS LCNumber,
		MD.IssueDate AS LCDate,
		ISNULL(MD.LCAmount, 0) AS LCValue,
		COALESCE(NULLIF(Applicant.Name, ''), NULLIF(LEBApplicant.Name, ''), '') AS BuyersName,
		COALESCE(
			NULLIF(Issue.Name, ''), 
			NULLIF(OpenBank.Name, ''), 
			NULLIF(LEBIssueBank.Name, ''), 
			NULLIF(DocSendBank.Name, ''), 
			''
		) AS IssuingBank,
		COALESCE(
			NULLIF(IssueBranch.Name, ''), 
			NULLIF(DocSendBranch.Name, ''), 
			NULLIF(OpenBankBranch.Name, ''), 
			''
		) AS IssuingBranch,
		ISNULL(G.GroupRefNo, '') AS JobNumber,
		COALESCE(
			NULLIF(LEB.DRAWING_TYPE, ''), 
			CASE 
				WHEN LEB.IsDrawingBill = 1 THEN 'Drawing' 
				WHEN NULLIF(LEB.BillNature, '') IS NOT NULL THEN LEB.BillNature
				WHEN NULLIF(LEB.ExportLocalBillType, '') IS NOT NULL THEN LEB.ExportLocalBillType
				ELSE 'Regular' 
			END, 
			''
		) AS DrawingType,
		ISNULL(FORMAT(COALESCE(EBM.AcceptanceReceivedOnDate, LEB.DateOfBillAccepted, LEB.AcceptanceReceivedOnDate), 'dd/MM/yyyy'), '') AS BanksAcceptDate,
		COALESCE(
			NULLIF(LEB.TransferringBankReferenceNumber, ''), 
			NULLIF(MD.TransferringBankReferenceNumber, ''), 
			NULLIF(EBM.OtherMessageID, ''), 
			NULLIF(LEB.CBSRefNo, ''), 
			NULLIF(LEB.RPA_REFERENCE_NO, ''), 
			NULLIF(LEB.AdditionalFilter, ''), 
			NULLIF(EBM.AdditionalFilter, ''), 
			''
		) AS BanksAcceptRef,
		CAST(ISNULL(COALESCE(NULLIF(LEB.BILL_OUTS_AMT, 0), LEB.ExportLocalBillAmount), 0) * ISNULL(CLR.ConvertFactor, 1) AS DECIMAL(18, 2)) AS OsAmtInTk,
		COALESCE(
			NULLIF(Advi.RReference, ''), 
			NULLIF(LEB.AdditionalFilter, ''), 
			NULLIF(MD.AdditionalFilter, ''), 
			''
		) AS R06Reference,
		CASE 
			WHEN @USDRate > 0 
				THEN (ISNULL(LEB.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
			ELSE 0 
		END AS EquivalentBillAmountUSD,
		ISNULL(Commo.CommodityName, '') AS CommodityName,
		ISNULL(FORMAT(COALESCE(EBM.AcceptanceReceivedOnDate, LEB.DateOfBillAccepted, LEB.AcceptanceReceivedOnDate), 'dd/MM/yyyy'), '') AS AcceptanceDate,
		ISNULL(FORMAT(COALESCE(EBM.MaturityDate, LEB.MaturityDate), 'dd/MM/yyyy'), '') AS MaturityDate,
		ISNULL(MD.LCNo, '') AS MasterLCNo,
		MD.IssueDate AS MasterLCDate, 
		ISNULL(MD.LCAmount, 0) AS MasterLCValue,
		COALESCE(
			NULLIF(IssueBranch.AgentName, ''), 
			NULLIF(DocSendBranch.AgentName, ''), 
			NULLIF(OpenBankBranch.AgentName, ''), 
			NULLIF(OpenBank.AgentName, ''), 
			''
		) AS IssuingBankADCode,
		'' AS BangladeshBankAcceptanceID,
		ISNULL(ten.DisplayCode, '') AS LCTypeSightorDeferred,
		ISNULL(MD.Tenor, 0) AS Tenor,
		ISNULL(FORMAT(COALESCE(LEB.BASE_DATE, Advi.DeliveryDate, EBM.AcceptanceReceivedOnDate, LEB.DateOfBillAccepted, LEB.DocReceiveDate), 'dd-MMM-yyyy'), '') AS AcceptanceCalculationBasisDate,
		CASE 
			WHEN ISNULL(LEB.IsAgainstCancelledBill, 0) = 1 THEN 'Reversed'
			WHEN ISNULL(LEB.IsCancelled, 0) = 1 THEN 'Cancelled'
			WHEN Advi.LiabilityReversalDate IS NOT NULL THEN 'Reversed'
			WHEN ISNULL(EBM.IsClosedCancelWOLiq, 0) = 1 THEN 'Cancelled Without Liquidation'
			ELSE 'Regular'
		END AS ReversalStatus,
		CASE WHEN PUR.EBIID IS NOT NULL THEN 'Purchased' ELSE '' END AS PurchaseStatus,
		ISNULL(PUR.LoanNumber, '') AS LoanIDLDNumber,
		COALESCE(
			NULLIF(LEB.AddedBy, ''), 
			NULLIF(PUR.AddedBy, ''), 
			NULLIF(LEB.MakeBy, ''), 
			NULLIF(EBM.AddedBy, ''), 
			NULLIF(MD.AddedBy, ''), 
			''
		) AS Inputter,
		COALESCE(
			NULLIF(LEB.CheckBy, ''), 
			NULLIF(PUR.CheckBy, ''), 
			NULLIF(EBM.CheckBy, ''), 
			NULLIF(MD.CheckBy, ''), 
			NULLIF(Advi.CheckBy, ''), 
			NULLIF(LEB.ExceptionApprovedBy, ''), 
			NULLIF(LEB.UpdatedBy, ''), 
			''
		) AS Authorizer
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
		LEFT JOIN SystemManager..EntityFixedVariables cus WITH(NOLOCK) ON cus.EntityID = Advi.CustomerType
		LEFT JOIN SystemManager..EntityFixedVariables ten WITH(NOLOCK) ON ten.EntityID = MD.TenorType
		LEFT JOIN SystemManager..Contacts Issue WITH(NOLOCK) ON Issue.Code = Advi.BankID
		LEFT JOIN SystemManager..Contacts IssueBranch WITH(NOLOCK) ON IssueBranch.Code = Advi.BankBranchID
		LEFT JOIN SystemManager..Contacts OpenBank WITH(NOLOCK) ON OpenBank.Code = MD.OpeningBankCode
		LEFT JOIN SystemManager..Contacts OpenBankBranch WITH(NOLOCK) ON OpenBankBranch.Code = MD.OpeningBankBranchID
		LEFT JOIN SystemManager..Contacts LEBIssueBank WITH(NOLOCK) ON LEBIssueBank.Code = LEB.IssueingBankCode
		LEFT JOIN SystemManager..Contacts DocSendBank WITH(NOLOCK) ON DocSendBank.Code = COALESCE(LEB.DocSendToBank, LEB.DocumentSendingBank)
		LEFT JOIN SystemManager..Contacts DocSendBranch WITH(NOLOCK) ON DocSendBranch.Code = LEB.DocumentSendingBranch
		LEFT JOIN SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = MD.Applicant
		LEFT JOIN SystemManager..Contacts LEBApplicant WITH(NOLOCK) ON LEBApplicant.Code = LEB.ApplicantID
		LEFT JOIN ExportBillMonitoring EBM WITH(NOLOCK) ON EBM.EBIID = LEB.EBIID AND EBM.IsDeleted = 0
		LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = LEB.CURRENCY_CODE AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN SystemManager..CommodityMaster Commo WITH(NOLOCK) ON Commo.CommodityMasterID = MD.Commodity
		LEFT JOIN SystemManager..EntityFixedVariables tenor WITH(NOLOCK) ON tenor.EntityID = LEB.TenorType
		LEFT JOIN (
			SELECT M.BillRefNo, MAX(M.Date) Date, SUM(M.ProceedsRecvd) RealizationAmount, MAX(Currency) Currency
			FROM
			(
				SELECT BillRefNo, MAX(Date) Date, MAX(ProceedsRecvd) ProceedsRecvd, MAX(Currency) Currency
				FROM PRSCreationDistributionDetails WITH(NOLOCK)
				WHERE IsDeleted = 0
				GROUP BY BillRefNo
			) M
			GROUP BY BillRefNo
		) PRSM ON PRSM.BillRefNo = LEB.EBIID
		LEFT JOIN (
			SELECT P.EBIID,
				STUFF((SELECT ', ' + CAST(CONVERT(DATE, PP.StartDate) AS VARCHAR(10))
					FROM LDBCPurchase PP WITH(NOLOCK)
					WHERE PP.IsDeleted = 0 AND PP.IsCancelled = 0 AND PP.EBIID = P.EBIID
					FOR XML PATH(''), TYPE)
				.value('.','NVARCHAR(MAX)'),1,2,' ') StartDate,
				STUFF((SELECT ', ' + PP.LoanNumber
					FROM LDBCPurchase PP WITH(NOLOCK)
					WHERE PP.IsDeleted = 0 AND PP.IsCancelled = 0 AND PP.EBIID = P.EBIID
					FOR XML PATH(''), TYPE)
				.value('.','NVARCHAR(MAX)'),1,2,' ') LoanNumber,
				MAX(P.AddedBy) AS AddedBy,
				MAX(P.CheckBy) AS CheckBy
			FROM LDBCPurchase P WITH(NOLOCK)
			WHERE P.IsDeleted = 0 AND P.IsCancelled = 0
			GROUP BY P.EBIID
		) PUR ON PUR.EBIID = LEB.EBIID
		LEFT JOIN (
			SELECT MAX(CreditDate) CreditDate, EBIID
			FROM (
				SELECT DISTINCT CreditDate, EBIID 
				FROM LDBCPayment P WITH(NOLOCK)
				WHERE P.IsDeleted = 0 AND IsCancelled = 0
			) A
			GROUP BY EBIID
		) PAY ON PAY.EBIID = LEB.EBIID
	WHERE LEB.IsDeleted = 0 
		AND ISNULL(LEB.IsCancelled, 0) = 0 
		AND LEB.ExportLocalBillNo IS NOT NULL 
		AND PRSM.BillRefNo IS NULL
		AND CONVERT(DATE, COALESCE(LEB.BillGenerationDate, LEB.DocReceiveDate, LEB.DateAdded)) BETWEEN @FromDate AND @ToDate;
END
GO
