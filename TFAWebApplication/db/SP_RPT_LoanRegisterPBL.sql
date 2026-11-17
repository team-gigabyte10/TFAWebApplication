USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_LoanRegisterPBL]    Script Date: 11/17/2026 12:29:55 PM ******/
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
	--LoanTypeName = CASE WHEN L.LoanAgainst = 'LoanType/FLAB' THEN 'FLAB'
	--WHEN L.LoanAgainst = 'LoanType/IBPC' THEN 'IBPC'
	--WHEN L.LoanAgainst = 'LoanType/LEDF' THEN 'LEDF'
	--WHEN L.LoanAgainst = 'LoanType/PAID' THEN 'PAID'
	--ELSE EFV.DisplayCode
	--END,
	LoanTypeName = EFV.DisplayCode,
	L.LoanNo + ', ' + isnull(L.ExternalID, '') AS LoanReferenceNo,
	--Currency = Case When FDAM.Billno is not NULL Then FDAM.Currency
	--		   Else L.Currency END,
	Currency = L.LoanCurrency,
	L.LoanAmount AS DisbursementAmount,
	L.INTEREST_RATE  AS RateofInterest,
	 PresentOutstanding=case when l.UBSSyncProcessID=0 
		then l.LoanAmount 
		when l.UBSSyncProcessID=1 and l.AdjustmentAmount=0 
		then l.LoanAmount
		else isnull(l.OutstandingAmount, 0) end,
	L.MATURITY_DATE AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.LoanAmount 
		when l.UBSSyncProcessID=1 and l.AdjustmentAmount=0 
		then l.LoanAmount
		else isnull(l.OutstandingAmount, 0) end)>0 and 
		cast(L.MATURITY_DATE as date )<cast(GETDATE() as date )
		and L.MATURITY_DATE is not null
		then DATEDIFF(day,L.MATURITY_DATE,GETDATE())
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
	L.LoanNumber + ', ' + isnull(L.ExternalID, '') AS LoanReferenceNo,
	MD.Currency AS Currency,
	L.DisbursedAmount AS DisbursementAmount,
	L.INT_OS  AS RateofInterest,
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
	L.LoanNumber + ', ' + isnull(L.ExternalID, '') AS LoanReferenceNo,
	MD.Currency AS Currency,
	L.DisbursedAmount AS DisbursementAmount,
	L.INT_OS  AS RateofInterest,
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
	L.LoanNumber + ', ' + isnull(L.ExternalID, '')AS LoanReferenceNo,
	MD2.Currency AS Currency,
	L.DisbursedAmount AS DisbursementAmount,
	null  AS RateofInterest,
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
	 ,	CPM.CustomerID AS CustomerID,
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
	----delete--
	--LEFT JOIN (SELECT   B.BranchID ,B.BranchName from SystemManager..BankProfileBranch B
	--	INNER JOIN (SELECT BranchID FROM SystemManager..CustomerBranchMap GROUP BY BranchID) C ON B.BranchID = C.BranchID
	--	WHERE IsADCode = 0) NonADbpb ON NonADbpb.BranchID = L.BranchID
	--LEFT JOIN (SELECT * FROM SystemManager..BankProfileBranch WHERE IsADCode = 1) ADbpb ON ADbpb.ADBranchID = L.BranchID
	----delete--
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
	L.AdditionalFilter + ', ' + isnull(L.ExternalID, '') AS LoanReferenceNo,
	'BDT' AS Currency,
	L.PCAmountTK AS DisbursementAmount,
	null  AS RateofInterest,
	 PresentOutstanding=CASE WHEN L.TransactionDate is  null THEN L.PCAmountTK                      
                    ELSE L.TOT_OS END,
	L.MATURITY_DATE AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.PCAmountTK 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.PCAmountTK
		else l.TOT_OS end)>0 and 
		cast(L.MATURITY_DATE as date )<cast(GETDATE() as date )
		and L.MATURITY_DATE is not null
		then DATEDIFF(day,L.MATURITY_DATE,GETDATE())
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
	L.Loannumber + ', ' + isnull(L.ExternalId, '') AS LoanReferenceNo,
	L.CurrencyCode AS Currency,
	L.DisbursedAmount AS DisbursementAmount,
	L.INTEREST_RATE  AS RateofInterest,
	 PresentOutstanding=case when l.UBSSyncProcessID=0 
		then l.DisbursedAmount 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.DisbursedAmount
		else l.TOT_OS end,
	L.MATURITY_DATE AS LoanExpiryDate,
	OverdueDays=Case when (case when l.UBSSyncProcessID=0 
		then l.DisbursedAmount 
		when l.UBSSyncProcessID=1 and l.TOT_OS is null 
		then l.DisbursedAmount
		else l.TOT_OS end)>0 and 
		cast(L.MATURITY_DATE as date )<cast(GETDATE() as date )
		and L.MATURITY_DATE is not null
		then DATEDIFF(day,L.MATURITY_DATE,GETDATE())
		else '' end,	
	CPM.CustomerID AS CustomerID,
	ADBranchID=	md.ADBranchID			 ,
	NonADBranchID=md.BranchID				 ,
	L.LoanType AS LoanType --EFV/23/45
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