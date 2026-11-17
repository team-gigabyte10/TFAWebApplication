USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spRPTBTBBillsPaymentRegister]    Script Date: 11/17/2026 11:48:11 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   PROC [dbo].[spRPTBTBBillsPaymentRegister] 
AS
	----  spRPTBTBBillsPaymentRegister  
BEGIN
	SELECT 
		BPB.BranchName AS Branch                         ,
		CONVERT(DATE,FDAM.BillGenerationDate) AS BillGenerationDate			 ,
		LTRIM(RTRIM(FDAM.BillNo)) AS BillNumber					 ,
		FDAM.ExternalId AS UBSContractReferenceNo		 ,
		BBLCM.BBLCNo AS LCNumber						 ,
		GL.GroupRefNo AS TAGNumber						 ,
		CPM.CustomerName AS Customer						 ,
		BBLCM.Benificiary AS Beneficiary					 ,
		FDAM.Currency AS CCY							 ,
		ISNULL(FDAM.BillAmount,0) AS BillAmount					 ,
		FDAM.NEGOTIATING_BANK AS DocumentForwardingBank		 ,
		FDAM.NEGOTIATING_BANK_REF AS DocumentForwardingBankReference,
		CASE 
			WHEN ISNULL(FDAM.TENOR_DAYS, 0) > 0 THEN CONVERT(varchar(15), CAST(FDAM.TENOR_DAYS AS INT)) + ' Days' 
			WHEN ISNULL(BBLCM.Tenor, 0) > 0 THEN CONVERT(varchar(15), CAST(BBLCM.Tenor AS INT)) + ' Days'
			WHEN DATEDIFF(DAY, FDAM.BillGenerationDate, FDAM.MATURITY_DATE) > 0 THEN CONVERT(varchar(15), DATEDIFF(DAY, FDAM.BillGenerationDate, FDAM.MATURITY_DATE)) + ' Days'
			ELSE 'At Sight' 
		END AS Tenor							 ,
		CONVERT(DATE,FDAM.MATURITY_DATE) AS DueDate						 ,
		CONVERT(DATE,FDPM.VALUE_DATE) AS PaymentDate					 ,
		ISNULL(FDPM.PaymentAmount,0) AS PaymentAmount					 ,
		FDPM.DISC_CHG AS DiscrepancyFee				 ,
		'' AS FDDNumber						 ,
		'' AS FDDValue						 ,
		'' AS FDDIssueDate					 ,
		FDAM.IMPNumber AS IMPNumber,
		FDAM.Remarks AS Remarks,
		CONVERT(DATE,FDAM.BillGenerationDate) FromDate,
		CONVERT(DATE,FDAM.BillGenerationDate) ToDate,
		FDAM.BranchID,
		FDAM.CustomerID,
		BPB.ADBranchID,
		BBLCM.LCode  
	FROM
		ForeignDocumentAcceptanceMaster FDAM 
		INNER JOIN  BBLCMaster BBLCM ON BBLCM.BBLCID = FDAM.BBLCID 
		LEFT  JOIN  GroupLC GL  ON GL.GroupSysID = BBLCM.GroupSysID 
		LEFT  JOIN  SystemManager..BankProfileBranch BPB  ON BPB.BranchID = ISNULL(FDAM.BranchID,'') 
		LEFT  JOIN  SystemManager..CustomerProfileMaster CPM  ON CPM.CustomerID = FDAM.CustomerID
		INNER JOIN (
			SELECT M.FDAID, MAX(M.VALUE_DATE) VALUE_DATE, SUM(M.PaymentAmount) PaymentAmount, MAX(DISC_CHG) DISC_CHG
			FROM
			(
				SELECT P.FDAID, MAX(P.VALUE_DATE) VALUE_DATE, MAX(P.PaymentAmount) PaymentAmount, MAX(DISC_CHG) DISC_CHG
				FROM ForeignDocumentPaymentMaster P
				WHERE P.IsDeleted = 0 AND ISNULL(P.PaymentAmount, 0) > 0
				GROUP BY P.FDAID, P.VALUE_DATE
			) M
			GROUP BY M.FDAID
		) FDPM ON FDPM.FDAID = FDAM.FDAID
	WHERE   
		 FDAM.IsDeleted = 0  AND FDAM.IsCancelled = 0 		  
		 AND FDAM.BillNo IS NOT NULL		
	ORDER BY CONVERT(DATE,FDPM.VALUE_DATE)
END
