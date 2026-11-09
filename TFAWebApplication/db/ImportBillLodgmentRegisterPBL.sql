USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_ImportBillLodgmentRegisterPBL] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[SP_RPT_ImportBillLodgmentRegisterPBL]
	@FromDate DATETIME, 
	@ToDate DATETIME
AS					
	-- EXEC SP_RPT_ImportBillLodgmentRegisterPBL '2023-01-01', '2026-12-31'
BEGIN
	SET NOCOUNT ON;

	SELECT DISTINCT
		UserID = FDAM.AddedBy + ', ' + ISNULL(FDAM.UpdatedBy, '') + ', ' + ISNULL(CASE WHEN FDAM.UBSSyncProcessID > 0 THEN ISNULL(FDAM.UpdatedBy, '') ELSE '' END, '') + ', ' + ISNULL(CASE WHEN ImportBillPayment.FDAID IS NOT NULL THEN ISNULL(ImportBillPayment.AddedBy, '') ELSE '' END, ''),
		LastAPIName = (CASE WHEN ImportBillPayment.FDAID IS NOT NULL AND FDAM.UBSSyncProcessID > 0 THEN 'Payment' 
			WHEN ImportBillPayment.FDAID IS NULL AND FDAM.UBSSyncProcessID > 0 THEN 'Lodgement' 
			ELSE NULL END),
		LastSyncDate = (CASE WHEN ImportBillPayment.FDAID IS NOT NULL AND FDAM.UBSSyncProcessID > 0 THEN ImportBillPayment.UBSSyncTime 
			WHEN ImportBillPayment.FDAID IS NULL AND FDAM.UBSSyncProcessID > 0 THEN FDAM.UBSSyncTime 
			ELSE NULL END),
		CBSContRef = FDAM.ReferenceNo,
		DocReceiveDate = FDAM.DocReceiveDate,
		CustomerName = CPM.CustomerName,
		ADBranch = COALESCE(
			ADBPB.BranchName,
			CASE WHEN BPB_FDAM.IsADCode = 1 THEN BPB_FDAM.BranchName ELSE BPB_FDAM_AD.BranchName END
		),
		NonADBranch = CASE 
			WHEN NonADBPB.BranchName IS NOT NULL 
			     AND RTRIM(LTRIM(NonADBPB.BranchName)) != RTRIM(LTRIM(COALESCE(ADBPB.BranchName, CASE WHEN BPB_FDAM.IsADCode = 1 THEN BPB_FDAM.BranchName ELSE BPB_FDAM_AD.BranchName END, '')))
			THEN NonADBPB.BranchName
			WHEN BPB_FDAM.IsADCode = 0 
			     AND RTRIM(LTRIM(BPB_FDAM.BranchName)) != RTRIM(LTRIM(COALESCE(ADBPB.BranchName, BPB_FDAM_AD.BranchName, '')))
			THEN BPB_FDAM.BranchName
			ELSE ''
		END,
		LCode = BBLCM.LCode,
		LCNo = BBLCM.LCNo,
		LCType = ISNULL(BBLCM.LCType, CASE WHEN FDAM.IsImportLC = 1 THEN 'ImportLC' ELSE 'BBLC' END),
		CommodityName = COALESCE(FDAM.CommodityName, CM.CommodityName, BBLCM.Commodity),
		SupplierName = ISNULL(Ben.Name, BBLCM.Benificiary),
		Currency = ISNULL(BBLCM.Currency, FDAM.Currency),
		LCAmount = ISNULL(BBLCM.LCAmount, FDAM.LCAmount),
		BillNo = FDAM.BillNo,
		BillsAlreadyReceived = BillRec.BillsAlreadyReceived,
		BalanceReceive = (ISNULL(ISNULL(BBLCM.LCAmount, FDAM.LCAmount), 0) + ISNULL(ISNULL(BBLCM.LCAmount, FDAM.LCAmount) * (ISNULL(BBLCM.Toleranace, 0) / 100), 0) - ISNULL(BillRec.BillsAlreadyReceived, 0)),
		OutstandingSGAmount = SGOut.SGAmount,
		AcceptanceDate = FDAM.AcceptanceDate,
		AcceptanceIDNo = FDAM.AcceptanceIDNo,
		MATURITY_DATE = FDAM.MATURITY_DATE,
		BillAmount = FDAM.BillAmount,
		ConvertFactor = CLR.ConvertFactor,
		BillAmountBDT = FDAM.BillAmount * ISNULL(CLR.ConvertFactor, 1),
		DocumentStatus = ISNULL(Accept.DisplayCode, FDAM.DocumentStatus),
		ScrutinyReceivedDate = FDAM.ScrutinyReceivedDate,
		LodgmentDate = FDAM.LodgmentDate,
		Aging = CASE WHEN FDAM.AcceptanceDate IS NULL AND FDAM.RemittedAmount = 0 AND Accept.DisplayCode != 'DISCREPANT' AND ImportBillPayment.VALUE_DATE IS NULL THEN DATEDIFF(DAY, FDAM.DocReceiveDate, GETDATE()) ELSE NULL END,
		RemittedAmount = FDAM.RemittedAmount,
		VALUE_DATE = ImportBillPayment.VALUE_DATE,
		AccountName = RemiNostroAcc.AccountName,
		GroupLCNo = LCG.GroupLCNo,
		NegotiatingBankName = NegoBank.Name,
		NegotiatingBankBranchName = NegoBankBranch.Name,
		NegoBankCountry = NegoCountry.CountryName,
		NegoBankBillRef = FDAM.NegoBankBillRef,
		InvoiceNumber = Invoice.InvoiceNo,
		InvoiceDate = Invoice.InvoiceDate,
		InvoiceAmount = Invoice.InvoiceAmount,
		ShipMode = Invoice.ShipMode,
		TransportDocNumber = Invoice.BillOrChalanTypeNo,
		TransportDocDate = Invoice.BillOrChalanDate,
		SGRefNumber = SG.SGRefNo,
		SGDate = SG.SGIssueDate,
		SGAmount = SG.Amount,
		LattestLoanNumber = (SELECT TOP 1 ExternalID FROM LoanCreation with (nolock) WHERE AdditionalFilter = FDAM.BillNo ORDER BY DateAdded DESC),
		LoanAmount = (SELECT TOP 1 LoanAmount FROM LoanCreation with (nolock) WHERE AdditionalFilter = FDAM.BillNo ORDER BY DateAdded DESC),
		LoanOutstanding = (SELECT TOP 1 OutstandingAmount FROM LoanCreation with (nolock) WHERE AdditionalFilter = FDAM.BillNo ORDER BY DateAdded DESC),
		SettlementDate = (SELECT TOP 1 AdjustedDate FROM LoanCreation with (nolock) WHERE AdditionalFilter = FDAM.BillNo ORDER BY DateAdded DESC),
		Remarks = FDAM.Remarks,
		CustomerID = FDAM.CustomerID,
		ADBranchID = COALESCE(BBLCM.ADBranchID, CASE WHEN BPB_FDAM.IsADCode = 1 THEN FDAM.BranchID ELSE BPB_FDAM.ADBranchID END),
		BranchID = FDAM.BranchID,
		BillType = CASE WHEN FDAM.IsCancelled = 0 THEN 'Live Bill' ELSE 'Delete Bill' END,
		FDAID = FDAM.FDAID,
		FromAcceptanceDate = CONVERT(DATE, FDAM.AcceptanceDate),
		ToAcceptanceDate = CONVERT(DATE, FDAM.AcceptanceDate),
		FromMATURITY_DATE = CONVERT(DATE, FDAM.MATURITY_DATE),
		ToMATURITY_DATE = CONVERT(DATE, FDAM.MATURITY_DATE),
		FromVALUE_DATE = CONVERT(DATE, ImportBillPayment.VALUE_DATE),
		ToVALUE_DATE = CONVERT(DATE, ImportBillPayment.VALUE_DATE)
	FROM ForeignDocumentAcceptanceMaster FDAM with (nolock)
		LEFT JOIN (
				SELECT 
					M.BBLCNo AS LCNo, 
					M.BBLCID, 
					M.Product, 
					M.BBLCAmount AS LCAmount, 
					M.Toleranace, 
					M.LCode, 
					M.Benificiary, 
					M.AdvisingBankCode, 
					'BBLC' AS LCType, 
					M.Currency, 
					M.GroupSysID, 
					COALESCE(G.ADBranchID, R.ADBranchID) AS ADBranchID,
					COALESCE(G.BankBranchID, R.BranchID) AS NonADBranchID,
					M.Commodity
				FROM BBLCMaster M with (nolock)
					LEFT JOIN GroupLC G with (nolock) ON G.GroupSysID = M.GroupSysID
					LEFT JOIN BBLCRequestMaster R with (nolock) ON R.BBLCID = M.BBLCID AND R.IsDeleted = 0 AND R.IsCancelled = 0
				WHERE M.IsDeleted = 0 AND M.IsCancelled = 0

				UNION ALL

				SELECT 
					M.ImportLCNo AS LCNo, 
					M.ImportLCID AS BBLCID, 
					M.Product, 
					M.ImportLCAmount AS LCAmount, 
					M.Toleranace, 
					M.LCode, 
					M.Benificiary, 
					M.AdvisingBankCode, 
					'ImportLC' AS LCType, 
					M.Currency, 
					'' AS GroupSysID, 
					COALESCE(R.ADBranchID, CASE WHEN BPB_M.IsADCode = 1 THEN M.BranchID ELSE BPB_M.ADBranchID END) AS ADBranchID,
					COALESCE(R.BranchID, CASE WHEN BPB_M.IsADCode = 0 THEN M.BranchID ELSE NULL END) AS NonADBranchID,
					M.Commodity
				FROM ImportLCMaster M with (nolock)
					LEFT JOIN BBLCRequestMaster R with (nolock) ON R.BBLCID = M.ImportLCID AND R.IsDeleted = 0 AND R.IsCancelled = 0
					LEFT JOIN SystemManager..BankProfileBranch BPB_M with (nolock) ON BPB_M.BranchID = M.BranchID
				WHERE M.IsDeleted = 0 
		) BBLCM ON BBLCM.BBLCID = FDAM.BBLCID
		LEFT JOIN SystemManager..Contacts Ben with (nolock) ON Ben.Code = BBLCM.Benificiary OR Ben.Name = BBLCM.Benificiary
		LEFT JOIN (
				SELECT SUM(ISNULL(BillAmount, 0)) BillsAlreadyReceived, BBLCID 
				FROM ForeignDocumentAcceptanceMaster with (nolock)
				WHERE IsDeleted = 0 AND IsCancelled = 0
				GROUP BY BBLCID
		) BillRec ON BillRec.BBLCID = FDAM.BBLCID
		LEFT JOIN SystemManager..CommodityMaster CM with (nolock) ON CM.CommodityMasterID = FDAM.Commodity 
		LEFT JOIN SystemManager..CustomerProfileMaster CPM with (nolock) ON FDAM.CustomerID = CPM.CustomerID
		LEFT JOIN SystemManager..Contacts NegoBank with (nolock) ON NegoBank.Code = FDAM.NegotiatingBank
		LEFT JOIN SystemManager..Country NegoCountry with (nolock) ON NegoCountry.CountryID = NegoBank.CountryID
		LEFT JOIN SystemManager..BankProfileNostroAccounts RemiNostroAcc with (nolock) ON RemiNostroAcc.BPNACID = FDAM.RemittedThrough
		LEFT JOIN SystemManager..BankProfileBranch ADBPB with (nolock) ON ADBPB.BranchID = BBLCM.ADBranchID
		LEFT JOIN SystemManager..BankProfileBranch NonADBPB with (nolock) ON NonADBPB.BranchID = BBLCM.NonADBranchID
		LEFT JOIN SystemManager..BankProfileBranch BPB_FDAM with (nolock) ON BPB_FDAM.BranchID = FDAM.BranchID
		LEFT JOIN SystemManager..BankProfileBranch BPB_FDAM_AD with (nolock) ON BPB_FDAM_AD.BranchID = BPB_FDAM.ADBranchID
		LEFT JOIN SystemManager..EntityFixedVariables Accept with (nolock) ON Accept.EntityID = FDAM.AcceptanceStatus
		LEFT JOIN SystemManager..Contacts NegoBankBranch with (nolock) ON NegoBankBranch.Code = FDAM.NegotiatingBankBranchId
		LEFT JOIN SystemManager..CurrencyLatestRate CLR with (nolock) ON CLR.CurrencyCode = ISNULL(BBLCM.Currency, FDAM.Currency) AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN (
		    SELECT M.FDAID, MAX(M.VALUE_DATE) VALUE_DATE, SUM(M.PaymentAmount) PaymentAmount, MAX(AddedBy) AddedBy, MAX(UBSSyncTime) UBSSyncTime
            FROM
            (
	            SELECT P.FDAID, MAX(P.VALUE_DATE) VALUE_DATE, MAX(P.PaymentAmount) PaymentAmount, MAX(AddedBy) AddedBy, MAX(UBSSyncTime) UBSSyncTime
	            FROM ForeignDocumentPaymentMaster P with (nolock)
	            WHERE P.IsDeleted = 0 AND ISNULL(P.PaymentAmount, 0) > 0
	            GROUP BY P.FDAID, P.VALUE_DATE
            ) M
            GROUP BY M.FDAID
	    ) ImportBillPayment ON ImportBillPayment.FDAID = FDAM.FDAID
		LEFT JOIN (
			SELECT 
				E.GroupSysID,
				STUFF((SELECT DISTINCT ', ' +  CombinedE.LCNo
				FROM MasterDoc CombinedE with(nolock)
				WHERE CombinedE.GroupSysID = E.GroupSysID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS GroupLCNo
			FROM MasterDoc E with (nolock)
			WHERE E.IsDeleted = 0 AND E.IsCancelled = 0
			GROUP BY E.GroupSysID
		) LCG ON LCG.GroupSysID = BBLCM.GroupSysID
		LEFT JOIN (
			SELECT 
				E.FDAID,
				STUFF((SELECT DISTINCT ', ' +  CombinedE.InvoiceNo
				FROM ForeignDocumentShippingGuaranteeInvoiceInfo CombinedE with(nolock)
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS InvoiceNo,
				STUFF((SELECT DISTINCT ', ' + CAST(FORMAT(CombinedE.InvoiceDate,'dd-MMM-yy') AS VARCHAR(11))
				FROM ForeignDocumentShippingGuaranteeInvoiceInfo CombinedE with(nolock)
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS InvoiceDate,
				STUFF((SELECT DISTINCT ', ' +  CAST(CombinedE.InvoiceAmount AS VARCHAR(21))
				FROM ForeignDocumentShippingGuaranteeInvoiceInfo CombinedE with(nolock)
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS InvoiceAmount,
				STUFF((SELECT DISTINCT ', ' +  EE.DisplayCode
				FROM ForeignDocumentShippingGuaranteeInvoiceInfo CombinedE with(nolock)
					LEFT JOIN SystemManager..EntityFixedVariables EE with (nolock) ON EE.EntityID = CombinedE.ShipModeID
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS ShipMode,
				STUFF((SELECT DISTINCT ', ' +  CombinedE.BillOrChalanTypeNo
				FROM ForeignDocumentShippingGuaranteeInvoiceInfo CombinedE with(nolock)
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS BillOrChalanTypeNo,
				STUFF((SELECT DISTINCT ', ' + CAST(FORMAT(CombinedE.BillOrChalanDate,'dd-MMM-yy') AS VARCHAR(11))
				FROM ForeignDocumentShippingGuaranteeInvoiceInfo CombinedE with(nolock)
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS BillOrChalanDate
			FROM ForeignDocumentShippingGuaranteeInvoiceInfo E with (nolock)
			WHERE E.IsDeleted = 0 AND E.IsCancelled = 0
			GROUP BY E.FDAID
		) Invoice ON Invoice.FDAID = FDAM.FDAID
		LEFT JOIN (
			SELECT 
				E.FDAID,
				STUFF((SELECT DISTINCT ', ' +  EE.SGRefNo
				FROM ForeignDocumentShippingGuaranteeMap CombinedE with(nolock)
					LEFT JOIN ShippingGuaranteeMaster EE with (nolock) ON EE.SGMID = CombinedE.SGMID
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS SGRefNo,
				STUFF((SELECT DISTINCT ', ' +  CAST(FORMAT(EE.SGIssueDate,'dd-MMM-yy') AS VARCHAR(11))
				FROM ForeignDocumentShippingGuaranteeMap CombinedE with(nolock)
					LEFT JOIN ShippingGuaranteeMaster EE with (nolock) ON EE.SGMID = CombinedE.SGMID
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS SGIssueDate,
				STUFF((SELECT DISTINCT ', ' +  CAST(EE.Amount AS VARCHAR(21))
				FROM ForeignDocumentShippingGuaranteeMap CombinedE with(nolock)
					LEFT JOIN ShippingGuaranteeMaster EE with (nolock) ON EE.SGMID = CombinedE.SGMID
				WHERE CombinedE.FDAID = E.FDAID AND CombinedE.IsDeleted = 0 AND CombinedE.IsCancelled = 0
				FOR XML PATH('')),1,1,'') AS Amount
			FROM ForeignDocumentShippingGuaranteeMap E with (nolock)
			WHERE E.IsDeleted = 0 AND E.IsCancelled = 0
			GROUP BY E.FDAID
		) SG ON SG.FDAID = FDAM.FDAID
		LEFT JOIN (
			SELECT SGM.ImportOrBBLCID, SUM(SGM.Amount) SGAmount
            FROM ShippingGuaranteeMaster SGM with (nolock)
	            LEFT JOIN ForeignDocumentShippingGuaranteeMap MAP with (nolock) ON MAP.SGMID = SGM.SGMID AND MAP.IsCancelled = 0 AND MAP.IsDeleted = 0
            WHERE SGM.IsDeleted = 0 AND SGM.IsCancelled = 0 AND MAP.SGMID IS NULL
			GROUP BY SGM.ImportOrBBLCID
		) SGOut ON SGOut.ImportOrBBLCID = BBLCM.BBLCID
	WHERE FDAM.IsDeleted = 0
		AND CONVERT(DATE, FDAM.DocReceiveDate) BETWEEN @FromDate AND @ToDate 
	ORDER BY FDAM.DocReceiveDate
END
GO

