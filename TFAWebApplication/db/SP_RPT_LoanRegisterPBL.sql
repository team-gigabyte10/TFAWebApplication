USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_LoanRegisterPBL]    Script Date: 11/22/2026 11:40:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[SP_RPT_LoanRegisterPBL]
@FromDate DATETIME,
@ToDate DATETIME
 
AS										
-- SP_RPT_LoanRegisterPBL '2020-10-04' , '2023-10-06'

BEGIN
	SET NOCOUNT ON;

	---------------------------------------------------------------------------------------------------------
	-- Helper CTE for LoanCreation Expiry and Interest Rate fallback (for PC loans)
	---------------------------------------------------------------------------------------------------------
	;WITH LC_Fallback AS (
		SELECT 
			LoanKey,
			MAX(NULLIF(INTEREST_RATE, 0)) AS INTEREST_RATE,
			MAX(NULLIF(INT_OS, 0)) AS INT_OS,
			MAX(MATURITY_DATE) AS MATURITY_DATE,
			MAX(LoanExpiry) AS LoanExpiry
		FROM (
			SELECT 
				COALESCE(NULLIF(LoanNo, ''), NULLIF(AdditionalFilter, ''), NULLIF(ExternalID, ''), ACCOUNT_NUMBER) AS LoanKey,
				INTEREST_RATE,
				INT_OS,
				MATURITY_DATE,
				LoanExpiry
			FROM LoanCreation WITH(NOLOCK)
			WHERE IsDeleted = 0
		) LC_INNER
		WHERE LoanKey IS NOT NULL
		GROUP BY LoanKey
	)

	---------------------------------------------------------------------------------------------------------
	-- UNION 1: LoanCreation (General / Import / Forced / EDF / etc.)
	---------------------------------------------------------------------------------------------------------
	SELECT DISTINCT
		L.Loancreationdate AS DisbursementDate,
		CPM.customername AS ClientsName,
		GLC.GroupRefNo AS GroupRef,
		ADBranchName = ISNULL(AdBranch.BranchName, AdBranch2.BranchName),
		NonADBranchName = ISNULL(
			CASE WHEN RTRIM(LTRIM(ISNULL(Branch.BranchName, Branch2.BranchName))) = RTRIM(LTRIM(ISNULL(AdBranch.BranchName, AdBranch2.BranchName))) 
				 THEN '' 
				 ELSE Branch.BranchName 
			END,
			CASE WHEN RTRIM(LTRIM(Branch2.BranchName)) = RTRIM(LTRIM(AdBranch2.BranchName)) 
				 THEN '' 
				 ELSE ISNULL(Branch2.BranchName, Branch2.BranchName) 
			END
		),
		LoanTypeName = CASE 
			WHEN (ISNULL(AdBranch.BranchName, AdBranch2.BranchName) LIKE '%Dilkusha%' OR ISNULL(AdBranch.BranchName, AdBranch2.BranchName) LIKE '%Nijam%' OR ISNULL(AdBranch.BranchName, AdBranch2.BranchName) LIKE '%Nizam%'
				  OR ISNULL(Branch.BranchName, Branch2.BranchName) LIKE '%Dilkusha%' OR ISNULL(Branch.BranchName, Branch2.BranchName) LIKE '%Nijam%' OR ISNULL(Branch.BranchName, Branch2.BranchName) LIKE '%Nizam%')
				 AND (EFV.DisplayCode = 'PC' OR EFV.DisplayCode LIKE '%PC%' OR L.Loanagainst = 'LoanType/PC' OR L.Loanagainst = 'LoanType/IBPC')
				 THEN 'Bai Salam'
			WHEN (ISNULL(AdBranch.BranchName, AdBranch2.BranchName) LIKE '%Dilkusha%' OR ISNULL(AdBranch.BranchName, AdBranch2.BranchName) LIKE '%Nijam%' OR ISNULL(AdBranch.BranchName, AdBranch2.BranchName) LIKE '%Nizam%'
				  OR ISNULL(Branch.BranchName, Branch2.BranchName) LIKE '%Dilkusha%' OR ISNULL(Branch.BranchName, Branch2.BranchName) LIKE '%Nijam%' OR ISNULL(Branch.BranchName, Branch2.BranchName) LIKE '%Nizam%')
				 AND (EFV.DisplayCode = 'FDBP' OR EFV.DisplayCode LIKE '%FDBP%')
				 THEN 'Bills Islamic'
			ELSE EFV.DisplayCode
		END,
		LoanReferenceNo = COALESCE(
			NULLIF(CASE 
				WHEN L.LoanNo LIKE 'LD%' AND CHARINDEX(',', L.LoanNo) = 0 THEN L.LoanNo
				WHEN L.LoanNo LIKE 'LD%' AND CHARINDEX(',', L.LoanNo) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNo, 1, CHARINDEX(',', L.LoanNo) - 1)))
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) = 0 THEN L.ExternalID
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN L.ACCOUNT_NUMBER LIKE 'LD%' THEN L.ACCOUNT_NUMBER
			END, ''),
			NULLIF(CASE 
				WHEN L.LoanNo NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNo) = 0 AND NULLIF(L.LoanNo, '') IS NOT NULL THEN L.LoanNo
				WHEN L.LoanNo NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNo) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNo, 1, CHARINDEX(',', L.LoanNo) - 1)))
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) = 0 AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN NULLIF(L.ACCOUNT_NUMBER, '') IS NOT NULL THEN L.ACCOUNT_NUMBER
			END, ''),
			CASE 
				WHEN CHARINDEX(',', L.LoanNo) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNo, 1, CHARINDEX(',', L.LoanNo) - 1)))
				ELSE L.LoanNo 
			END
		),
		Currency = COALESCE(NULLIF(L.LoanCurrency, ''), NULLIF(L.Currency, ''), NULLIF(md.Currency, ''), NULLIF(FDAM.Currency, ''), NULLIF(IML.Currency, ''), 'BDT'),
		DisbursementAmount = COALESCE(NULLIF(L.LoanAmount, 0), NULLIF(L.BillAmount, 0), NULLIF(L.PRINCIPAL_OS, 0), NULLIF(md.BBLCAmount, 0), NULLIF(FDAM.BillAmount, 0), 0),
		RateofInterest = COALESCE(NULLIF(L.INTEREST_RATE, 0), NULLIF(L.INT_OS, 0), NULLIF(L.PENAL_IN, 0)),
		PresentOutstanding = CASE 
			WHEN l.UBSSyncProcessID = 0 THEN l.LoanAmount 
			WHEN l.UBSSyncProcessID = 1 AND l.AdjustmentAmount = 0 THEN l.LoanAmount
			ELSE ISNULL(l.OutstandingAmount, 0) 
		END,
		LoanExpiryDate = COALESCE(L.MATURITY_DATE, L.LoanExpiry),
		OverdueDays = CASE 
			WHEN (CASE WHEN l.UBSSyncProcessID = 0 THEN l.LoanAmount 
					   WHEN l.UBSSyncProcessID = 1 AND l.AdjustmentAmount = 0 THEN l.LoanAmount
					   ELSE ISNULL(l.OutstandingAmount, 0) 
				  END) > 0 
				 AND CAST(COALESCE(L.MATURITY_DATE, L.LoanExpiry) AS DATE) < CAST(GETDATE() AS DATE)
				 AND COALESCE(L.MATURITY_DATE, L.LoanExpiry) IS NOT NULL
			THEN DATEDIFF(DAY, COALESCE(L.MATURITY_DATE, L.LoanExpiry), GETDATE())
			ELSE '' 
		END,
		CPM.CustomerID AS CustomerID, 
		ADBranchID = ISNULL(glc.ADBranchID, r.ADBranchID),
		NonADBranchID = ISNULL(glc.bankBranchID, r.BranchID),
		L.Loanagainst AS LoanType
	FROM LoanCreation L WITH(NOLOCK)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = L.Customer
		LEFT JOIN SystemManager..EntityFixedVariables EFV WITH(NOLOCK) ON EFV.entityid = L.Loanagainst
		LEFT JOIN BBLCMaster md WITH(NOLOCK) ON md.BBLCID = L.BBLCID
		LEFT JOIN BBLCRequestMaster r WITH(NOLOCK) ON r.BBLCID = L.BBLCID
		LEFT JOIN ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK) ON FDAM.Billno = L.AdditionalFilter
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = md.GroupSysID
		LEFT JOIN ImportLCmaster IML WITH(NOLOCK) ON IML.ImportLCID = L.BBLCID
		LEFT JOIN [SystemManager]..BankProfileBranch Branch WITH(NOLOCK) ON Branch.BranchID = glc.bankBranchID
		LEFT JOIN [SystemManager]..BankProfileBranch AdBranch WITH(NOLOCK) ON AdBranch.BranchID = glc.ADBranchID
		LEFT JOIN [SystemManager]..BankProfileBranch Branch2 WITH(NOLOCK) ON Branch2.BranchID = r.BranchID
		LEFT JOIN [SystemManager]..BankProfileBranch AdBranch2 WITH(NOLOCK) ON AdBranch2.BranchID = r.ADBranchID
	WHERE 
		CONVERT(DATE, L.LoanCreationDate) BETWEEN @FromDate AND @ToDate 
		AND ISNULL(L.IsDeleted, 0) = 0 
		AND L.LoanNo IS NOT NULL 
		AND r.isdeleted = 0

	UNION ALL

	---------------------------------------------------------------------------------------------------------
	-- UNION 2: PurchaseDiscountForeignDocumentMaster (Purchase / FDBP)
	---------------------------------------------------------------------------------------------------------
	SELECT
		L.ApplyDate AS DisbursementDate,
		CPM.customername AS ClientsName,
		GGLC.GroupRefNo AS GroupRef,
		ADBranchName = AdBranch.BranchName,
		NonADBranchName = CASE WHEN RTRIM(LTRIM(Branch.BranchName)) = RTRIM(LTRIM(AdBranch.BranchName)) THEN '' ELSE Branch.BranchName END,
		LoanTypeName = CASE 
			WHEN (AdBranch.BranchName LIKE '%Dilkusha%' OR AdBranch.BranchName LIKE '%Nijam%' OR AdBranch.BranchName LIKE '%Nizam%'
				  OR Branch.BranchName LIKE '%Dilkusha%' OR Branch.BranchName LIKE '%Nijam%' OR Branch.BranchName LIKE '%Nizam%')
				 THEN 'Bills Islamic'
			ELSE 'Purchase'
		END,
		LoanReferenceNo = COALESCE(
			NULLIF(CASE 
				WHEN L.LoanNumber LIKE 'LD%' AND CHARINDEX(',', L.LoanNumber) = 0 THEN L.LoanNumber
				WHEN L.LoanNumber LIKE 'LD%' AND CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) = 0 THEN L.ExternalID
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN L.Account_Number LIKE 'LD%' THEN L.Account_Number
			END, ''),
			NULLIF(CASE 
				WHEN L.LoanNumber NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNumber) = 0 AND NULLIF(L.LoanNumber, '') IS NOT NULL THEN L.LoanNumber
				WHEN L.LoanNumber NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) = 0 AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN NULLIF(L.Account_Number, '') IS NOT NULL THEN L.Account_Number
			END, ''),
			CASE 
				WHEN CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				ELSE L.LoanNumber 
			END
		),
		Currency = COALESCE(NULLIF(L.CURRENCY, ''), NULLIF(MD.Currency, ''), NULLIF(L.AC_CCY, ''), NULLIF(L.CR_AC_CCY, ''), 'BDT'),
		DisbursementAmount = COALESCE(NULLIF(L.DisbursedAmount, 0), NULLIF(L.LoanBasisAmount, 0), NULLIF(L.SanctionAmount, 0), NULLIF(L.CustomerRequestAmt, 0), NULLIF(L.CR_LCY_AMOUNT, 0), NULLIF(L.FCY_AMOUNT, 0), 0),
		RateofInterest = COALESCE(NULLIF(L.InterestRate, 0), NULLIF(L.INT_OS, 0)),
		PresentOutstanding = CASE 
			WHEN l.UBSSyncProcessID = 0 THEN L.DisbursedAmount
			WHEN ISNULL(LEN(ISNULL(CONVERT(DATE, (SELECT MAX(ll.DateAdded) FROM [EFA]..CustomerVoucherTransDetails ll WITH(NOLOCK) WHERE ll.AdditionalFilter = 'Purchase Discount Foreign Document Master' AND ll.CreditAccountNo = '503010101' AND l.ExternalID = ll.AdditionalMasterID)), CONVERT(DATE, PRS.RealizedDate))), 0) < 1 THEN L.DisbursedAmount
			ELSE ISNULL(l.TOT_OS, 0) 
		END,
		LoanExpiryDate = L.MaturityDate,
		OverdueDays = CASE 
			WHEN (CASE WHEN l.UBSSyncProcessID = 0 THEN L.DisbursedAmount
					   WHEN ISNULL(LEN(ISNULL(CONVERT(DATE, (SELECT MAX(ll.DateAdded) FROM [EFA]..CustomerVoucherTransDetails ll WITH(NOLOCK) WHERE ll.AdditionalFilter = 'Purchase Discount Foreign Document Master' AND ll.CreditAccountNo = '503010101' AND l.ExternalID = ll.AdditionalMasterID)), CONVERT(DATE, PRS.RealizedDate))), 0) < 1 THEN L.DisbursedAmount
					   ELSE ISNULL(l.TOT_OS, 0) 
				  END) > 0 
				 AND CAST(L.MaturityDate AS DATE) < CAST(GETDATE() AS DATE)
				 AND L.MaturityDate IS NOT NULL
			THEN DATEDIFF(DAY, L.MaturityDate, GETDATE())
			ELSE '' 
		END,
		CPM.CustomerID AS CustomerID,
		ADBranch.ADBranchID AS ADBranchID,
		Branch.BranchID AS NonADBranchID,
		'Purchase' AS LoanType
	FROM PurchaseDiscountForeignDocumentMaster L WITH(NOLOCK)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = L.CustomerID
		LEFT JOIN Masterdoc MD WITH(NOLOCK) ON MD.MasterDocID = L.MasterDocID
		LEFT JOIN GROUPLC GGLC WITH(NOLOCK) ON GGLC.GroupSysID = MD.GroupSysID
		LEFT JOIN SystemManager..BankProfileBranch Branch WITH(NOLOCK) ON Branch.branchid = L.BranchID
		LEFT JOIN SystemManager..BankProfileBranch ADBranch WITH(NOLOCK) ON ADBranch.branchid = L.ADBranchID
		LEFT JOIN (
			SELECT M.BillRefNo, MAX(M.Date) AS RealizedDate, SUM(M.ProceedsRecvd) AS RealizedValue
			FROM (
				SELECT P.BillRefNo, MAX(P.Date) AS Date, MAX(P.ProceedsRecvd) AS ProceedsRecvd
				FROM PRSCreationDistributionDetails P WITH(NOLOCK)
				WHERE P.IsDeleted = 0 AND P.PRSNCADID != 'NOT_NCA'
				GROUP BY P.BillRefNo, P.Date
			) M
			GROUP BY M.BillRefNo
		) PRS ON PRS.BillRefNo = l.EBIID
	WHERE 
		CONVERT(DATE, L.ApplyDate) BETWEEN @FromDate AND @ToDate 
		AND ISNULL(L.IsDeleted, 0) = 0 
		AND ISNULL(L.IsExportLoan, 0) = 0 
		AND L.IsPurchaseLoanType = 1 
		AND L.LoanNumber IS NOT NULL

	UNION ALL

	---------------------------------------------------------------------------------------------------------
	-- UNION 3: PurchaseDiscountForeignDocumentMaster (Discount / FDBP)
	---------------------------------------------------------------------------------------------------------
	SELECT
		L.ApplyDate AS DisbursementDate,
		CPM.customername AS ClientsName,
		GGLC.GroupRefNo AS GroupRef,
		ADBranchName = AdBranch.BranchName,
		NonADBranchName = CASE WHEN RTRIM(LTRIM(Branch.BranchName)) = RTRIM(LTRIM(AdBranch.BranchName)) THEN '' ELSE Branch.BranchName END,
		LoanTypeName = CASE 
			WHEN (AdBranch.BranchName LIKE '%Dilkusha%' OR AdBranch.BranchName LIKE '%Nijam%' OR AdBranch.BranchName LIKE '%Nizam%'
				  OR Branch.BranchName LIKE '%Dilkusha%' OR Branch.BranchName LIKE '%Nijam%' OR Branch.BranchName LIKE '%Nizam%')
				 THEN 'Bills Islamic'
			ELSE 'Discount'
		END,
		LoanReferenceNo = COALESCE(
			NULLIF(CASE 
				WHEN L.LoanNumber LIKE 'LD%' AND CHARINDEX(',', L.LoanNumber) = 0 THEN L.LoanNumber
				WHEN L.LoanNumber LIKE 'LD%' AND CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) = 0 THEN L.ExternalID
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN L.Account_Number LIKE 'LD%' THEN L.Account_Number
			END, ''),
			NULLIF(CASE 
				WHEN L.LoanNumber NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNumber) = 0 AND NULLIF(L.LoanNumber, '') IS NOT NULL THEN L.LoanNumber
				WHEN L.LoanNumber NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) = 0 AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN NULLIF(L.Account_Number, '') IS NOT NULL THEN L.Account_Number
			END, ''),
			CASE 
				WHEN CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				ELSE L.LoanNumber 
			END
		),
		Currency = COALESCE(NULLIF(L.CURRENCY, ''), NULLIF(MD.Currency, ''), NULLIF(L.AC_CCY, ''), NULLIF(L.CR_AC_CCY, ''), 'BDT'),
		DisbursementAmount = COALESCE(NULLIF(L.DisbursedAmount, 0), NULLIF(L.LoanBasisAmount, 0), NULLIF(L.SanctionAmount, 0), NULLIF(L.CustomerRequestAmt, 0), NULLIF(L.CR_LCY_AMOUNT, 0), NULLIF(L.FCY_AMOUNT, 0), 0),
		RateofInterest = COALESCE(NULLIF(L.InterestRate, 0), NULLIF(L.INT_OS, 0)),
		PresentOutstanding = CASE 
			WHEN l.UBSSyncProcessID = 0 THEN L.DisbursedAmount
			WHEN ISNULL(LEN(CONVERT(DATE, (SELECT MAX(ll.DateAdded) FROM [EFA]..CustomerVoucherTransDetails ll WITH(NOLOCK) WHERE ll.AdditionalFilter = 'Purchase Discount Foreign Document Master' AND ll.CreditAccountNo = '503010101' AND l.ExternalID = ll.AdditionalMasterID))), 0) < 1 THEN L.DisbursedAmount
			ELSE ISNULL(l.TOT_OS, 0) 
		END,
		LoanExpiryDate = L.MaturityDate,
		OverdueDays = CASE 
			WHEN (CASE WHEN l.UBSSyncProcessID = 0 THEN L.DisbursedAmount
					   WHEN ISNULL(LEN(CONVERT(DATE, (SELECT MAX(ll.DateAdded) FROM [EFA]..CustomerVoucherTransDetails ll WITH(NOLOCK) WHERE ll.AdditionalFilter = 'Purchase Discount Foreign Document Master' AND ll.CreditAccountNo = '503010101' AND l.ExternalID = ll.AdditionalMasterID))), 0) < 1 THEN L.DisbursedAmount
					   ELSE ISNULL(l.TOT_OS, 0) 
				  END) > 0 
				 AND CAST(L.MaturityDate AS DATE) < CAST(GETDATE() AS DATE)
				 AND L.MaturityDate IS NOT NULL
			THEN DATEDIFF(DAY, L.MaturityDate, GETDATE())
			ELSE '' 
		END,	
		CPM.CustomerID AS CustomerID,
		ADBranch.ADBranchID AS ADBranchID,
		Branch.BranchID AS NonADBranchID,
		'Discount' AS LoanType
	FROM PurchaseDiscountForeignDocumentMaster L WITH(NOLOCK)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = L.CustomerID
		LEFT JOIN Masterdoc MD WITH(NOLOCK) ON MD.MasterDocID = L.MasterDocID
		LEFT JOIN GROUPLC GGLC WITH(NOLOCK) ON GGLC.GroupSysID = MD.GroupSysID
		LEFT JOIN SystemManager..BankProfileBranch Branch WITH(NOLOCK) ON Branch.branchid = L.BranchID
		LEFT JOIN SystemManager..BankProfileBranch ADBranch WITH(NOLOCK) ON ADBranch.branchid = L.ADBranchID
	WHERE 
		CONVERT(DATE, L.ApplyDate) BETWEEN @FromDate AND @ToDate 
		AND ISNULL(L.IsDeleted, 0) = 0 
		AND ISNULL(L.IsExportLoan, 0) = 0 
		AND ISNULL(L.IsPurchaseLoanType, 0) = 0 
		AND L.LoanNumber IS NOT NULL

	UNION ALL

	---------------------------------------------------------------------------------------------------------
	-- UNION 4: PurchaseDiscountForeignDocumentMaster (Export Loan / Time Loan)
	---------------------------------------------------------------------------------------------------------
	SELECT
		L.ApplyDate AS DisbursementDate,
		CPM.customername AS ClientsName,
		ISNULL(GGLC.GroupRefNo, GLC.GroupRefNo) AS GroupRef,
		ADbpb.BranchName AS ADBranchName,
		NonADbpb.BranchName AS NonADBranchName,
		LoanTypeName = CASE 
			WHEN L.PurchaseLoanTypeID = 'DemandLoan' THEN 'Demand Loan'
			WHEN L.PurchaseLoanTypeID = 'TimeLoan' THEN 'Time Loan'
			WHEN L.PurchaseLoanTypeID IS NULL OR L.PurchaseLoanTypeID = '' THEN 'Time Loan'
			WHEN L.LoanType LIKE '%Time%' THEN 'Time Loan'
			WHEN L.LoanType IS NOT NULL AND L.LoanType <> '' THEN L.LoanType
			ELSE 'Time Loan'
		END,
		LoanReferenceNo = COALESCE(
			NULLIF(CASE 
				WHEN L.LoanNumber LIKE 'LD%' AND CHARINDEX(',', L.LoanNumber) = 0 THEN L.LoanNumber
				WHEN L.LoanNumber LIKE 'LD%' AND CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) = 0 THEN L.ExternalID
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN L.Account_Number LIKE 'LD%' THEN L.Account_Number
			END, ''),
			NULLIF(CASE 
				WHEN L.LoanNumber NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNumber) = 0 AND NULLIF(L.LoanNumber, '') IS NOT NULL THEN L.LoanNumber
				WHEN L.LoanNumber NOT LIKE 'TF%' AND CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) = 0 AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
				WHEN NULLIF(L.Account_Number, '') IS NOT NULL THEN L.Account_Number
			END, ''),
			CASE 
				WHEN CHARINDEX(',', L.LoanNumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.LoanNumber, 1, CHARINDEX(',', L.LoanNumber) - 1)))
				ELSE L.LoanNumber 
			END
		),
		Currency = COALESCE(NULLIF(L.CURRENCY, ''), NULLIF(MD2.Currency, ''), NULLIF(EBM.CURRENCY_CODE, ''), NULLIF(EBM.BILL_CCY, ''), NULLIF(L.AC_CCY, ''), 'BDT'),
		DisbursementAmount = COALESCE(NULLIF(L.DisbursedAmount, 0), NULLIF(L.LoanBasisAmount, 0), NULLIF(L.ExportLoanLimitAmount, 0), NULLIF(L.SanctionAmount, 0), NULLIF(L.CustomerRequestAmt, 0), NULLIF(L.CR_LCY_AMOUNT, 0), 0),
		RateofInterest = COALESCE(NULLIF(L.InterestRate, 0), NULLIF(L.INT_OS, 0)),
		PresentOutstanding = CASE 
			WHEN l.UBSSyncProcessID = 0 THEN l.DisbursedAmount 
			WHEN l.UBSSyncProcessID = 1 AND l.TOT_OS IS NULL THEN l.DisbursedAmount
			ELSE l.TOT_OS 
		END,
		LoanExpiryDate = L.MaturityDate,
		OverdueDays = CASE 
			WHEN (CASE WHEN l.UBSSyncProcessID = 0 THEN l.DisbursedAmount 
					   WHEN l.UBSSyncProcessID = 1 AND l.TOT_OS IS NULL THEN l.DisbursedAmount
					   ELSE l.TOT_OS 
				  END) > 0 
				 AND CAST(L.MaturityDate AS DATE) < CAST(GETDATE() AS DATE)
				 AND L.MaturityDate IS NOT NULL
			THEN DATEDIFF(DAY, L.MaturityDate, GETDATE())
			ELSE '' 
		END,
		CPM.CustomerID AS CustomerID,
		ADbpb.ADBranchID AS ADBranchID,
		NonADbpb.BranchID AS NonADBranchID,
		LoanType = CASE 
			WHEN L.PurchaseLoanTypeID = 'DemandLoan' THEN 'Demand Loan'
			WHEN L.PurchaseLoanTypeID = 'TimeLoan' THEN 'Time Loan'
			WHEN L.PurchaseLoanTypeID IS NULL OR L.PurchaseLoanTypeID = '' THEN 'Time Loan'
			WHEN L.LoanType LIKE '%Time%' THEN 'Time Loan'
			WHEN L.LoanType IS NOT NULL AND L.LoanType <> '' THEN L.LoanType
			ELSE 'Time Loan'
		END
	FROM PurchaseDiscountForeignDocumentMaster L WITH(NOLOCK)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = L.CustomerID
		LEFT JOIN PurchaseDiscountForeignDocumentChild LL WITH(NOLOCK) ON L.PDFDMID = LL.PDFDMID
		LEFT JOIN GROUPLC GGLC WITH(NOLOCK) ON GGLC.GroupSysID = LL.GroupSysID
		LEFT JOIN ExportBillInitiationMaster EBM WITH(NOLOCK) ON EBM.EBIID = LL.EBIID
		LEFT JOIN Masterdoc MD2 WITH(NOLOCK) ON MD2.MasterDocID = EBM.MasterDocID
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD2.GroupSysID
		LEFT JOIN SystemManager..BankProfileBranch NonADbpb WITH(NOLOCK) ON NonADbpb.branchid = L.BranchID
		LEFT JOIN SystemManager..BankProfileBranch ADbpb WITH(NOLOCK) ON ADbpb.branchid = L.ADBranchID
	WHERE 
		CONVERT(DATE, L.ApplyDate) BETWEEN @FromDate AND @ToDate 
		AND ISNULL(L.IsDeleted, 0) = 0 
		AND ISNULL(L.IsCancelled, 0) = 0 
		AND ISNULL(L.IsExportLoan, 0) = 1 
		AND L.LoanNumber IS NOT NULL

	UNION ALL

	---------------------------------------------------------------------------------------------------------
	-- UNION 5: PCDisbursementMaster (Packing Credit / PC)
	---------------------------------------------------------------------------------------------------------
	SELECT
		L.PCDisburseDate AS DisbursementDate,
		CPM.customername AS ClientsName,
		GLC.GroupRefNo AS GroupRef,
		ADBranchName = AdBranch.BranchName,
		NonADBranchName = CASE WHEN RTRIM(LTRIM(Branch.BranchName)) = RTRIM(LTRIM(AdBranch.BranchName)) THEN '' ELSE Branch.BranchName END,
		LoanTypeName = CASE 
			WHEN (AdBranch.BranchName LIKE '%Dilkusha%' OR AdBranch.BranchName LIKE '%Nijam%' OR AdBranch.BranchName LIKE '%Nizam%'
				  OR Branch.BranchName LIKE '%Dilkusha%' OR Branch.BranchName LIKE '%Nijam%' OR Branch.BranchName LIKE '%Nizam%')
				 THEN 'Bai Salam'
			ELSE EFV.DisplayCode
		END,
		LoanReferenceNo = COALESCE(
			NULLIF(CASE 
				WHEN L.AdditionalFilter LIKE 'LD%' AND CHARINDEX(',', L.AdditionalFilter) = 0 THEN L.AdditionalFilter
				WHEN L.AdditionalFilter LIKE 'LD%' AND CHARINDEX(',', L.AdditionalFilter) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.AdditionalFilter, 1, CHARINDEX(',', L.AdditionalFilter) - 1)))
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) = 0 THEN L.ExternalID
				WHEN L.ExternalID LIKE 'LD%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
			END, ''),
			NULLIF(CASE 
				WHEN L.AdditionalFilter NOT LIKE 'TF%' AND CHARINDEX(',', L.AdditionalFilter) = 0 AND NULLIF(L.AdditionalFilter, '') IS NOT NULL THEN L.AdditionalFilter
				WHEN L.AdditionalFilter NOT LIKE 'TF%' AND CHARINDEX(',', L.AdditionalFilter) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.AdditionalFilter, 1, CHARINDEX(',', L.AdditionalFilter) - 1)))
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) = 0 AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
				WHEN L.ExternalID NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalID) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalID, 1, CHARINDEX(',', L.ExternalID) - 1)))
			END, ''),
			CASE 
				WHEN CHARINDEX(',', L.AdditionalFilter) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.AdditionalFilter, 1, CHARINDEX(',', L.AdditionalFilter) - 1)))
				ELSE L.AdditionalFilter 
			END
		),
		Currency = COALESCE(NULLIF(L.Currency, ''), 'BDT'),
		DisbursementAmount = COALESCE(NULLIF(L.PCAmountTK, 0), NULLIF(L.PCAmount, 0), NULLIF(L.PRINCIPAL_OS, 0), 0),
		RateofInterest = COALESCE(NULLIF(L.InterestRate, 0), NULLIF(LC.INTEREST_RATE, 0), NULLIF(LC.INT_OS, 0), NULLIF(L.PCorSODInterestAmount, 0), NULLIF(L.INT_OS, 0)),
		PresentOutstanding = CASE 
			WHEN L.TransactionDate IS NULL THEN L.PCAmountTK                      
			ELSE L.TOT_OS 
		END,
		LoanExpiryDate = COALESCE(
			L.MATURITY_DATE,
			L.ExpiryDate,
			L.InterestDueDate,
			LC.MATURITY_DATE,
			LC.LoanExpiry,
			CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, ISNULL(L.PCDisburseDate, L.PCCreationDate)) END,
			MD.ExpiryDate,
			MD.ShipmentDate,
			DATEADD(DAY, 90, ISNULL(L.PCDisburseDate, L.PCCreationDate))
		),
		OverdueDays = CASE 
			WHEN (CASE WHEN l.UBSSyncProcessID = 0 THEN l.PCAmountTK 
					   WHEN l.UBSSyncProcessID = 1 AND l.TOT_OS IS NULL THEN l.PCAmountTK
					   ELSE l.TOT_OS 
				  END) > 0 
				 AND CAST(COALESCE(L.MATURITY_DATE, L.ExpiryDate, L.InterestDueDate, LC.MATURITY_DATE, LC.LoanExpiry, CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, ISNULL(L.PCDisburseDate, L.PCCreationDate)) END, MD.ExpiryDate, MD.ShipmentDate, DATEADD(DAY, 90, ISNULL(L.PCDisburseDate, L.PCCreationDate))) AS DATE) < CAST(GETDATE() AS DATE)
				 AND COALESCE(L.MATURITY_DATE, L.ExpiryDate, L.InterestDueDate, LC.MATURITY_DATE, LC.LoanExpiry, CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, ISNULL(L.PCDisburseDate, L.PCCreationDate)) END, MD.ExpiryDate, MD.ShipmentDate, DATEADD(DAY, 90, ISNULL(L.PCDisburseDate, L.PCCreationDate))) IS NOT NULL
			THEN DATEDIFF(DAY, COALESCE(L.MATURITY_DATE, L.ExpiryDate, L.InterestDueDate, LC.MATURITY_DATE, LC.LoanExpiry, CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, ISNULL(L.PCDisburseDate, L.PCCreationDate)) END, MD.ExpiryDate, MD.ShipmentDate, DATEADD(DAY, 90, ISNULL(L.PCDisburseDate, L.PCCreationDate))), GETDATE())
			ELSE '' 
		END,	
		CPM.CustomerID AS CustomerID,
		GLC.ADBranchID AS ADBranchID,
		GLC.BankBranchID AS NonADBranchID,
		LoanType = CASE 
			WHEN (AdBranch.BranchName LIKE '%Dilkusha%' OR AdBranch.BranchName LIKE '%Nijam%' OR AdBranch.BranchName LIKE '%Nizam%'
				  OR Branch.BranchName LIKE '%Dilkusha%' OR Branch.BranchName LIKE '%Nijam%' OR Branch.BranchName LIKE '%Nizam%')
				 THEN 'Bai Salam'
			ELSE L.LoanType
		END
	FROM PCDisbursementMaster L WITH(NOLOCK)
		LEFT JOIN LC_Fallback LC ON LC.LoanKey = L.AdditionalFilter OR LC.LoanKey = L.PCDMID OR LC.LoanKey = L.ExternalID
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = L.CustomerID
		LEFT JOIN MasterDoc MD WITH(NOLOCK) ON L.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..EntityFixedVariables EFV WITH(NOLOCK) ON EFV.entityid = L.LoanType
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = L.GrouprefID
		LEFT JOIN [SystemManager]..BankProfileBranch Branch WITH(NOLOCK) ON Branch.BranchID = glc.bankBranchID
		LEFT JOIN [SystemManager]..BankProfileBranch AdBranch WITH(NOLOCK) ON AdBranch.BranchID = glc.ADBranchID
	WHERE 
		CONVERT(DATE, L.PCDisburseDate) BETWEEN @FromDate AND @ToDate 
		AND ISNULL(L.IsDeleted, 0) = 0 
		AND L.AdditionalFilter IS NOT NULL

	UNION ALL

	---------------------------------------------------------------------------------------------------------
	-- UNION 6: LDBCPurchase (Local / LDBC)
	---------------------------------------------------------------------------------------------------------
	SELECT
		L.LoanGenerationDate AS DisbursementDate,
		CPM.customername AS ClientsName,
		GLC.GroupRefNo AS GroupRef,
		ADBranchName = AdBranch.BranchName,
		NonADBranchName = CASE WHEN RTRIM(LTRIM(Branch.BranchName)) = RTRIM(LTRIM(AdBranch.BranchName)) THEN '' ELSE Branch.BranchName END,
		LoanTypeName = EFV.DisplayCode,
		LoanReferenceNo = COALESCE(
			NULLIF(CASE 
				WHEN L.Loannumber LIKE 'LD%' AND CHARINDEX(',', L.Loannumber) = 0 THEN L.Loannumber
				WHEN L.Loannumber LIKE 'LD%' AND CHARINDEX(',', L.Loannumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.Loannumber, 1, CHARINDEX(',', L.Loannumber) - 1)))
				WHEN L.ExternalId LIKE 'LD%' AND CHARINDEX(',', L.ExternalId) = 0 THEN L.ExternalId
				WHEN L.ExternalId LIKE 'LD%' AND CHARINDEX(',', L.ExternalId) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalId, 1, CHARINDEX(',', L.ExternalId) - 1)))
			END, ''),
			NULLIF(CASE 
				WHEN L.Loannumber NOT LIKE 'TF%' AND CHARINDEX(',', L.Loannumber) = 0 AND NULLIF(L.Loannumber, '') IS NOT NULL THEN L.Loannumber
				WHEN L.Loannumber NOT LIKE 'TF%' AND CHARINDEX(',', L.Loannumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.Loannumber, 1, CHARINDEX(',', L.Loannumber) - 1)))
				WHEN L.ExternalId NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalId) = 0 AND NULLIF(L.ExternalId, '') IS NOT NULL THEN L.ExternalId
				WHEN L.ExternalId NOT LIKE 'TF%' AND CHARINDEX(',', L.ExternalId) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.ExternalId, 1, CHARINDEX(',', L.ExternalId) - 1)))
			END, ''),
			CASE 
				WHEN CHARINDEX(',', L.Loannumber) > 0 THEN LTRIM(RTRIM(SUBSTRING(L.Loannumber, 1, CHARINDEX(',', L.Loannumber) - 1)))
				ELSE L.Loannumber 
			END
		),
		Currency = COALESCE(NULLIF(L.CurrencyCode, ''), NULLIF(md.Currency, ''), NULLIF(localb.CURRENCY_CODE, ''), NULLIF(localb.BILL_CCY, ''), 'BDT'),
		DisbursementAmount = COALESCE(NULLIF(L.DisbursedAmount, 0), NULLIF(L.EligibleAmount, 0), NULLIF(L.LimitAmount, 0), NULLIF(localb.ExportLocalBillAmount, 0), 0),
		RateofInterest = COALESCE(NULLIF(L.INTEREST_RATE, 0), NULLIF(L.InterestPercent, 0), NULLIF(L.INT_OS, 0)),
		PresentOutstanding = CASE 
			WHEN l.UBSSyncProcessID = 0 THEN l.DisbursedAmount 
			WHEN l.UBSSyncProcessID = 1 AND l.TOT_OS IS NULL THEN l.DisbursedAmount
			ELSE l.TOT_OS 
		END,
		LoanExpiryDate = COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate),
		OverdueDays = CASE 
			WHEN (CASE WHEN l.UBSSyncProcessID = 0 THEN l.DisbursedAmount 
					   WHEN l.UBSSyncProcessID = 1 AND l.TOT_OS IS NULL THEN l.DisbursedAmount
					   ELSE l.TOT_OS 
				  END) > 0 
				 AND CAST(COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate) AS DATE) < CAST(GETDATE() AS DATE)
				 AND COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate) IS NOT NULL
			THEN DATEDIFF(DAY, COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate), GETDATE())
			ELSE '' 
		END,	
		CPM.CustomerID AS CustomerID,
		ADBranchID = md.ADBranchID,
		NonADBranchID = md.BranchID,
		L.LoanType AS LoanType
	FROM LDBCPurchase L WITH(NOLOCK)
		LEFT JOIN SystemManager..EntityFixedVariables EFV WITH(NOLOCK) ON EFV.entityid = L.LoanType
		LEFT JOIN LocalExportBillInitiationMaster localb WITH(NOLOCK) ON localb.EBIID = L.EBIID
		LEFT JOIN MasterDoc md WITH(NOLOCK) ON md.MasterDocID = l.contractref
		LEFT JOIN LCadvisingregister lcad WITH(NOLOCK) ON lcad.lcreceiveid = L.contractref
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = md.GroupSysID
		LEFT JOIN [SystemManager]..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = ISNULL(L.CustomerID, lcad.customer)
		LEFT JOIN [SystemManager]..contacts applicant WITH(NOLOCK) ON applicant.code = ISNULL(md.Applicant, lcad.applicant)
		LEFT JOIN [SystemManager]..BankProfileBranch Branch WITH(NOLOCK) ON Branch.BranchID = ISNULL(localb.BranchID, lcad.branchid)
		LEFT JOIN [SystemManager]..BankProfileBranch AdBranch WITH(NOLOCK) ON AdBranch.BranchID = ISNULL(glc.ADBranchID, lcad.adbranchid)
	WHERE 
		CONVERT(DATE, L.LoanGenerationDate) BETWEEN @FromDate AND @ToDate
		AND ISNULL(L.IsDeleted, 0) = 0 
		AND L.LoanGenerationDate IS NOT NULL  
		AND L.IsCancelled = 0;
END
GO
