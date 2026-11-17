USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_LoanRegisterPBL]    Script Date: 11/17/2026 03:52:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_LoanRegisterPBL]
@FromDate DATETIME,@ToDate DATETIME
 
AS										
-- SP_RPT_LoanRegisterPBL '2020-10-04' , '2023-10-06'

BEGIN

SELECT DISTINCT
	L.Loancreationdate DisbursementDate,
	CPM.customername AS ClientsName,
	GLC.GroupRefNo AS GroupRef,
	ADBranchName=isnull(AdBranch.BranchName,AdBranch2.BranchName)			  ,
	NonADBranchName	=isnull(Case when Rtrim(Ltrim(isnull(Branch.BranchName,Branch2.BranchName)))=Rtrim(Ltrim(isnull(AdBranch.BranchName,AdBranch2.BranchName))) then '' Else Branch.BranchName END,Case when Rtrim(Ltrim(Branch2.BranchName))=Rtrim(Ltrim(AdBranch2.BranchName)) then '' Else isnull(Branch2.BranchName,Branch2.BranchName) END),
	LoanTypeName = EFV.DisplayCode,
	CASE 
		WHEN L.LoanNo LIKE 'LD%' THEN L.LoanNo
		WHEN L.ExternalID LIKE 'LD%' THEN L.ExternalID
		WHEN L.LoanNo NOT LIKE 'TF%' AND NULLIF(L.LoanNo, '') IS NOT NULL THEN L.LoanNo
		WHEN L.ExternalID NOT LIKE 'TF%' AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
		WHEN NULLIF(L.ACCOUNT_NUMBER, '') IS NOT NULL THEN L.ACCOUNT_NUMBER
		ELSE L.LoanNo
	END AS LoanReferenceNo,
	Currency = COALESCE(NULLIF(L.LoanCurrency, ''), NULLIF(md.Currency, ''), NULLIF(FDAM.Currency, ''), 'BDT'),
	ISNULL(NULLIF(L.LoanAmount, 0), L.BillAmount) AS DisbursementAmount,
	COALESCE(L.INTEREST_RATE, L.RateOnInterest) AS RateofInterest,
	PresentOutstanding=case when l.UBSSyncProcessID=0 
		then l.LoanAmount 
		when l.UBSSyncProcessID=1 and l.AdjustmentAmount=0 
		then l.LoanAmount
		else isnull(l.OutstandingAmount, 0) end,
	COALESCE(L.MATURITY_DATE, L.LoanExpiry) AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.LoanAmount 
		when l.UBSSyncProcessID=1 and l.AdjustmentAmount=0 
		then l.LoanAmount
		else isnull(l.OutstandingAmount, 0) end)>0 and 
		cast(COALESCE(L.MATURITY_DATE, L.LoanExpiry) as date )<cast(GETDATE() as date )
		and COALESCE(L.MATURITY_DATE, L.LoanExpiry) is not null
		then DATEDIFF(day,COALESCE(L.MATURITY_DATE, L.LoanExpiry),GETDATE())
		else '' end,
	 
	CPM.CustomerID AS CustomerID, 
	ADBranchID=	isnull(glc.ADBranchID,r.ADBranchID)			 ,
	NonADBranchID=isnull(glc.bankBranchID,r.BranchID)				 ,
	L.Loanagainst AS LoanType
FROM LoanCreation L
	LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = L.Customer
	LEFT JOIN SystemManager..EntityFixedVariables EFV ON EFV.entityid = L.Loanagainst
	LEFT JOIN BBLCMaster md ON md.BBLCID = L.BBLCID
	LEFT JOIN BBLCRequestMaster r ON r.BBLCID = L.BBLCID
	LEFT JOIN ForeignDocumentAcceptanceMaster FDAM ON FDAM.Billno = L.AdditionalFilter
	LEFT JOIN GroupLC GLC ON GLC.GroupSysID = md.GroupSysID
	left join ImportLCmaster IML on IML.ImportLCID = L.BBLCID
	LEFT join [SystemManager]..BankProfileBranch Branch on Branch.BranchID=glc.bankBranchID
	LEFT join [SystemManager]..BankProfileBranch AdBranch on AdBranch.BranchID=glc.ADBranchID
	LEFT join [SystemManager]..BankProfileBranch Branch2 on Branch2.BranchID=r.BranchID
	LEFT join [SystemManager]..BankProfileBranch AdBranch2 on AdBranch2.BranchID=r.ADBranchID

WHERE 
	CONVERT(DATE,L.LoanCreationDate) BETWEEN @FromDate AND @ToDate and 
	isnull(L.IsDeleted,0)=0  and L.LoanNo is not null and r.isdeleted=0
UNION 


SELECT
	L.ApplyDate DisbursementDate,
	CPM.customername AS ClientsName,
	GGLC.GroupRefNo AS GroupRef,
	ADBranchName=AdBranch.BranchName			  ,
	NonADBranchName	=Case when Rtrim(Ltrim(Branch.BranchName))=Rtrim(Ltrim(AdBranch.BranchName)) then '' Else Branch.BranchName END,
	'Purchase' AS LoanTypeName,
	CASE 
		WHEN L.LoanNumber LIKE 'LD%' THEN L.LoanNumber
		WHEN L.ExternalID LIKE 'LD%' THEN L.ExternalID
		WHEN L.LoanNumber NOT LIKE 'TF%' AND NULLIF(L.LoanNumber, '') IS NOT NULL THEN L.LoanNumber
		WHEN L.ExternalID NOT LIKE 'TF%' AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
		WHEN NULLIF(L.Account_Number, '') IS NOT NULL THEN L.Account_Number
		ELSE L.LoanNumber
	END AS LoanReferenceNo,
	COALESCE(NULLIF(MD.Currency, ''), NULLIF(L.AC_CCY, ''), 'BDT') AS Currency,
	ISNULL(NULLIF(L.DisbursedAmount, 0), L.LoanBasisAmount) AS DisbursementAmount,
	COALESCE(L.InterestRate, NULLIF(L.INT_OS, 0)) AS RateofInterest,
	PresentOutstanding=case when l.UBSSyncProcessID=0 
		then L.DisbursedAmount
		when isnull(len(Isnull(CONVERT(DATE,(Select Max(ll.DateAdded) from [EFA]..CustomerVoucherTransDetails ll where ll.AdditionalFilter='Purchase Discount Foreign Document Master' and ll.CreditAccountNo='503010101' and l.ExternalID=ll.AdditionalMasterID)),CONVERT(DATE, PRS.RealizedDate))),0)<1 then L.DisbursedAmount
		else isnull(l.TOT_OS, 0) end,
	L.MaturityDate AS LoanExpiryDate,
	
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then L.DisbursedAmount
		when isnull(len(Isnull(CONVERT(DATE,(Select Max(ll.DateAdded) from [EFA]..CustomerVoucherTransDetails ll where ll.AdditionalFilter='Purchase Discount Foreign Document Master' and ll.CreditAccountNo='503010101' and l.ExternalID=ll.AdditionalMasterID)),CONVERT(DATE, PRS.RealizedDate))),0)<1 then L.DisbursedAmount
		else isnull(l.TOT_OS, 0) end)>0 and 
		cast(L.MaturityDate as date )<cast(GETDATE() as date )
		and L.MaturityDate is not null
		then DATEDIFF(day,L.MaturityDate,GETDATE())
		else '' end,
	CPM.CustomerID AS CustomerID,
	ADBranch.ADBranchID AS ADBranchID,
	Branch.BranchID AS NonADBranchID,
	'Purchase' AS LoanType
FROM PurchaseDiscountForeignDocumentMaster L
	LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = L.CustomerID
	LEFT JOIN Masterdoc MD ON MD.MasterDocID = L.MasterDocID
	LEFT JOIN GROUPLC GGLC ON GGLC.GroupSysID = MD.GroupSysID
	LEFT JOIN SystemManager..BankProfileBranch Branch with(nolock) ON  Branch.branchid = L.BranchID
	LEFT JOIN SystemManager..BankProfileBranch ADBranch with(nolock) ON  ADBranch.branchid = L.ADBranchID
	LEFT JOIN (
		                    SELECT M.BillRefNo, MAX(M.Date) RealizedDate, SUM(M.ProceedsRecvd) RealizedValue
		                    FROM
		                    (
		                       SELECT P.BillRefNo, MAX(P.Date) Date, MAX(P.ProceedsRecvd) ProceedsRecvd
		                       FROM PRSCreationDistributionDetails P
		                       WHERE P.IsDeleted = 0 AND P.PRSNCADID != 'NOT_NCA'
		                       GROUP BY P.BillRefNo, P.Date
		                    ) M
		                    GROUP BY M.BillRefNo
	                    ) PRS ON PRS.BillRefNo = l.EBIID
WHERE 
	CONVERT(DATE,L.ApplyDate) BETWEEN @FromDate AND @ToDate and
	isnull(L.IsDeleted,0)=0 and isnull(L.IsExportLoan,0)=0 and L.IsPurchaseLoanType=1 and L.LoanNumber is not null
UNION
SELECT
	L.ApplyDate DisbursementDate,
	CPM.customername AS ClientsName,
	GGLC.GroupRefNo AS GroupRef,
	ADBranchName=AdBranch.BranchName			  ,
	NonADBranchName	=Case when Rtrim(Ltrim(Branch.BranchName))=Rtrim(Ltrim(AdBranch.BranchName)) then '' Else Branch.BranchName END,
	'Discount' AS LoanTypeName,
	CASE 
		WHEN L.LoanNumber LIKE 'LD%' THEN L.LoanNumber
		WHEN L.ExternalID LIKE 'LD%' THEN L.ExternalID
		WHEN L.LoanNumber NOT LIKE 'TF%' AND NULLIF(L.LoanNumber, '') IS NOT NULL THEN L.LoanNumber
		WHEN L.ExternalID NOT LIKE 'TF%' AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
		WHEN NULLIF(L.Account_Number, '') IS NOT NULL THEN L.Account_Number
		ELSE L.LoanNumber
	END AS LoanReferenceNo,
	COALESCE(NULLIF(MD.Currency, ''), NULLIF(L.AC_CCY, ''), 'BDT') AS Currency,
	ISNULL(NULLIF(L.DisbursedAmount, 0), L.LoanBasisAmount) AS DisbursementAmount,
	COALESCE(L.InterestRate, NULLIF(L.INT_OS, 0)) AS RateofInterest,
	PresentOutstanding=case when l.UBSSyncProcessID=0 
		then L.DisbursedAmount
		when isnull(len(CONVERT(DATE,(Select Max(ll.DateAdded) from [EFA]..CustomerVoucherTransDetails ll where ll.AdditionalFilter='Purchase Discount Foreign Document Master' and ll.CreditAccountNo='503010101' and l.ExternalID=ll.AdditionalMasterID))),0)<1 then L.DisbursedAmount
		else isnull(l.TOT_OS, 0) end,
	L.MaturityDate AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then L.DisbursedAmount
		when isnull(len(CONVERT(DATE,(Select Max(ll.DateAdded) from [EFA]..CustomerVoucherTransDetails ll where ll.AdditionalFilter='Purchase Discount Foreign Document Master' and ll.CreditAccountNo='503010101' and l.ExternalID=ll.AdditionalMasterID))),0)<1 then L.DisbursedAmount
		else isnull(l.TOT_OS, 0) end)>0 and 
		cast(L.MaturityDate as date )<cast(GETDATE() as date )
		and L.MaturityDate is not null
		then DATEDIFF(day,L.MaturityDate,GETDATE())
		else '' end,	
	CPM.CustomerID AS CustomerID,
	ADBranch.ADBranchID AS ADBranchID,
	Branch.BranchID AS NonADBranchID,
	'Discount' AS LoanType
FROM PurchaseDiscountForeignDocumentMaster L
	LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = L.CustomerID
	LEFT JOIN Masterdoc MD ON MD.MasterDocID = L.MasterDocID
	LEFT JOIN GROUPLC GGLC ON GGLC.GroupSysID = MD.GroupSysID
	LEFT JOIN SystemManager..BankProfileBranch Branch with(nolock) ON  Branch.branchid = L.BranchID
	LEFT JOIN SystemManager..BankProfileBranch ADBranch with(nolock) ON  ADBranch.branchid = L.ADBranchID
WHERE 
	CONVERT(DATE,L.ApplyDate) BETWEEN @FromDate AND @ToDate and
	isnull(L.IsDeleted,0)=0 and isnull(L.IsExportLoan,0)=0 and isnull(L.IsPurchaseLoanType,0)=0 and L.LoanNumber is not null
UNION

SELECT
	L.ApplyDate DisbursementDate,
	CPM.customername AS ClientsName,
	isnull(GGLC.GroupRefNo,GLC.GroupRefNo) AS GroupRef,
	ADbpb.BranchName AS ADBranchName,
	NonADbpb.BranchName AS NonADBranchName,
	Case when L.PurchaseLoanTypeID = 'DemandLoan' Then 'Demand Loan'
	     when L.PurchaseLoanTypeID is null Then 'Demand Loan'
		 Else L.PurchaseLoanTypeID END AS LoanTypeName,
	CASE 
		WHEN L.LoanNumber LIKE 'LD%' THEN L.LoanNumber
		WHEN L.ExternalID LIKE 'LD%' THEN L.ExternalID
		WHEN L.LoanNumber NOT LIKE 'TF%' AND NULLIF(L.LoanNumber, '') IS NOT NULL THEN L.LoanNumber
		WHEN L.ExternalID NOT LIKE 'TF%' AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
		WHEN NULLIF(L.Account_Number, '') IS NOT NULL THEN L.Account_Number
		ELSE L.LoanNumber
	END AS LoanReferenceNo,
	COALESCE(NULLIF(MD2.Currency, ''), NULLIF(EBM.CURRENCY_CODE, ''), NULLIF(EBM.BILL_CCY, ''), NULLIF(L.AC_CCY, ''), 'BDT') AS Currency,
	ISNULL(NULLIF(L.DisbursedAmount, 0), L.LoanBasisAmount) AS DisbursementAmount,
	COALESCE(L.InterestRate, NULLIF(L.INT_OS, 0)) AS RateofInterest,
	PresentOutstanding=case when l.UBSSyncProcessID=0 
		then l.DisbursedAmount 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.DisbursedAmount
		else l.TOT_OS end,
	L.MaturityDate AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.DisbursedAmount 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.DisbursedAmount
		else l.TOT_OS end)>0 and 
		cast(L.MaturityDate as date )<cast(GETDATE() as date )
		and L.MaturityDate is not null
		then DATEDIFF(day,L.MaturityDate,GETDATE())
		else '' end
	,CPM.CustomerID AS CustomerID,
	ADbpb.ADBranchID AS ADBranchID,
	NonADbpb.BranchID AS NonADBranchID,
	Case When L.PurchaseLoanTypeID is Null THEN 'Demand Loan'
	     Else L.PurchaseLoanTypeID END AS LoanType
FROM PurchaseDiscountForeignDocumentMaster L
	LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = L.CustomerID
	LEFT JOIN PurchaseDiscountForeignDocumentChild LL ON L.PDFDMID = LL.PDFDMID
    LEFT JOIN GROUPLC GGLC ON GGLC.GroupSysID = LL.GroupSysID
	LEFT JOIN ExportBillInitiationMaster EBM ON EBM.EBIID = LL.EBIID
	LEFT JOIN Masterdoc MD2 ON MD2.MasterDocID = EBM.MasterDocID
	LEFT JOIN GroupLC GLC ON GLC.GroupSysID = MD2.GroupSysID
	LEFT JOIN SystemManager..BankProfileBranch NonADbpb with(nolock) ON  NonADbpb.branchid = L.BranchID
	LEFT JOIN SystemManager..BankProfileBranch ADbpb with(nolock) ON  ADbpb.branchid = L.ADBranchID
WHERE 
	CONVERT(DATE,L.ApplyDate) BETWEEN @FromDate AND @ToDate and
	isnull(L.IsDeleted,0)=0 and isnull(L.IsCancelled,0)=0 and isnull(L.IsExportLoan,0)=1 and L.LoanNumber is not null
UNION
SELECT
	L.PCDisburseDate DisbursementDate,
	CPM.customername AS ClientsName,
	GLC.GroupRefNo AS GroupRef,
	ADBranchName=AdBranch.BranchName			  ,
	NonADBranchName	=Case when Rtrim(Ltrim(Branch.BranchName))=Rtrim(Ltrim(AdBranch.BranchName)) then '' Else Branch.BranchName END,
	EFV.DisplayCode AS LoanTypeName,
	CASE 
		WHEN L.AdditionalFilter LIKE 'LD%' THEN L.AdditionalFilter
		WHEN L.ExternalID LIKE 'LD%' THEN L.ExternalID
		WHEN L.AdditionalFilter NOT LIKE 'TF%' AND NULLIF(L.AdditionalFilter, '') IS NOT NULL THEN L.AdditionalFilter
		WHEN L.ExternalID NOT LIKE 'TF%' AND NULLIF(L.ExternalID, '') IS NOT NULL THEN L.ExternalID
		ELSE L.AdditionalFilter
	END AS LoanReferenceNo,
	'BDT' AS Currency,
	ISNULL(NULLIF(L.PCAmountTK, 0), L.PCAmount) AS DisbursementAmount,
	COALESCE(L.InterestRate, L.PCorSODInterestAmount, NULLIF(L.INT_OS, 0)) AS RateofInterest,
	PresentOutstanding=CASE WHEN L.TransactionDate is null THEN L.PCAmountTK                      
                    ELSE L.TOT_OS END,
	COALESCE(
		L.MATURITY_DATE,
		L.ExpiryDate,
		L.InterestDueDate,
		CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, L.PCDisburseDate) END,
		MD.ExpiryDate
	) AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.PCAmountTK 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.PCAmountTK
		else l.TOT_OS end)>0 and 
		cast(COALESCE(L.MATURITY_DATE, L.ExpiryDate, L.InterestDueDate, CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, L.PCDisburseDate) END, MD.ExpiryDate) as date )<cast(GETDATE() as date )
		and COALESCE(L.MATURITY_DATE, L.ExpiryDate, L.InterestDueDate, CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, L.PCDisburseDate) END, MD.ExpiryDate) is not null
		then DATEDIFF(day,COALESCE(L.MATURITY_DATE, L.ExpiryDate, L.InterestDueDate, CASE WHEN ISNULL(L.TenorDays, 0) > 0 THEN DATEADD(DAY, L.TenorDays, L.PCDisburseDate) END, MD.ExpiryDate),GETDATE())
		else '' end,	
	CPM.CustomerID AS CustomerID,
	GLC.ADBranchID AS ADBranchID,
	GLC.BankBranchID AS NonADBranchID,
	L.LoanType AS LoanType
FROM PCDisbursementMaster L
	LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = L.CustomerID
	LEFT JOIN MasterDoc MD ON L.MasterDocID = MD.MasterDocID
	LEFT JOIN SystemManager..EntityFixedVariables EFV ON EFV.entityid = L.LoanType
	LEFT JOIN GroupLC GLC on GLC.GroupSysID=L.GrouprefID
	LEFT join [SystemManager]..BankProfileBranch Branch on Branch.BranchID=glc.bankBranchID
	LEFT join [SystemManager]..BankProfileBranch AdBranch on AdBranch.BranchID=glc.ADBranchID
WHERE CONVERT(DATE,L.PCDisburseDate) BETWEEN @FromDate AND @ToDate
	and isnull(L.IsDeleted,0)=0 and L.AdditionalFilter is not null
UNION 

SELECT
	L.LoanGenerationDate DisbursementDate,
	CPM.customername AS ClientsName,
	GLC.GroupRefNo AS GroupRef,
	ADBranchName=AdBranch.BranchName					  ,
	NonADBranchName	=Case when Rtrim(Ltrim(Branch.BranchName))=Rtrim(Ltrim(AdBranch.BranchName)) then '' Else Branch.BranchName END,
	EFV.DisplayCode AS LoanTypeName,
	CASE 
		WHEN L.Loannumber LIKE 'LD%' THEN L.Loannumber
		WHEN L.ExternalId LIKE 'LD%' THEN L.ExternalId
		WHEN L.Loannumber NOT LIKE 'TF%' AND NULLIF(L.Loannumber, '') IS NOT NULL THEN L.Loannumber
		WHEN L.ExternalId NOT LIKE 'TF%' AND NULLIF(L.ExternalId, '') IS NOT NULL THEN L.ExternalId
		ELSE L.Loannumber
	END AS LoanReferenceNo,
	COALESCE(NULLIF(L.CurrencyCode, ''), NULLIF(md.Currency, ''), 'BDT') AS Currency,
	L.DisbursedAmount AS DisbursementAmount,
	COALESCE(L.INTEREST_RATE, NULLIF(L.INT_OS, 0)) AS RateofInterest,
	PresentOutstanding=case when l.UBSSyncProcessID=0 
		then l.DisbursedAmount 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.DisbursedAmount
		else l.TOT_OS end,
	COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate) AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.DisbursedAmount 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.DisbursedAmount
		else l.TOT_OS end)>0 and 
		cast(COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate) as date )<cast(GETDATE() as date )
		and COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate) is not null
		then DATEDIFF(day,COALESCE(L.MATURITY_DATE, localb.MaturityDate, md.ExpiryDate),GETDATE())
		else '' end,	
	CPM.CustomerID AS CustomerID,
	ADBranchID=	md.ADBranchID			 ,
	NonADBranchID=md.BranchID				 ,
	L.LoanType AS LoanType
FROM LDBCPurchase L

	LEFT JOIN SystemManager..EntityFixedVariables EFV ON EFV.entityid = L.LoanType
	LEFT JOIN LocalExportBillInitiationMaster localb on localb.EBIID = L.EBIID
	Left Join MasterDoc md on md.MasterDocID=l.contractref
	LEFT JOIN LCadvisingregister lcad on lcad.lcreceiveid = L.contractref
    LEFT JOIN GroupLC GLC ON GLC.GroupSysID = md.GroupSysID
	LEFT join [SystemManager]..CustomerProfileMaster CPM on CPM.CustomerID=isnull(L.CustomerID,lcad.customer)
	LEFT join [SystemManager]..contacts applicant on applicant.code=isnull(md.Applicant,lcad.applicant)
	LEFT join [SystemManager]..BankProfileBranch Branch on Branch.BranchID=isnull(localb.BranchID,lcad.branchid)
	LEFT join [SystemManager]..BankProfileBranch AdBranch on AdBranch.BranchID=isnull(glc.ADBranchID,lcad.adbranchid)

WHERE CONVERT(DATE,L.LoanGenerationDate) BETWEEN @FromDate AND @ToDate
	and isnull(L.IsDeleted,0)=0 and L.LoanGenerationDate is not null  and L.IsCancelled = 0
END
GO
