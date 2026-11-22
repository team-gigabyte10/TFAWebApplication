USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[RTGSRegisterPBL]    Script Date: 11/18/2026 11:57:14 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Or Alter Proc [dbo].[RTGSRegisterPBL]
@FromDate date,@ToDate date
as
Begin
----  Exec RTGSRegisterPBL '2024-01-01','2025-10-01'
Declare @USDRate numeric(18,4)
Select @USDRate=ConvertFactor from [SystemManager]..CurrencyLatestRate  with(nolock) where CurrencyCode='USD' and RateFor='BC SELLING'


Select distinct  
rDate=r.RequestDate,
RTGSNo=i.BBLCNo,
Amount=isnull(Isnull(b.BBLCAmount,c.ImportLCAmount),r.ProposedAmount),
Applicant=cus.CustomerName,
Benificiary=Isnull(beni.Name ,r.Benificiary),
Commodity=com.CommodityName,
FTNo=null,
Inputter=Isnull(r.AddedBy,r.MakeBy),
SalesContractNo=null
																													
from BBLCRequestMaster r with(nolock)
left join BBLCIssuance i with(nolock) on r.BBLCID=i.BBLCID
Left Join BBLCMaster b with(nolock) on b.BBLCID=r.BBLCID
left join ImportLCMaster c with(nolock) on c.ImportLCID=r.BBLCID
Left Join [SystemManager]..Contacts beni with(nolock) on beni.code=r.Benificiary
Left Join [SystemManager]..CommodityMaster com with(nolock) on com.CommodityMasterID=r.Commodity
LEFT JOIN [SystemManager]..CustomerProfileMaster cus with(nolock) on cus.CustomerID=r.CustomerID
LEFT JOIN [SystemManager]..CurrencyLatestRate clr  with(nolock) on clr.CurrencyCode=r.Currency and clr.RateFor='BC SELLING'
where
CONVERT(DATE,r.RequestDate) Between @FromDate and @ToDate  
	and r.IsDeleted = 0 and r.IsCancelled=0
	and i.LCode in('16','32','BBLC16','BBLC32','CASH16','CASH32','CASHLC16','CASHLC32')
--order by r.RequestDate desc
End
GO




USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[BTBAcceptedLiabilityCoveragePBL]    Script Date: 11/18/2026 11:58:36 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Or Alter Proc [dbo].[BTBAcceptedLiabilityCoveragePBL]
@FromDate date,@ToDate date
as
Begin
SET NOCOUNT ON;

-- Exec BTBAcceptedLiabilityCoveragePBL '2024-01-01', '2025-10-01'
Declare @USDRate numeric(18,4)
Select @USDRate=ConvertFactor from [SystemManager]..CurrencyLatestRate with(nolock) where CurrencyCode='USD' and RateFor='BC SELLING'
IF ISNULL(@USDRate, 0) = 0 SET @USDRate = 120.00;

-- 1. All relevant GroupLC records
WITH GroupBase AS (
    SELECT DISTINCT
        g.GroupSysID,
        g.GroupRefNo,
        g.CustomerID,
        g.CurrencyCode,
        ISNULL(g.GroupAmount, 0) AS GroupAmount,
        CONVERT(DATE, g.DateAdded) AS JobDate
    FROM GroupLC g WITH(NOLOCK)
    WHERE g.IsDeleted = 0
      AND (
          CONVERT(DATE, g.DateAdded) BETWEEN @FromDate AND @ToDate
          OR EXISTS (
              SELECT 1 FROM BBLCMaster bb WITH(NOLOCK) 
              WHERE bb.GroupSysID = g.GroupSysID AND bb.IsDeleted = 0 AND bb.IsCancelled = 0
                AND CONVERT(DATE, bb.IssueDate) BETWEEN @FromDate AND @ToDate
          )
          OR EXISTS (
              SELECT 1 FROM BBLCRequestMaster b WITH(NOLOCK)
              WHERE b.GroupSysID = g.GroupSysID AND b.IsDeleted = 0 AND b.IsCancelled = 0
                AND CONVERT(DATE, b.RequestDate) BETWEEN @FromDate AND @ToDate
          )
      )
),
-- 2. BTB Accepted Liability per Group
BTBAccepted AS (
    SELECT 
        bb.GroupSysID,
        SUM(
            CASE 
                WHEN ISNULL(fd.Currency, 'USD') = 'USD' THEN ISNULL(fd.BillAmount, 0)
                ELSE (ISNULL(fd.BillAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
            END
        ) AS BTBAcceptedliability
    FROM ForeignDocumentAcceptanceMaster fd WITH(NOLOCK)
    INNER JOIN BBLCMaster bb WITH(NOLOCK) ON bb.BBLCID = fd.BBLCID
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = fd.Currency AND clr.RateFor = 'BC SELLING'
    WHERE fd.IsDeleted = 0 
      AND fd.IsCancelled = 0
      AND bb.IsDeleted = 0
      AND bb.IsCancelled = 0
    GROUP BY bb.GroupSysID
),
-- 3. TT and CAD Issued per Group
TTCAD AS (
    SELECT 
        b.GroupSysID,
        SUM(CASE WHEN b.ReqPaymentMethod LIKE '%TT%' THEN 
                CASE WHEN ISNULL(b.Currency, 'USD') = 'USD' THEN ISNULL(b.ProposedAmount, 0)
                     ELSE (ISNULL(b.ProposedAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate END
            ELSE 0 END) AS TTIssued,
        SUM(CASE WHEN b.ReqPaymentMethod LIKE '%CAD%' THEN 
                CASE WHEN ISNULL(b.Currency, 'USD') = 'USD' THEN ISNULL(b.ProposedAmount, 0)
                     ELSE (ISNULL(b.ProposedAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate END
            ELSE 0 END) AS CADIssued
    FROM BBLCRequestMaster b WITH(NOLOCK)
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = b.Currency AND clr.RateFor = 'BC SELLING'
    WHERE b.IsDeleted = 0 AND b.IsCancelled = 0
    GROUP BY b.GroupSysID
),
-- 4. BTB Bills Paid Already per Group
BTBPaid AS (
    SELECT 
        bb.GroupSysID,
        SUM(
            CASE 
                WHEN ISNULL(pm.Currency, 'USD') = 'USD' THEN ISNULL(pm.PaymentAmount, 0)
                ELSE (ISNULL(pm.PaymentAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
            END
        ) AS BTBBillsPaidAlready
    FROM ForeignDocumentPaymentMaster pm WITH(NOLOCK)
    INNER JOIN ForeignDocumentAcceptanceMaster fd WITH(NOLOCK) ON fd.FDAID = pm.FDAID
    INNER JOIN BBLCMaster bb WITH(NOLOCK) ON bb.BBLCID = fd.BBLCID
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = pm.Currency AND clr.RateFor = 'BC SELLING'
    WHERE pm.IsDeleted = 0 AND fd.IsDeleted = 0 AND fd.IsCancelled = 0
    GROUP BY bb.GroupSysID
),
-- 5. Export Bills / Receivables (Unrealized Export Bills) per Group
ExportBills AS (
    SELECT 
        MD.GroupSysID,
        SUM(
            CASE 
                WHEN ISNULL(EBI.CURRENCY_CODE, 'USD') = 'USD' THEN ISNULL(EBI.ExportBillAmount, 0)
                ELSE (ISNULL(EBI.ExportBillAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
            END
        ) AS TotalBillAmountUSD,
        SUM(
            CASE 
                WHEN (ISNULL(EBI.ExportBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) > 0 THEN
                    CASE 
                        WHEN ISNULL(EBI.CURRENCY_CODE, 'USD') = 'USD' THEN (ISNULL(EBI.ExportBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0))
                        ELSE ((ISNULL(EBI.ExportBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                    END
                ELSE 0 
            END
        ) AS ReceivablesUSD
    FROM ExportBillInitiationMaster EBI WITH(NOLOCK)
    INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = EBI.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = EBI.CURRENCY_CODE AND clr.RateFor = 'BC SELLING'
    LEFT JOIN (
        SELECT BillRefNo, SUM(ISNULL(ProceedsRecvd, 0)) AS ProceedsRecvd
        FROM PRSCreationDistributionDetails WITH(NOLOCK)
        WHERE IsDeleted = 0
        GROUP BY BillRefNo
    ) Realized ON Realized.BillRefNo = EBI.EBIID
    WHERE EBI.IsDeleted = 0 AND ISNULL(EBI.IsCancelled, 0) = 0 AND EBI.ExportBillNo IS NOT NULL
    GROUP BY MD.GroupSysID

    UNION ALL

    SELECT 
        MD.GroupSysID,
        SUM(
            CASE 
                WHEN ISNULL(LEBI.CURRENCY_CODE, 'USD') = 'USD' THEN ISNULL(LEBI.ExportLocalBillAmount, 0)
                ELSE (ISNULL(LEBI.ExportLocalBillAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
            END
        ) AS TotalBillAmountUSD,
        SUM(
            CASE 
                WHEN (ISNULL(LEBI.ExportLocalBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) > 0 THEN
                    CASE 
                        WHEN ISNULL(LEBI.CURRENCY_CODE, 'USD') = 'USD' THEN (ISNULL(LEBI.ExportLocalBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0))
                        ELSE ((ISNULL(LEBI.ExportLocalBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                    END
                ELSE 0 
            END
        ) AS ReceivablesUSD
    FROM LocalExportBillInitiationMaster LEBI WITH(NOLOCK)
    INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = LEBI.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = LEBI.CURRENCY_CODE AND clr.RateFor = 'BC SELLING'
    LEFT JOIN (
        SELECT BillRefNo, SUM(ISNULL(ProceedsRecvd, 0)) AS ProceedsRecvd
        FROM PRSCreationDistributionDetails WITH(NOLOCK)
        WHERE IsDeleted = 0
        GROUP BY BillRefNo
    ) Realized ON Realized.BillRefNo = LEBI.EBIID
    WHERE LEBI.IsDeleted = 0 AND ISNULL(LEBI.IsCancelled, 0) = 0 AND LEBI.ExportLocalBillNo IS NOT NULL
    GROUP BY MD.GroupSysID
),
ExportBillSummary AS (
    SELECT 
        GroupSysID,
        SUM(TotalBillAmountUSD) AS TotalBillAmountUSD,
        SUM(ReceivablesUSD) AS ReceivablesUSD
    FROM ExportBills
    GROUP BY GroupSysID
),
-- 6. Stock In Hand per Group
StockSummary AS (
    SELECT 
        spu.GroupSysID,
        SUM(
            CASE 
                WHEN ISNULL(spu.Currency, 'USD') = 'USD' 
                    THEN (ISNULL(spu.Fabrics_Raw_Marerials, 0) + ISNULL(spu.Accessories, 0) + ISNULL(spu.Work_In_Process, 0) + ISNULL(spu.Finished_Goods, 0))
                ELSE ((ISNULL(spu.Fabrics_Raw_Marerials, 0) + ISNULL(spu.Accessories, 0) + ISNULL(spu.Work_In_Process, 0) + ISNULL(spu.Finished_Goods, 0)) * ISNULL(clr.ConvertFactor, 1)) / @USDRate
            END
        ) AS StockInhand
    FROM StockPositionUpload spu WITH(NOLOCK)
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = spu.Currency AND clr.RateFor = 'BC SELLING'
    WHERE spu.IsDeleted = 0
    GROUP BY spu.GroupSysID
),
-- 7. BBLC Contracts summary
BBLCSummary AS (
    SELECT 
        bb.GroupSysID,
        STRING_AGG(CAST(bb.BBLCNo AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY bb.BBLCNo) AS SalesContractNo,
        SUM(
            CASE 
                WHEN ISNULL(bb.Currency, 'USD') = 'USD' THEN ISNULL(bb.BBLCAmount, 0)
                ELSE (ISNULL(bb.BBLCAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
            END
        ) AS TotalSalesContractvalue
    FROM BBLCMaster bb WITH(NOLOCK)
    LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
        ON clr.CurrencyCode = bb.Currency AND clr.RateFor = 'BC SELLING'
    WHERE bb.IsDeleted = 0 AND bb.IsCancelled = 0
    GROUP BY bb.GroupSysID
)
SELECT 
    JobRefNo                 = gb.GroupRefNo,
    ExportersName            = cus.CustomerName,
    oDate                    = gb.JobDate,
    BTBAcceptedliability     = ISNULL(ba.BTBAcceptedliability, 0),
    TTIssued                 = ISNULL(tc.TTIssued, 0),
    CADIssued                = ISNULL(tc.CADIssued, 0),
    TotalLiability           = ISNULL(ba.BTBAcceptedliability, 0) + ISNULL(tc.TTIssued, 0) + ISNULL(tc.CADIssued, 0),
    BTBBillsPaidAlready      = ISNULL(bp.BTBBillsPaidAlready, 0),
    JobValue                 = gb.GroupAmount,
    SalesContractNo          = bblc.SalesContractNo,
    TotalSalesContractvalue  = ISNULL(bblc.TotalSalesContractvalue, 0),
    ExportToBeMade           = CASE 
                                 WHEN (gb.GroupAmount - ISNULL(ebs.TotalBillAmountUSD, 0)) > 0 
                                     THEN (gb.GroupAmount - ISNULL(ebs.TotalBillAmountUSD, 0)) 
                                 ELSE 0 
                               END,
    Receivables              = ISNULL(ebs.ReceivablesUSD, 0),
    StockInhand              = ISNULL(stk.StockInhand, 0),
    gb.CustomerID
FROM GroupBase gb
LEFT JOIN [SystemManager]..CustomerProfileMaster cus WITH(NOLOCK) ON cus.CustomerID = gb.CustomerID
LEFT JOIN BTBAccepted ba ON ba.GroupSysID = gb.GroupSysID
LEFT JOIN TTCAD tc ON tc.GroupSysID = gb.GroupSysID
LEFT JOIN BTBPaid bp ON bp.GroupSysID = gb.GroupSysID
LEFT JOIN ExportBillSummary ebs ON ebs.GroupSysID = gb.GroupSysID
LEFT JOIN StockSummary stk ON stk.GroupSysID = gb.GroupSysID
LEFT JOIN BBLCSummary bblc ON bblc.GroupSysID = gb.GroupSysID
ORDER BY gb.GroupRefNo ASC
End
GO


USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spLocalExportBillRealizationRegisterPBL]    Script Date: 11/18/2026 12:00:39 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Or Alter PROC [dbo].[spLocalExportBillRealizationRegisterPBL] 
	@FromDate date, @ToDate date
AS
	-- spLocalExportBillRealizationRegisterPBL '2024-08-01','2025-03-03'
BEGIN  
	DECLARE @USDRate DECIMAL(18,4)
	SELECT  @USDRate = ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) WHERE RateFor = 'BC SELLING' AND CurrencyCode='USD'

	Select
		BPB.BranchName,
		LEB.ExternalID T24Reference,
		CPM.CustomerName + ', ' + ISNULL(CPM.CustomerAddress, '') ExporterNameAddr,
		CPM.CIF CustomerID,
		'' ImporterBankBranch,
		MD.LCNo LCNumber, 
		PUR.StartDate DateOfDiscounting,
		LEB.CURRENCY_CODE Currency,
		LEB.ExportLocalBillAmount DocumentAmount,
		'' ReceivedAmount,
		EBM.MaturityDate DueDate,
		PAY.CreditDate PaymentDate,
		'' OverdueDay,
		PUR.LoanNumber LDNumber,
		LEB.ExportLocalBillNo IDBCNumber,
		LEB.BillGenerationDate IDBCDate,
		'' AitInlandBills,
		MD.LCAmount LCValue,
		MD.DateOfLien LCDate,
		LEB.ExportLocalBillAmount * CLR.ConvertFactor BillValueEquivalentBDT,
		PRSM.RealizationAmount * CLR.ConvertFactor RealizedValueEquivalentBDTOnRealizationDate,
		'' CustomerTypeLTDOthethanLTD,
		'' StatusRegularReversed,
		(LEB.ExportLocalBillAmount * CLR.ConvertFactor)/@USDRate BillValueEquivalentUSD,
		PRSM.Currency RealizationCurrency,
		PRSM.RealizationAmount * CLR.ConvertFactor EquivalentRealizationAmountInBDT,
		(PRSM.RealizationAmount * CLR.ConvertFactor)/@USDRate EquivalentRealizationAmountInUSD,
		LEB.AddedBy Inputter,
		LEB.CheckBy Authorizer,
		(LEB.ExportLocalBillAmount * CLR.ConvertFactor)/@USDRate EquivelentBillAmountUSD,
		Commo.CommodityName,
		EBM.AcceptanceReceivedOnDate AcceptanceDate,
		EBM.MaturityDate MaturityDate,
		Issue.Name IssuingBankName,
		IssueBranch.Name IssuingBranch,
		IssueBranch.AgentName IssuingBankADCode,
		'' BangladeshBankAcceptanceID,
		tenor.DisplayCode LCTypeSightOrDeffered,
		LEB.TENOR_DAYS Tenor,
		'' AcceptanceCalculationBasis,
		'' ReversalStatus,
		'' PurchaseStatus,
		'' BangladeshBankPaymentID,
		'' PRCIssueStatus,
		'' BBPRCID,
		'' EchangeRateAppliedOnRealizaiton,
		'' LBCNo
	FROM LocalExportBillInitiationMaster LEB with(nolock)
		LEFT JOIN SystemManager..BankProfileBranch BPB with(nolock) ON BPB.BranchID = LEB.BranchID
		LEFT JOIN SystemManager..CustomerProfileMaster CPM with(nolock) ON CPM.CustomerID = LEB.CustomerCode
		LEFT JOIN MasterDoc MD with(nolock) ON MD.MasterDocID = LEB.MasterDocID
		LEFT JOIN LCAdvisingRegister Advi with(nolock) ON Advi.LCReceiveID = MD.LCReceiveID
		LEFT JOIN SystemManager..Contacts Issue with(nolock) ON Issue.Code = Advi.BankID
		LEFT JOIN SystemManager..Contacts IssueBranch with(nolock) ON IssueBranch.Code = Advi.BankBranchID
		LEFT JOIN ExportBillMonitoring EBM with(nolock) ON EBM.EBIID = LEB.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = LEB.CURRENCY_CODE AND CLR.RateFor = 'BC SELLING'
		LEFT JOIN SystemManager..CommodityMaster Commo with(nolock) ON Commo.CommodityMasterID = MD.Commodity
		LEFT JOIN SystemManager..EntityFixedVariables tenor with(nolock) ON tenor.EntityID = LEB.TenorType
		INNER JOIN (
			SELECT M.BillRefNo, MAX(M.Date) Date, SUM(M.ProceedsRecvd) RealizationAmount, MAX(Currency) Currency
			FROM
			(
				SELECT BillRefNo, MAX(Date) Date, MAX(ProceedsRecvd) ProceedsRecvd, MAX(Currency) Currency
				FROM PRSCreationDistributionDetails with(nolock)
				WHERE IsDeleted = 0
				GROUP BY BillRefNo
			) M
			GROUP BY BillRefNo
		) PRSM ON PRSM.BillRefNo = LEB.EBIID
		LEFT JOIN (
			Select P.EBIID,
				STUFF((SELECT ', ' + CAST(CONVERT(date, PP.StartDate) AS VARCHAR(10))
					FROM LDBCPurchase PP with(nolock)
					WHERE PP.IsDeleted = 0 AND PP.IsCancelled = 0 AND PP.EBIID = P.EBIID
					FOR XML PATH(''), TYPE)
				.value('.','NVARCHAR(MAX)'),1,2,' ') StartDate,
				STUFF((SELECT ', ' + PP.LoanNumber
					FROM LDBCPurchase PP with(nolock)
					WHERE PP.IsDeleted = 0 AND PP.IsCancelled = 0 AND PP.EBIID = P.EBIID
					FOR XML PATH(''), TYPE)
				.value('.','NVARCHAR(MAX)'),1,2,' ') LoanNumber
			FROM LDBCPurchase P with(nolock)
			WHERE P.IsDeleted = 0 AND P.IsCancelled = 0
			Group by P.EBIID
		) PUR ON PUR.EBIID = LEB.EBIID
		LEFT JOIN (
			SELECT MAX(CreditDate) CreditDate, EBIID
			FROM (
				SELECT DISTINCT CreditDate, EBIID 
				FROM LDBCPayment P with(nolock)
				WHERE P.IsDeleted = 0 AND IsCancelled = 0
			) A
			GROUP BY EBIID
		) PAY ON PAY.EBIID = LEB.EBIID
	WHERE LEB.IsDeleted = 0 AND ISNULL(LEB.IsCancelled, 0) = 0 AND LEB.ExportLocalBillNo IS NOT NULL
		AND CONVERT(DATE, PRSM.Date) BETWEEN @FromDate AND @ToDate
END
GO


USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[LCAdvisingRegisterPBL]    Script Date: 11/18/2026 12:02:04 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE Or Alter Proc [dbo].[LCAdvisingRegisterPBL]
@FromDate date,@ToDate date
as
Begin
----  Exec LCAdvisingRegisterPBL '2025-01-01','2025-10-01'
Declare @USDRate numeric(18,4)
Select @USDRate=ConvertFactor from [SystemManager]..CurrencyLatestRate  with(nolock) where CurrencyCode='USD' and RateFor='BC SELLING'


Select distinct  ADbpb.BranchName AS ADBranchName	,
	NonADbpb.BranchName AS NonADBranchName,	                       
	scu.AdviceNo AS AdvisingNumber,
	scu.AdviceDate AS AdvisingDate,
	TransactionRef=LCAR.ExternalId,	
	ExportLCNo=LCAR.LCNumber,
	LCAR.BBLCSCNumber,
	LCTYPE.DisplayCode AS LCType,
	LCSubType=SubLC.DisplayCode,
	LCSubTypeDescription=SubLC.Description,
	TenorType=TenorType.DisplayCode,	
	Tenor=CASE WHEN ISNULL(MD.Tenor,0) > 0 AND ISNULL(MD.TenorType,'') <> ''  THEN CAST(MD.Tenor AS VARCHAR(100)) + ' Days'
	WHEN ISNULL(MD.TenorType,'') = '' AND ISNULL(MD.Tenor,0)= 0 THEN ''  
	ELSE 'At Sight' END,	
	TenorDescription=isnull(TenorDes.Description,TenorDes.DisplayCode),	
	IssueDate=lcar.IssueDate,	
	Currency=lcar.Currency,	
	Amount=lcar.LCAmount,	
	EquivalentinUSD=(lcar.LCAmount*clr.ConvertFactor)/@USDRate,	
	ExchangeRate=clr.ConvertFactor,	
	EquivalentinBDT=lcar.LCAmount*clr.ConvertFactor,	
	ShipmentDate=lcar.ShipmentDate,	
	ExpiryDate=lcar.ExpiryDate,	
	Tolerance=Case when LCAR.ToleranceNegative>0 then LCAR.ToleranceNegative*-1 else lcar.TolerancePositive end,	
	LiabRevDate=null,	
	ClosingDate=LCAR.ClosingDate,	
	Commodity=Commodity.CommodityName,	
	IssueBank=issueBank.Name,	
	IssueBranch=issueBranch.Name,	
	CustomerNonCustomer=Case when lcar.IsCustomerLC=1 then 'Customer' else 'Non-Customer' end,	Benificiary=Beni.Name,	
	CustomerID=CPM.CIF,	
	CustomerType=COALESCE(NULLIF(Seg.DisplayCode, ''), NULLIF(Seg.Description, ''), NULLIF(CPM.BusinessUnit, ''), CusType.Description, Case when lcar.IsCustomerLC=1 then 'Customer' else 'Non-Customer' end),	
	Applicant=Applicant.Name,	
	ApplicantsCountry=ApplicantCountry.CountryName,	
	JobNumber=null,	
	R06Reference=null,	
	InputterName=Isnull(lcar.AddedBy,lcar.MakeBy),	
	InputTime=isnull(lcar.DateAdded,lcar.MakeDate),
	AuthorisedBy=lcar.CheckBy,	
	AuthTime=lcar.CheckDate,	
	ChargeRealizationStatus=null, 	
	ChargeAmt=null,	
	ChargeDebAcc=null,	
	IssuingBanksBIC=null,	
	AdvisingBanksBIC=null,	
	MessageType=MSGTYPE.DisplayCode,	
	IssuingBankBranchAddress=issueBranch.Officeaddress, 	
	IssuingBankBranchEmail=issueBank.EmailNo,	
	IssuingBankAddress=issueBank.Officeaddress,
	-----------NEW----------
	WaiverCharge = lcar.WaiverCharge,
	CMTAmount = lcar.CMTAmount,
	CMTPercent = lcar.CMTPercent,
	ClosingDate1 = lcar.ClosingDate,
	ChargeDebitAccount = lcar.ChargeDebitAccount,
	ChargeStatus = lcar.ChargeStatus,
	BICodAdvisingBank = lcar.BICodAdvisingBank,
	RReference = lcar.RReference,
	LCExpiryPlace = lcar.LCExpiryPlace,
	AvailablewithBankID = lcar.AvailablewithBankID,
	AvailableWithBank1 = lcar.AvailableWithBank1,
	AdviseThruBank1 = lcar.AdviseThruBank1,
	ModeofTransport = lcar.ModeofTransport,
	UnitPrice1 = lcar.UnitPrice1,
	LiabilityReversalDate = lcar.LiabilityReversalDate,
	PortOfLoading=lcar.PortOfLoading,
	PortOfDestination = lcar.PortOfDestination,
	PartShipment = lcar.Partshipment,
	Transhipment = lcar.Transhipment,

	PresentationDescription = lcar.PresentationDescription,
	DraweeBankID = lcar.DraweeBankID,
	DraweeName = lcar.DraweeName,
	AvailableWithBank = lcar.AvailableWithBank,
	AvailableBy = lcar.AvailableBy,
	AdviseThroughBankID = lcar.AdviseThroughBankID,
	ReimbursingBankID = lcar.ReimbursingBankID,
	ReimbursingBankName = lcar.ReimbursingBankName,
	ReqConfirmationParty = lcar.ReqConfirmationParty,
	ReqConfirmPartyName = lcar.ReqConfirmPartyName,
	Operation = lcar.Operation,
	LCAmountLCY = lcar.LCAmountLCY,
	UltimateBuyer = lcar.UltimateBuyer,
	BenefeciaryAccount = lcar.BenefeciaryAccount,
	LCTypeBB = lcar.LCTypeBB,
	UploadBB = lcar.UploadBB,
	Chargesfrom = lcar.Chargesfrom,
	ChargeDefaultAcct = lcar.ChargeDefaultAcct,
	SequenceofTotal = lcar.SequenceofTotal,
	EApplicableRules = lcar.EApplicableRules,
	aAIssuingBank = lcar.aAIssuingBank,
	ADIssuingBank = lcar.ADIssuingBank,
	ApplicantBank = lcar.ApplicantBank,
	CAddlAmountsCovered = lcar.CAddlAmountsCovered,
	MMixedPaymentDetails = lcar.MMixedPaymentDetails,
	PDeferredPaymentDetails = lcar.PDeferredPaymentDetails,
	APlaceofTakinginCharge = lcar.APlaceofTakinginCharge,
	BFinalDestination = lcar.BFinalDestination,
	DShipmentPeriod = lcar.DShipmentPeriod,
	ConfirmationInstructions = lcar.ConfirmationInstructions,
	InstructionstotheBank = lcar.InstructionstotheBank,
	aAAdviseThroughBank = lcar.aAAdviseThroughBank,
	aDAdviseThroughBank = lcar.aDAdviseThroughBank,
	ZSendertoReceiverInformatioin = lcar.ZSendertoReceiverInformatioin,
	RecordStatus = lcar.RecordStatus,
	DepartmentCode = lcar.DepartmentCode,
	AuditorCode = lcar.AuditorCode,
	AuditDateandTime = lcar.AuditDateandTime,
	CountryMakingPayment = lcar.CountryMakingPayment,
	DebitAmount = lcar.DebitAmount,
	DebitCurrency = lcar.DebitCurrency,
	ChargeCode = lcar.ChargeCode,
	PartyCharged = lcar.PartyCharged,
	TotalCharges = lcar.TotalCharges,
	TaxACCAmount = lcar.TaxACCAmount,
	DebitAccountNo = lcar.DebitAccountNo,
	ExportSection = lcar.ExportSection,
	---------------END------------
	CASE WHEN LCAR.IsTransferable = 1 THEN 'Transferable' ELSE 'Not Transferable' END TransferableStatus,
	issueBranch.SwiftCode LCIssuingBankSWIFTCode,
	advisingBank.Name AdvisingBankName,
	issueBranch.AgentName ADCodeofIssuingBankBranch,
	issueBank.CountryID CountryOfLCIssuingBank,
	FBeni.Name FirstBeneficiaryName,
	FBeni.CountryID FirstBeneficiaryCountry,
	TransferringBank.Name TransferringFirstAdvisingBankName,
	TransferringBank.CountryID CountryOfTransferringBank,
	RM.EmployeeName RMName,
	'' TBRM,
	'' LCAdvisingStatus,
	CASE WHEN MD.LCReceiveID IS NOT NULL THEN 'Lined' ELSE '' END LienStatus,
	LCAR.Remarks Remarks,

	--For Mapping Non Mendatory Parameter
	CustomerId=LCAR.Customer,
	LCAR.ADBranchID,
	IssueingBankId=LCAR.BankID

from 
LCAdvisingRegister LCAR with(nolock)
Left Join LCScrutiny scu with(nolock) on scu.LCReceiveID=LCAR.LCReceiveID and scu.IsDeleted=0 and scu.IsCancelled=0
LEFT JOIN MasterDoc MD with(nolock) ON MD.LCReceiveID = LCAR.LCReceiveID and md.IsDeleted=0 and md.IsCancelled=0
LEFT JOIN SystemManager..EntityFixedVariables MSGTYPE with(nolock) ON MSGTYPE.EntityID = LCAR.MessageTypeID
LEFT JOIN SystemManager..EntityFixedVariables TenorType with(nolock) ON TenorType.EntityID = LCAR.TenorType
LEFT JOIN SystemManager..EntityFixedVariables TenorDes with(nolock) ON TenorDes.EntityID = LCAR.TenorDescription
LEFT JOIN [SystemManager]..CommodityMaster Commodity with(nolock) on Commodity.CommodityMasterID=lcar.Commodity and Commodity.IsDeleted=0
LEFT JOIN SystemManager..Contacts issueBank  with(nolock) on  issueBank.Code = LCAR.BankID
LEFT JOIN SystemManager..CustomerProfileMaster CPM  with(nolock) on  CPM.CustomerID = LCAR.Customer
LEFT JOIN SystemManager..Contacts Applicant  with(nolock) on  Applicant.Code = LCAR.Applicant
LEFT JOIN SystemManager..Country ApplicantCountry  with(nolock) on  ApplicantCountry.CountryID = Applicant.CountryID
LEFT JOIN SystemManager..Contacts Beni  with(nolock) on  Rtrim(Ltrim(Beni.Name)) =  Rtrim(Ltrim(LCAR.Beneficiary))
	LEFT JOIN SystemManager..Contacts issueBranch  with(nolock) on  issueBranch.Code = LCAR.BankBranchID
LEFT JOIN ( SELECT B.BranchID ,B.BranchName from SystemManager..BankProfileBranch B
				 inner JOIN SystemManager..CustomerBranchMap C  with(nolock) on  B.BranchID = C.BranchID	) NonADbpb   on  NonADbpb.BranchID = LCAR.BranchID
	LEFT JOIN (select * from SystemManager..BankProfileBranch WHERE IsADCode = 1) ADbpb   on  ADbpb.ADBranchID = LCAR.ADBranchID
LEFT JOIN SystemManager..EntityFixedVariables LCTYPE  with(nolock) on  LCTYPE.EntityID = LCAR.LCTypeID
LEFT JOIN SystemManager..EntityFixedVariables CusType  with(nolock) on  CusType.EntityID = LCAR.CustomerType
LEFT JOIN SystemManager..EntityFixedVariables Seg with(nolock) on Seg.EntityID = CPM.SegmentID and Seg.EntityTypeID = 'CSEG/17/1' and Seg.IsDeleted = 0
LEFT JOIN SystemManager..EntityFixedVariables SubLC  with(nolock) on  SubLC.EntityID = LCAR.LCSubTypeID
LEFT JOIN [SystemManager]..CurrencyLatestRate clr  with(nolock) on clr.CurrencyCode=lcar.Currency and clr.RateFor='BC SELLING'
LEFT JOIN SystemManager..t_Employee RM with(nolock) ON RM.EmployeeCode = CPM.RMID
LEFT JOIN SystemManager..Contacts TransferringBank  with(nolock) on  TransferringBank.Code = LCAR.TransferringBankID
LEFT JOIN SystemManager..Contacts advisingBank  with(nolock) on  advisingBank.Code = LCAR.AdvisingBankID
LEFT JOIN SystemManager..Contacts FBeni  with(nolock) on  FBeni.Code = LCAR.FirstBeneficiaryID

where
CONVERT(DATE,LCAR.LCReceiveDate) Between @FromDate and @ToDate  
	and LCAR.IsDeleted = 0 
order by AdviceNo desc
End
GO


