USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spRPTBTBBillsPaymentRegister] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROC [dbo].[spRPTBTBBillsPaymentRegister] 
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
	-- EXEC spRPTBTBBillsPaymentRegister '2024-01-01', '2026-12-31'
BEGIN
	SET NOCOUNT ON;

	SELECT 
		BPB.BranchName AS Branch,
		CONVERT(DATE, FDAM.BillGenerationDate) AS BillGenerationDate,
		LTRIM(RTRIM(REPLACE(REPLACE(FDAM.BillNo, CHAR(13), ''), CHAR(10), ''))) AS BillNumber,
		FDAM.ExternalId AS UBSContractReferenceNo,
		BBLCM.BBLCNo AS LCNumber,
		GL.GroupRefNo AS TAGNumber,
		CPM.CustomerName AS Customer,
		BBLCM.Benificiary AS Beneficiary,
		FDAM.Currency AS CCY,
		ISNULL(FDAM.BillAmount, 0) AS BillAmount,
		COALESCE(NegoBank.Name, FDAM.NEGOTIATING_BANK, '') AS DocumentForwardingBank,
		COALESCE(FDAM.NegoBankBillRef, FDAM.NEGOTIATING_BANK_REF, '') AS DocumentForwardingBankReference,
		CASE 
			WHEN ISNULL(FDAM.TENOR_DAYS, 0) > 0 
				THEN CONVERT(VARCHAR(15), CAST(FDAM.TENOR_DAYS AS INT)) + ' Days' 
			WHEN ISNULL(BBLCM.Tenor, 0) > 0 
				THEN CONVERT(VARCHAR(15), CAST(BBLCM.Tenor AS INT)) + ' Days' + ISNULL(' ' + TenorDes.DisplayCode, '')
			WHEN DATEDIFF(DAY, COALESCE(FDAM.DocReceiveDate, FDAM.BillGenerationDate), FDAM.MATURITY_DATE) > 0 
				THEN CONVERT(VARCHAR(15), DATEDIFF(DAY, COALESCE(FDAM.DocReceiveDate, FDAM.BillGenerationDate), FDAM.MATURITY_DATE)) + ' Days'
			WHEN TenorType.DisplayCode IS NOT NULL AND TenorType.DisplayCode <> ''
				THEN TenorType.DisplayCode
			ELSE 'At Sight' 
		END AS Tenor,
		CONVERT(DATE, FDAM.MATURITY_DATE) AS DueDate,
		CONVERT(DATE, FDPM.VALUE_DATE) AS PaymentDate,
		ISNULL(FDPM.PaymentAmount, 0) AS PaymentAmount,
		FDPM.DISC_CHG AS DiscrepancyFee,
		'' AS FDDNumber,
		'' AS FDDValue,
		'' AS FDDIssueDate,
		FDAM.IMPNumber AS IMPNumber,
		FDAM.Remarks AS Remarks,
		CONVERT(DATE, ISNULL(@FromDate, FDPM.VALUE_DATE)) AS FromDate,
		CONVERT(DATE, ISNULL(@ToDate, FDPM.VALUE_DATE)) AS ToDate,
		FDAM.BranchID,
		FDAM.CustomerID,
		BPB.ADBranchID,
		BBLCM.LCode  
	FROM
		ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK)
		INNER JOIN BBLCMaster BBLCM WITH(NOLOCK) ON BBLCM.BBLCID = FDAM.BBLCID 
		LEFT JOIN GroupLC GL WITH(NOLOCK) ON GL.GroupSysID = BBLCM.GroupSysID 
		LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(FDAM.BranchID, '') 
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = FDAM.CustomerID
		LEFT JOIN SystemManager..Contacts NegoBank WITH(NOLOCK) ON NegoBank.Code = FDAM.NegotiatingBank
		LEFT JOIN SystemManager..EntityFixedVariables TenorType WITH(NOLOCK) ON TenorType.EntityID = BBLCM.TenorType
		LEFT JOIN SystemManager..EntityFixedVariables TenorDes WITH(NOLOCK) ON TenorDes.EntityID = BBLCM.TenorDescription
		INNER JOIN (
			SELECT M.FDAID, MAX(M.VALUE_DATE) VALUE_DATE, SUM(M.PaymentAmount) PaymentAmount, MAX(DISC_CHG) DISC_CHG
			FROM
			(
				SELECT P.FDAID, MAX(P.VALUE_DATE) VALUE_DATE, MAX(P.PaymentAmount) PaymentAmount, MAX(DISC_CHG) DISC_CHG
				FROM ForeignDocumentPaymentMaster P WITH(NOLOCK)
				WHERE P.IsDeleted = 0 AND ISNULL(P.PaymentAmount, 0) > 0
				GROUP BY P.FDAID, P.VALUE_DATE
			) M
			GROUP BY M.FDAID
		) FDPM ON FDPM.FDAID = FDAM.FDAID
	WHERE   
		FDAM.IsDeleted = 0  
		AND FDAM.IsCancelled = 0 		  
		AND FDAM.BillNo IS NOT NULL
		AND LTRIM(RTRIM(FDAM.BillNo)) <> ''
		AND (@FromDate IS NULL OR CONVERT(DATE, FDPM.VALUE_DATE) >= @FromDate)
		AND (@ToDate IS NULL OR CONVERT(DATE, FDPM.VALUE_DATE) <= @ToDate)
	ORDER BY 
		CONVERT(DATE, FDPM.VALUE_DATE) DESC,
		FDAM.BillNo ASC
END
GO
