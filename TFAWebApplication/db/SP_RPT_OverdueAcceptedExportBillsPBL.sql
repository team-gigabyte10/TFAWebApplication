USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_OverdueAcceptedExportBillsPBL]    Script Date: 11/23/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_OverdueAcceptedExportBillsPBL]
@FromDate DATETIME, @ToDate DATETIME
AS				-- SP_RPT_OverdueAcceptedExportBillsPBL '20-Sep-2022','30-Sep-2022'
BEGIN
	SET NOCOUNT ON;

SELECT * FROM (
SELECT * FROM (
	SELECT
		EBM.BillGenerationDate AS LodgementDate,
		EBM.ExportBillNo AS FDBCNumber,
		ISNULL(CPM.CustomerName, EBM.CustomerCode) AS ClientsName,
		COALESCE(
			NULLIF(ADbpb.BranchName, ''), 
			CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END,
			''
		) AS ADBranch,
		CASE 
			WHEN NonADbpb.BranchName IS NOT NULL 
				 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
			THEN NonADbpb.BranchName
			WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
				 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
			THEN BPB.BranchName
			ELSE ''
		END AS NonAdBranch,
		EPZNonEPZ = CASE WHEN CPM.IsUsed = 1 THEN 'EPZ' ELSE 'Non-EPZ' END,
		EBM.CURRENCY_CODE AS BillCurrency,
		EBM.ExportBillAmount AS BillAmount,
		CASE 
			WHEN EBM.TenorType = 'Deferred' THEN CONCAT(CAST(EBM.TENOR_DAYS AS VARCHAR(10)), ' Days ', TenorDescription.DisplayCode)
			ELSE tenor.DisplayCode
		END PaymentTerm,
		CASE WHEN MD.IsSC = 1 THEN 'SC' ELSE 'LC' END AS InstrumentType,
		MD.LCNo AS LCSCNumber,
		DocSendBank.Name + ', ' + ISNULL(DocSendBankBranch.Name, '') AS LCIssuingBankCollectingBank,
		'' AS DocumentsReceivingBank,
		'' AS DocumentsReceivingCountry,
		purchase.DateAdded AS PurchaseDate,
		purchase.DisbursedAmount AS PurchaseAmountFCY,
		EM.MailSentToFFDateDate AS DocumentsForwardingDate,
		DATEDIFF(DAY, EBM.DocReceiveDate, GETDATE()) AS TotalUnrespondedDays,
		CourierCompany.CourierCompany AS CouriersName,
		CourierReceipt.CourierReceipt AS CourierReciptNumber,
		EBM.EBIID AS EBIID,
		EBM.CustomerCode AS CustomerID,
		COALESCE(
			NULLIF(ADbpb.BranchID, ''), 
			CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END,
			''
		) AS ADBranchID,
		CASE 
			WHEN NonADbpb.BranchName IS NOT NULL 
				 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
			THEN ISNULL(NonADbpb.BranchID, '')
			WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
				 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
			THEN ISNULL(BPB.BranchID, '')
			ELSE ''
		END AS NonADBranchID,
		CASE WHEN ISNULL(CPM.IsUsed, 0) = 1 THEN 'EPZ' ELSE 'Non-EPZ' END AS EpzId,
		EBM.TenorType AS TenorType,
		EBM.MasterDocID AS MasterDocID,
		EM.MaturityDate AS MaturityDate,
		PartialPaymentReceived = (SELECT TOP 1 P.C_Amount
			FROM PRSCreationMaster P WITH(NOLOCK)
				LEFT JOIN (
					SELECT EBIID, MasterDocID, ExportBillAmount, CURRENCY_CODE, ExportBillNo, ExportBillAmount TempBillAmount, 'Export' BillType 
					FROM ExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND IsARVAdjusted = 0 AND ExportBillNo IS NOT NULL
					UNION
					SELECT EBIID, MasterDocID, ExportLocalBillAmount, CURRENCY_CODE, ExportLocalBillNo, ExportLocalBillAmount TempBillAmount, 'Local' BillType 
					FROM LocalExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
					UNION
					SELECT EBIID, EBIM.MasterDocID, (EBIM.ExportBillAmount - ISNULL(ARV.ARVAdjustmentAmount, 0)) ExportBillAmount, EBIM.CURRENCY_CODE, EBIM.ExportBillNo, EBIM.ExportBillAmount TempBillAmount, 'Export' BillType 
					FROM ExportBillInitiationMaster EBIM WITH(NOLOCK)   
						INNER JOIN (
							SELECT EBIIRMTD, SUM(AdjustmentAmount + ForeignBankCharge + ForeignCommission + DiscountAmount) ARVAdjustmentAmount
							FROM ExportBillAgainstRMTAdjustmentDetails WITH(NOLOCK)
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0
							GROUP BY EBIIRMTD
						) ARV ON ARV.EBIIRMTD = EBIM.EBIID
					WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND EBIM.ExportBillNo IS NOT NULL  
						AND EBIM.IsARVAdjusted = 1 AND (EBIM.ExportBillAmount - ISNULL(ARV.ARVAdjustmentAmount, 0)) != 0.00
				) E ON E.EBIID = ISNULL(P.EBIID, '')
			WHERE P.IsDeleted = 0 AND P.EBIID = EBM.EBIID AND CAST((P.ShortAmount / CASE WHEN P.PaymentType = 'ARV' THEN P.C_Amount ELSE E.ExportBillAmount END) * 100 AS DECIMAL(18, 2)) > 5
			ORDER BY P.DateAdded DESC),
		COALESCE(NULLIF(BPB.BranchName, ''), NULLIF(ADbpb.BranchName, ''), NULLIF(NonADbpb.BranchName, ''), '') AS BranchName

		FROM (SELECT * FROM ExportBillInitiationMaster WITH(NOLOCK) WHERE ExportBillNo IS NOT NULL AND IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0) EBM
		INNER JOIN (SELECT * FROM MasterDoc WITH(NOLOCK) WHERE IsDeleted = 0 AND IsCancelled = 0) MD ON MD.MasterDocID = EBM.MasterDocID
		LEFT JOIN ExportBillMonitoring EM WITH(NOLOCK) ON EM.EBIID = EBM.EBIID AND EM.IsDeleted = 0
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = EBM.CustomerCode
		LEFT JOIN (
			SELECT EBIID, MAX(CURRENCY) CURRENCY, SUM(DisbursedAmount) DisbursedAmount, MAX(DateAdded) DateAdded
			FROM PurchaseDiscountForeignDocumentMaster WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsExportLoan = 0
			GROUP BY EBIID
		) purchase ON purchase.EBIID = EBM.EBIID
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD.GroupSysID
		LEFT JOIN LCAdvisingRegister LCAR WITH(NOLOCK) ON LCAR.LCReceiveID = MD.LCReceiveID AND LCAR.IsDeleted = 0
		LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON 
			BPB.BranchID = EBM.BranchID
			OR BPB.BranchID = REPLACE(EBM.BranchID, 'BPB/22/', 'OBPB/25/')
		LEFT JOIN SystemManager..BankProfileBranch ADbpb WITH(NOLOCK) ON 
			ADbpb.BranchID = COALESCE(
				NULLIF(MD.ADBranchID, ''), 
				NULLIF(GLC.ADBranchID, ''), 
				NULLIF(LCAR.ADBranchID, ''), 
				CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END
			)
			OR ADbpb.BranchID = REPLACE(COALESCE(NULLIF(MD.ADBranchID, ''), NULLIF(GLC.ADBranchID, ''), NULLIF(LCAR.ADBranchID, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END), 'BPB/22/', 'OBPB/25/')
		LEFT JOIN SystemManager..BankProfileBranch NonADbpb WITH(NOLOCK) ON 
			NonADbpb.BranchID = COALESCE(NULLIF(EBM.BranchID, ''), NULLIF(MD.BranchID, ''), NULLIF(LCAR.BranchID, ''), NULLIF(GLC.BankBranchID, ''))
			OR NonADbpb.BranchID = REPLACE(COALESCE(NULLIF(EBM.BranchID, ''), NULLIF(MD.BranchID, ''), NULLIF(LCAR.BranchID, ''), NULLIF(GLC.BankBranchID, '')), 'BPB/22/', 'OBPB/25/')
		LEFT JOIN SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = MD.Applicant
		LEFT JOIN SystemManager..Contacts issuingBank WITH(NOLOCK) ON issuingBank.Code = MD.OpeningBankCode
		LEFT JOIN SystemManager..Contacts DocSendBank WITH(NOLOCK) ON DocSendBank.Code = EBM.DocSendToBank
		LEFT JOIN SystemManager..Contacts DocSendBankBranch WITH(NOLOCK) ON DocSendBankBranch.Code = EBM.DocumentSendingBranch
		LEFT JOIN SystemManager..EntityFixedVariables tenor WITH(NOLOCK) ON tenor.EntityID = EBM.TenorType
		LEFT JOIN (SELECT EntityID, DisplayCode FROM SystemManager..EntityFixedVariables WITH(NOLOCK) WHERE EntityTypeID = 'TenorDescription') TenorDescription ON TenorDescription.EntityID = EBM.TenorDescription
	    LEFT JOIN (SELECT MasterId EBIID,
							STUFF((SELECT DISTINCT ', ' + CourierReceipt
										FROM CourierInfo CombinedE WITH(NOLOCK)
										WHERE CombinedE.MasterId = E.MasterId
										FOR XML PATH('')), 1, 1, '') AS CourierReceipt
					FROM CourierInfo E WITH(NOLOCK) GROUP BY MasterId) CourierReceipt ON CourierReceipt.EBIID = EBM.EBIID
		LEFT JOIN (SELECT MasterId EBIID,
							STUFF((SELECT DISTINCT ', ' + Name
										FROM (SELECT A.Name, MasterId FROM CourierInfo B WITH(NOLOCK)
										LEFT JOIN SystemManager..Contacts A WITH(NOLOCK) ON A.CODE = B.CourierCompany) CombinedE  
										WHERE CombinedE.MasterId = E.MasterId
										FOR XML PATH('')), 1, 1, '') AS CourierCompany
					FROM (SELECT A.Name, MasterId FROM CourierInfo B WITH(NOLOCK)
						  LEFT JOIN SystemManager..Contacts A WITH(NOLOCK) ON A.CODE = B.CourierCompany) E  
						  GROUP BY MasterId) CourierCompany ON CourierCompany.EBIID = EBM.EBIID
		LEFT JOIN (
			SELECT P.EBIID, SUM(C_Amount) + ISNULL(SUM(FCC.ChargeAmount), 0) RealizedValue, MAX(P.PRSDate) Date
			FROM PRSCreationMaster P WITH(NOLOCK)
				LEFT JOIN (
					SELECT C.PRSSysID, SUM(C.ChargeAmount) ChargeAmount
					FROM PRSCreationForeignCharges C WITH(NOLOCK)
					WHERE C.IsDeleted = 0
					GROUP BY C.PRSSysID
				) FCC ON FCC.PRSSysID = P.PRSSysID
			WHERE P.IsDeleted = 0
			GROUP BY P.EBIID
		) PRSM ON PRSM.EBIID = EBM.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate RealizedCCY WITH(NOLOCK) ON RealizedCCY.CurrencyCode = ISNULL(EBM.CURRENCY_CODE, '') AND RealizedCCY.RateFor = 'BC SELLING'
		WHERE CONVERT(DATE, EBM.BillGenerationDate) BETWEEN @FromDate AND @ToDate
		 AND EM.MaturityDate IS NOT NULL AND DATEDIFF(DAY, EM.MaturityDate, GETDATE()) > 0	
		 AND (ISNULL(PRSM.RealizedValue, 0) / EBM.ExportBillAmount) * 100 < 95
		) A

		GROUP BY
		LodgementDate,FDBCNumber,ClientsName,ADBranch,NonAdBranch,EPZNonEPZ,BillCurrency,BillAmount,PaymentTerm,InstrumentType,LCSCNumber,LCIssuingBankCollectingBank,DocumentsReceivingBank,DocumentsReceivingCountry,PurchaseDate,PurchaseAmountFCY,DocumentsForwardingDate,TotalUnrespondedDays,CouriersName,CourierReciptNumber
		,EBIID,CustomerID,ADBranchID,NonADBranchID,EpzId,TenorType,MasterDocID,MaturityDate,PartialPaymentReceived,BranchName

		UNION ALL
SELECT * FROM (
		SELECT
		EBM.BillGenerationDate AS LodgementDate,
		EBM.ExportBillNo AS FDBCNumber,
		ISNULL(CPM.CustomerName, EBM.CustomerCode) AS ClientsName,
		COALESCE(
			NULLIF(ADbpb.BranchName, ''), 
			CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END,
			''
		) AS ADBranch,
		CASE 
			WHEN NonADbpb.BranchName IS NOT NULL 
				 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
			THEN NonADbpb.BranchName
			WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
				 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
			THEN BPB.BranchName
			ELSE ''
		END AS NonAdBranch,
		CASE WHEN ISNULL(CPM.IsUsed, 0) = 1 THEN 'EPZ' ELSE 'Non-EPZ' END AS EPZNonEPZ,
		EBM.CURRENCY_CODE AS BillCurrency,
		EBM.ExportBillAmount AS BillAmount,
		CASE 
			WHEN EBM.TenorType = 'Deferred' THEN CONCAT(CAST(EBM.TENOR_DAYS AS VARCHAR(10)), ' Days ', TenorDescription.DisplayCode)
			ELSE tenor.DisplayCode
		END PaymentTerm,
		MD.LCSCTypeId AS InstrumentType,
		MD.LCNumber AS LCSCNumber,
		DocSendBank.Name + ', ' + ISNULL(DocSendBankBranch.Name, '') AS LCIssuingBankCollectingBank,
		'' AS DocumentsReceivingBank,
		'' AS DocumentsReceivingCountry,
		purchase.DateAdded AS PurchaseDate,
		purchase.DisbursedAmount AS PurchaseAmountFCY,
		EM.MailSentToFFDateDate AS DocumentsForwardingDate,
		DATEDIFF(DAY, EBM.DocReceiveDate, GETDATE()) AS TotalUnrespondedDays,
		CourierCompany.CourierCompany AS CouriersName,
		CourierReceipt.CourierReceipt AS CourierReciptNumber,
		EBM.EBIID AS EBIID,
		EBM.CustomerCode AS CustomerID,
		COALESCE(
			NULLIF(ADbpb.BranchID, ''), 
			CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END,
			''
		) AS ADBranchID,
		CASE 
			WHEN NonADbpb.BranchName IS NOT NULL 
				 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
			THEN ISNULL(NonADbpb.BranchID, '')
			WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
				 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
			THEN ISNULL(BPB.BranchID, '')
			ELSE ''
		END AS NonADBranchID,
		CASE WHEN ISNULL(CPM.IsUsed, 0) = 1 THEN 'EPZ' ELSE 'Non-EPZ' END AS EpzId,
		EBM.TenorType AS TenorType,
		EBM.MasterDocID AS MasterDocID,
		EM.MaturityDate AS MaturityDate,
		PartialPaymentReceived = (SELECT TOP 1 P.C_Amount
			FROM PRSCreationMaster P WITH(NOLOCK)
				LEFT JOIN (
					SELECT EBIID, MasterDocID, ExportBillAmount, CURRENCY_CODE, ExportBillNo, ExportBillAmount TempBillAmount, 'Export' BillType 
					FROM ExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND IsARVAdjusted = 0 AND ExportBillNo IS NOT NULL
					UNION
					SELECT EBIID, MasterDocID, ExportLocalBillAmount, CURRENCY_CODE, ExportLocalBillNo, ExportLocalBillAmount TempBillAmount, 'Local' BillType 
					FROM LocalExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
					UNION
					SELECT EBIID, EBIM.MasterDocID, (EBIM.ExportBillAmount - ISNULL(ARV.ARVAdjustmentAmount, 0)) ExportBillAmount, EBIM.CURRENCY_CODE, EBIM.ExportBillNo, EBIM.ExportBillAmount TempBillAmount, 'Export' BillType 
					FROM ExportBillInitiationMaster EBIM WITH(NOLOCK)   
						INNER JOIN (
							SELECT EBIIRMTD, SUM(AdjustmentAmount + ForeignBankCharge + ForeignCommission + DiscountAmount) ARVAdjustmentAmount
							FROM ExportBillAgainstRMTAdjustmentDetails WITH(NOLOCK)
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0
							GROUP BY EBIIRMTD
						) ARV ON ARV.EBIIRMTD = EBIM.EBIID
					WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND EBIM.ExportBillNo IS NOT NULL  
						AND EBIM.IsARVAdjusted = 1 AND (EBIM.ExportBillAmount - ISNULL(ARV.ARVAdjustmentAmount, 0)) != 0.00
				) E ON E.EBIID = ISNULL(P.EBIID, '')
			WHERE P.IsDeleted = 0 AND P.EBIID = EBM.EBIID AND CAST((P.ShortAmount / CASE WHEN P.PaymentType = 'ARV' THEN P.C_Amount ELSE E.ExportBillAmount END) * 100 AS DECIMAL(18, 2)) > 5
			ORDER BY P.DateAdded DESC),
		COALESCE(NULLIF(BPB.BranchName, ''), NULLIF(ADbpb.BranchName, ''), NULLIF(NonADbpb.BranchName, ''), '') AS BranchName		
		FROM (SELECT * FROM ExportBillInitiationMaster WITH(NOLOCK) WHERE ExportBillNo IS NOT NULL AND IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0) EBM
		INNER JOIN (SELECT * FROM LCAdvisingRegister WITH(NOLOCK) WHERE IsDeleted = 0 AND IsCancelled = 0) MD ON MD.LCReceiveID = EBM.MasterDocID
		LEFT JOIN ExportBillMonitoring EM WITH(NOLOCK) ON EM.EBIID = EBM.EBIID AND EM.IsDeleted = 0
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = EBM.CustomerCode
		LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON 
			BPB.BranchID = EBM.BranchID
			OR BPB.BranchID = REPLACE(EBM.BranchID, 'BPB/22/', 'OBPB/25/')
		LEFT JOIN SystemManager..BankProfileBranch ADbpb WITH(NOLOCK) ON 
			ADbpb.BranchID = COALESCE(
				NULLIF(MD.ADBranchID, ''), 
				CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END
			)
			OR ADbpb.BranchID = REPLACE(COALESCE(NULLIF(MD.ADBranchID, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END), 'BPB/22/', 'OBPB/25/')
		LEFT JOIN SystemManager..BankProfileBranch NonADbpb WITH(NOLOCK) ON 
			NonADbpb.BranchID = COALESCE(NULLIF(EBM.BranchID, ''), NULLIF(MD.BranchID, ''))
			OR NonADbpb.BranchID = REPLACE(COALESCE(NULLIF(EBM.BranchID, ''), NULLIF(MD.BranchID, '')), 'BPB/22/', 'OBPB/25/')
		LEFT JOIN SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = MD.Applicant
		LEFT JOIN (
			SELECT EBIID, SUM(DisbursedAmount) DisbursedAmount, MAX(DateAdded) DateAdded
			FROM PurchaseDiscountForeignDocumentMaster WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsExportLoan = 0
			GROUP BY EBIID
		) purchase ON purchase.EBIID = EBM.EBIID
		LEFT JOIN SystemManager..Contacts issuingBank WITH(NOLOCK) ON issuingBank.Code = MD.BankID
		LEFT JOIN SystemManager..Contacts DocSendBank WITH(NOLOCK) ON DocSendBank.Code = EBM.DocSendToBank
		LEFT JOIN SystemManager..Contacts DocSendBankBranch WITH(NOLOCK) ON DocSendBankBranch.Code = EBM.DocumentSendingBranch
		LEFT JOIN SystemManager..EntityFixedVariables tenor WITH(NOLOCK) ON tenor.EntityID = EBM.TenorType
		LEFT JOIN (SELECT EntityID, DisplayCode FROM SystemManager..EntityFixedVariables WITH(NOLOCK) WHERE EntityTypeID = 'TenorDescription') TenorDescription ON TenorDescription.EntityID = EBM.TenorDescription
	    LEFT JOIN (SELECT MasterId EBIID,
							STUFF((SELECT DISTINCT ', ' + CourierReceipt
										FROM CourierInfo CombinedE WITH(NOLOCK)
										WHERE CombinedE.MasterId = E.MasterId
										FOR XML PATH('')), 1, 1, '') AS CourierReceipt
					FROM CourierInfo E WITH(NOLOCK) GROUP BY MasterId) CourierReceipt ON CourierReceipt.EBIID = EBM.EBIID
		LEFT JOIN (SELECT MasterId EBIID,
							STUFF((SELECT DISTINCT ', ' + Name
										FROM (SELECT A.Name, MasterId FROM CourierInfo B WITH(NOLOCK)
										LEFT JOIN SystemManager..Contacts A WITH(NOLOCK) ON A.CODE = B.CourierCompany) CombinedE  
										WHERE CombinedE.MasterId = E.MasterId
										FOR XML PATH('')), 1, 1, '') AS CourierCompany
					FROM (SELECT A.Name, MasterId FROM CourierInfo B WITH(NOLOCK)
						  LEFT JOIN SystemManager..Contacts A WITH(NOLOCK) ON A.CODE = B.CourierCompany) E  
						  GROUP BY MasterId) CourierCompany ON CourierCompany.EBIID = EBM.EBIID
		LEFT JOIN (
			SELECT P.EBIID, SUM(C_Amount) + ISNULL(SUM(FCC.ChargeAmount), 0) RealizedValue, MAX(P.PRSDate) Date
			FROM PRSCreationMaster P WITH(NOLOCK)
				LEFT JOIN (
					SELECT C.PRSSysID, SUM(C.ChargeAmount) ChargeAmount
					FROM PRSCreationForeignCharges C WITH(NOLOCK)
					WHERE C.IsDeleted = 0
					GROUP BY C.PRSSysID
				) FCC ON FCC.PRSSysID = P.PRSSysID
			WHERE P.IsDeleted = 0
			GROUP BY P.EBIID
		) PRSM ON PRSM.EBIID = EBM.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate RealizedCCY WITH(NOLOCK) ON RealizedCCY.CurrencyCode = ISNULL(EBM.CURRENCY_CODE, '') AND RealizedCCY.RateFor = 'BC SELLING'
		WHERE CONVERT(DATE, EBM.BillGenerationDate) BETWEEN @FromDate AND @ToDate
		AND EM.MaturityDate IS NOT NULL AND DATEDIFF(DAY, EM.MaturityDate, GETDATE()) > 0 
		AND (ISNULL(PRSM.RealizedValue, 0) / EBM.ExportBillAmount) * 100 < 95
		) B
		GROUP BY
		LodgementDate,FDBCNumber,ClientsName,ADBranch,NonAdBranch,EPZNonEPZ,BillCurrency,BillAmount,PaymentTerm,InstrumentType,LCSCNumber,LCIssuingBankCollectingBank,DocumentsReceivingBank,DocumentsReceivingCountry,PurchaseDate,PurchaseAmountFCY,DocumentsForwardingDate,TotalUnrespondedDays,CouriersName,CourierReciptNumber
		,EBIID,CustomerID,ADBranchID,NonADBranchID,EpzId,TenorType,MasterDocID,MaturityDate,PartialPaymentReceived,BranchName
) C

ORDER BY MaturityDate ASC;

END
GO
