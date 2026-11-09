USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_PerformanceDetailExporterWiseSummaryPBL]    Script Date: 11/9/2026 2:24:22 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_PerformanceDetailExporterWiseSummaryPBL]
	-- SP_RPT_PerformanceDetailExporterWiseSummaryPBL  
AS											 
BEGIN
DECLARE @USDRate NUMERIC(18,4)
SELECT @USDRate=ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) 
WHERE RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l) AND CurrencyCode='USD'


---  Export LC Details
SELECT 
		GroupSysID,
		TotalAmountFOBINSFREFCUSD=Sum(((Case when ReplacedLCSC=1 then null else FobValue+ Insurance+ Freight+ ForeignCommision end)*ConvertFactor)/@USDRate),
		ReplacedbyLCUSD=Sum((ISNULL((Case when ReplacedLCSC=1 then ReplacedbyLC else null end),0)*ConvertFactor)/@USDRate),
		FobValueUSD=Sum((ISNULL(Case when ReplacedLCSC=1 then null else FobValue end,0)*ConvertFactor)/@USDRate)

		into #ExportLCDetails
		
		 FROM (
		 SELECT
		    MD.ReplacedLCSC,
			MD.LCNo ExportLCSCNo,
			
			MD.Incoterm Incoterm,
			MD.Currency Currency,
			 FobValue=CASE
                WHEN IsLienToGroup = 1
                THEN
                    CASE
                            WHEN ReplacedLCSC = 1 
							THEN 
								CASE
								WHEN Commission.FOBChargesTypeID = 'Percent'
								THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
								ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
							END
                            ELSE                              
                                CASE WHEN IsSC = 0 THEN
                                    CASE
                                            WHEN Commission.FOBChargesTypeID = 'Percent'
											THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
											ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
                                    END
                                ELSE
                                    CASE
                                            WHEN ReplacedAmount > LCAmount THEN 0
                                            ELSE
                                                CASE
                                                    WHEN Commission.FOBChargesTypeID = 'Percent'
													THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - MD.ReplacedAmount
													ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.ReplacedAmount
                                                END
                                    END
                                END
                    END
                ELSE 0
            END ,
            MD.AmountToGroup,
			CASE WHEN MD.ReplacedLCSC = 1 and LCAmount > 0 THEN MD.TolerancePercent Else '' END AS ReplacingTolerancePercent,
			CLR.ConvertFactor,MD.LCAmount,
			ISNULL(Insurance.FOBChargesValue, 0) Insurance,
			ISNULL(Freight.FOBChargesValue, 0) Freight,
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 ELSE ISNULL(Commission.FOBChargesValue, 0) END AS ForeignCommision,
			MD.LCAmount + CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 ELSE ISNULL(Commission.FOBChargesValue, 0) END + ISNULL(Insurance.FOBChargesValue, 0) + ISNULL(Freight.FOBChargesValue, 0) AS TotalAmountFOBINSFREFC,
			MD.TolerancePercent Tolerance,
			TotalAmountTol=MD.LCAmount + 
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 
				 ELSE ISNULL(Commission.FOBChargesValue, 0) END + ISNULL(Insurance.FOBChargesValue, 0) + ISNULL(Freight.FOBChargesValue, 0) + MD.TolerancePercent  ,
			CASE WHEN MD.ReplacedLCSC = 1 THEN MD.LCAmount ELSE 0 END AS ReplacedbyLC,
			SCReplacedByLCAmount * (MD.TolerancePercent)/100 TotalAmountReplacedTotal,
			Tenor=CASE WHEN md.TenorType='AtSight' then 'At Sight'
			
			when md.TenorType='Deferred' then   CONVERT(VARCHAR(10),MD.Tenor)+' Days '+ isnull(tenordes.DisplayCode,'')  
			ELSE tenorType.DisplayCode END ,
			
			MD.CustomerID,GLC.GroupSysID,GroupRefNo=Replace(GLC.GroupRefNo,'&amp;','&'),CPM.CustomerName,BPB.BranchName,
			LCSCtype=case when md.IsSC=1 then 'SC' ELSE 'LC' end,
			ReplacementStatus=case when md.ReplacedLCSC=1 then 'Yes' ELSE 'No' end
			
			
		FROM (SELECT * FROM MasterDoc with(nolock) WHERE IsDeleted = 0 AND IsCancelled = 0 AND IsConformed = 1 AND IsLienToGroup = 1) MD
		LEFT JOIN (SELECT * FROM GroupLC with(nolock) WHERE IsDeleted = 0) GLC ON GLC.GroupSysID = MD.GroupSysID
		LEFT JOIN (SELECT MasterDocID,MAX(NewExpiryDate)ExpiryDate,MAX(NewShipDate)ShipmentDate FROM MasterLCAmmendment with(nolock)
					WHERE IsDeleted = 0 AND IsCancelled = 0 GROUP BY MasterDocID) MLCAM ON MLCAM.MasterDocID = MD.MasterDocID
		LEFT JOIN (SELECT MasterDocID,ReplacedAmount SCReplacedByLCAmount FROM MasterDoc with(nolock) WHERE IsDeleted = 0 AND IsCancelled = 0 AND IsScReplacedByLC = 1 AND IsConformed = 1) SCReplacedByLC ON SCReplacedByLC.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'ForeignCommission'
		) Commission ON Commission.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'Freight'
		) Freight ON Freight.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'Insurance'
		) Insurance ON Insurance.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
		LEFT JOIN SystemManager..CustomerProfileMaster CPM with(nolock) ON CPM.CustomerID = MD.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = GLC.BankBranchID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = SSG.ConvertRateForExportLCAmount
		LEFT JOIN SystemManager..Contacts APP with(nolock) ON APP.Code = MD.Applicant
		LEFT JOIN SystemManager..Contacts opB with(nolock) ON opB.Code = MD.OpeningBankCode
		LEFT JOIN SystemManager..Country C with(nolock) ON C.CountryID = APP.CountryID
		LEFT JOIN SystemManager..EntityFixedVariables tenordes ON tenordes.entityid = md.tenordescription
		LEFT JOIN SystemManager..EntityFixedVariables tenorType ON tenorType.entityid = md.TenorType
		  LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR ON GRPCLR.CurrencyCode = Glc.CurrencyCode AND GRPCLR.RateFor = SSG.ConvertRateForGroupAmount
		  LEFT JOIN (Select top 1 c.Name,co.CountryName,p.LCReceiveID from LcAdvisingPartyInfo p
inner join [SystemManager]..Contacts c with(nolock) on c.code=p.PartyID
Inner join [SystemManager]..ContactPersonChild cpc on cpc.Code=c.Code
Inner join [SystemManager]..ContactTypes ct on ct.ContactTypeID=cpc.ContactTypeID
left join [SystemManager]..Country co on co.CountryID=c.CountryID
where ct.ContactType='Ultimate Buyer') UltimateBuyer on UltimateBuyer.LCReceiveID=MD.MasterDocID
LEFT JOIN (
    		SELECT SUM(AmountToGroupA) GroupAmount  
			FROM (
    	    				SELECT CASE
    		   					WHEN Commission.FOBChargesTypeID = 'Percent'
    		   					THEN CASE
									WHEN((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
									THEN LCAmount 
									ELSE ReplacedAmount
								END - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - CASE
												WHEN((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
												THEN LCAmount 
												ELSE ReplacedAmount
												END * ISNULL(Commission.FOBChargesValue, 0) / 100
    		   					ELSE CASE
									WHEN((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
									THEN LCAmount 
									ELSE ReplacedAmount
								END - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
    		   				END * CASE WHEN G.CurrencyCode = MD.Currency THEN 1 ELSE CLR.ConvertFactor / GRPCLR.ConvertFactor END AmountToGroupA
    	    				FROM MasterDoc MD with(nolock)
								INNER JOIN GroupLC G with(nolock) ON G.GroupSysID = MD.GroupSysID
								LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
								LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR with(nolock) ON GRPCLR.CurrencyCode = G.CurrencyCode AND GRPCLR.RateFor = SSG.ConvertRateForGroupAmount
								LEFT JOIN SystemManager..SystemSettings SSM ON '' = ''
    	    	  				LEFT JOIN SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = SSM.ConvertRateForExportLCAmount
								LEFT JOIN (
									SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
									FROM ChargesAgainstLCValueFOBCalculation with(nolock)
									WHERE TemplateID = 'ForeignCommission'
								) Commission ON Commission.MasterDocID = MD.MasterDocID
								LEFT JOIN (
									SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
									FROM ChargesAgainstLCValueFOBCalculation with(nolock)
									WHERE TemplateID = 'Freight'
								) Freight ON Freight.MasterDocID = MD.MasterDocID
								LEFT JOIN (
									SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
									FROM ChargesAgainstLCValueFOBCalculation with(nolock)
									WHERE TemplateID = 'Insurance'
								) Insurance ON Insurance.MasterDocID = MD.MasterDocID
    	    				WHERE
								 MD.IsCancelled = 0
								AND MD.IsDeleted = 0
								AND MD.IsLienToGroup = 1
								AND MD.ReplacedLCSC = 0
			) GrpCalcFromMasterDoc
    	) GrpCalcFromMasterDoc ON '' = '')x group by x.GroupSysID

--- END Export LC Details

----  Acceptance Information 
Select x.GroupSysID,AcceptanceBillAmountFCYUSD=Sum(x.AcceptanceBillAmountFCYUSD),
OutstandingAcceptanceAmountFCY=Sum(x.OutstandingAcceptanceAmountFCY),
OverdueAmount=Sum(x.OverdueAmount)
into #AcceptenceInfoSubReport from  (
SELECT
			B.GroupSysID,
			AcceptanceBillAmountFCYUSD=(F.BillAmount*CLR.ConvertFactor)/@USDRate ,			
			OutstandingAcceptanceAmountFCY=((F.BillAmount-ISNULL(ImportBillPayment.PaymentAmount, 0))*CLR.ConvertFactor)/@USDRate-((((Select isnull(Sum(l.CreditAmount),0) from CustomerVoucherTransDetails l
			 where l.AdditionalMasterID=f.ExternalID and substring(l.CreditAccountNo,0,3)='50' )-ISNULL(ImportBillPayment.PaymentAmount, 0))*ISNULL(CLR.ConvertFactor,0))/@USDRate),
		
			OverdueAmount= Case 			
			when cast(f.MATURITY_DATE as date )<cast(getdate() as date ) then 
			((F.BillAmount-ISNULL(ImportBillPayment.PaymentAmount, 0))*CLR.ConvertFactor)/@USDRate-((((Select isnull(Sum(l.CreditAmount),0) from CustomerVoucherTransDetails l
			 where l.AdditionalMasterID=f.ExternalID and substring(l.CreditAccountNo,0,3)='50' )-ISNULL(ImportBillPayment.PaymentAmount, 0))*ISNULL(CLR.ConvertFactor,0))/@USDRate)
			else null end 
		 FROM ForeignDocumentAcceptanceMaster F
		INNER JOIN BBLCMaster B ON B.BBLCID = F.BBLCID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = F.Currency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = F.CustomerID
		LEFT JOIN (SELECT * FROM GroupLC WHERE IsDeleted = 0) G ON G.GroupSysID = B.GroupSysID
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN SystemManager..EntityFixedVariables EFV ON EFV.EntityID = F.AcceptanceStatus
		Left Join (Select PaymentAmount=Sum(x.Amount)/@USDRate,TransDate=Max(x.TransDate),x.FDAID from (Select Amount=Sum(v.CreditAmount*c.ConvertFactor),Max(v.DateAdded)TransDate,f.FDAID from CustomerVoucherTransDetails v
			inner join [SystemManager]..BankProfileNostroAccounts n on n.AccountNo=v.CreditAccountNo
			Inner join [SystemManager]..CurrencyLatestRate c on c.CurrencyCode=v.CreditCurrency AND c.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
			Inner join ForeignDocumentAcceptanceMaster f on f.ExternalID=v.AdditionalMasterID
			where v.AdditionalFilter='Foreign Document Acceptance Master' group by f.FDAID
			Union All
			Select sum(l.CreditFCY*c.ConvertFactor),Max(l.TransactionSendingTimeToCBS),e.BillOrLoanID from			MarginTransactionDetails l
			inner join MarginEncashmentMaster e on e.MAEMID=l.MAEMID
			inner join [SystemManager]..BankProfileNostroAccounts n on n.AccountNo=l.AccountNo
			Inner join [SystemManager]..EntityFixedVariables v on v.EntityID=e.ExportBillType
			Inner join [SystemManager]..CurrencyLatestRate c on c.CurrencyCode=l.CCY AND c.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
			where l.IsSendTransactionToCBS=1 and e.IsBill=1 and v.DisplayCode='Import Payment'
			group by e.BillOrLoanID)x
			Group by x.FDAID)
		ImportBillPayment ON ImportBillPayment.FDAID = F.FDAID		
		WHERE BillNo IS NOT NULL AND F.IsDeleted = 0 AND F.IsCancelled = 0 
		--AND EFV.EntityType = 'Acceptance_Status' 
		and f.UBSSyncProcessID>0 and f.AcceptanceIDNo is not null )x
		Group by x.GroupSysID
--- End  Acceptance Information 

---- PAD Information
SELECT
			
			B.GroupSysID,
			PADEDFAmountFCY=Sum(Case when L.Currency='USD' then l.LoanAmount/l.ExchangeRate else l.LoanAmount/@USDRate end),
			UnpaidPADUSD=Sum(Case when L.Currency='USD' then (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end)/l.ExchangeRate else (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end)/@USDRate end),
			OverdueAmountUSD=Sum(Case when L.Currency='USD' then (Case when Cast(l.MATURITY_DATE as date)<Cast(Getdate() as date)  then (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end) else null end)/l.ExchangeRate else (Case when Cast(l.MATURITY_DATE as date)<Cast(Getdate() as date)  then (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end) else null end)/@USDRate end)
			into #PADEDFInformation
			
			
		FROM LoanCreation L 
		INNER JOIN BBLCMaster B ON B.BBLCID = L.BBLCID
		LEFT JOIN (SELECT * FROM GroupLC WHERE IsDeleted = 0) G ON G.GroupSysID = B.GroupSysID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = L.Currency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = G.CustomerID
				
		LEFT JOIN (SELECT * FROM EFA..LoanPayment WHERE LoanAgainst = 'PAD' AND Product = 'EDF' ) P_EDF ON P_EDF.USER_REF_NO = L.LoanNo
		LEFT JOIN SystemManager..CurrencyLatestRate P_EDFCLR ON P_EDFCLR.CurrencyCode = P_EDF.AC_CCY AND P_EDFCLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN SystemManager..EntityFixedVariables loantype on loantype.EntityID=l.LoanAgainst
		WHERE B.IsDeleted = 0 AND B.IsCancelled = 0 AND B.IsDeleted = 0 
		and l.UBSSyncProcessID > 0
		AND isnull(loantype.DisplayCode, l.LoanAgainst) in ('PD01', 'PD03', 'PD04', 'PDOF')
		Group by B.GroupSysID
---- End PAD Information

--- EDF Information
		SELECT
			B.GroupSysID,

		    EDFAmountFCYUSD=Sum(Case 
			when 
			lca.ExchangeRate is not null and lca.ExchangeRate>1 
			then l.LoanAmount/lca.ExchangeRate 
			else l.LoanAmount/@USDRate end),
			UnpaidFCY=Sum((Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end)/(Case 
			when 
			lca.ExchangeRate is not null and lca.ExchangeRate>1 
			then lca.ExchangeRate 
			else @USDRate end))  ,									
			OverdueUSD = Sum((Case when Cast(l.MATURITY_DATE as date)<Cast(Getdate() as date)  then (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end) else null end)/(Case 
			when 
			lca.ExchangeRate is not null and lca.ExchangeRate>1 
			then lca.ExchangeRate 
			else @USDRate end))
			into #EDFInfo
			
		FROM LoanCreation L 
		left join LoanCreation lca on lca.IsDeleted=0 and lca.LoanNo=l.AdditionalFilter
		INNER JOIN BBLCMaster B ON B.BBLCID = L.BBLCID
		LEFT JOIN (SELECT * FROM GroupLC WHERE IsDeleted = 0) G ON G.GroupSysID = B.GroupSysID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = L.LoanCurrency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = G.CustomerID
		--LEFT JOIN EFA..LoanPayment P ON P.USER_REF_NO = L.LoanNo
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN SystemManager..EntityFixedVariables loantype on loantype.EntityID=l.LoanAgainst
		WHERE B.IsDeleted = 0 AND B.IsCancelled = 0 AND B.IsDeleted = 0 
		and l.UBSSyncProcessID > 0 AND (l.ExternalID like '%EDF%' or l.LoanNo like '%EDF%')
		AND G.Grouprefno is not null
		Group by b.GroupSysID
--- End EDF Information

-- PC TimeLoan Information
SELECT
			
			M.GroupSysID,
			PCTimeLoanAmountFCYUSD=Sum((PC.PCAmount*ConvertFactor)/@USDRate),
			
			OutstandingAmountFCYUSD=SUM(CASE WHEN pc.TransactionDate is  null THEN pc.PCAmountTK                      
                    ELSE pc.TOT_OS END)/@USDRate, 
			
			OverdueAmountUSD = Sum(Case when PC.MATURITY_DATE  < getdate() 
			then (CASE WHEN pc.TransactionDate is  null THEN pc.PCAmountTK                      
                    ELSE pc.TOT_OS END)/@USDRate 
			else Null END)
			into #PCTimeLoanInformation
		FROM PCDisbursementMaster PC
		LEFT JOIN (SELECT * FROM GroupLC WHERE IsDeleted = 0) G ON G.GroupSysID = PC.GroupRefID
		LEFT JOIN (SELECT MAX(Tenor)Tenor,GroupSysID FROM MasterDoc WHERE IsDeleted = 0 AND IsCancelled = 0 GROUP BY GroupSysID) M ON M.GroupSysID = G.GroupSysID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = PC.Currency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = G.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN  SystemManager..EntityFixedVariables E ON E.EntityID = PC.LoanType
		WHERE PC.IsDeleted = 0 
		AND PC.UBSSyncProcessID>0
		group by M.GroupSysID

-- End PC Time Loan Information

-- ExportBill FDBC Information / ExportMade

Select x.GroupSysID,ExportMade=Sum(x.BillAmountUSD),
RealizedAmount=Sum(x.RealizedAmountFCY*x.ConvertFactor)/@USDRate,
UnrealizedAmount=Sum(x.UnRealizedAmountFCY*x.ConvertFactor)/@USDRate
into #ExportBillFDBCInformation from  (SELECT 
		EBIM.ExportBillNo AS FDBCFDBPNo,
		EBIM.BillGenerationDate AS Date,
		EBIM.CURRENCY_CODE AS BillCurrency,
		EBIM.ExportBillAmount AS BillAmount,
		(EBIM.ExportBillAmount * ConvertFactor) / @USDRate AS BillAmountUSD,
		MD.LCNo AS ExportLCSCNumber,
		EM.MaturityDate AS DueDate,
		ProductCSV.Product AS Product,
		PDFDM.DisbursedAmount AS PurchaseDiscountingAmountTimeLoan,
		(ISNULL(PDFDM.DisbursedAmount,0) * ConvertFactor) / @USDRate AS PurchaseDiscountingAmountTimeLoanUSD,
		Isnull(PRSM.RealizedValue,0)+Isnull(ARV.RMTAdjustedAmount,0) AS RealizedAmountFCY,
		(ISNULL(PRSM.RealizedValue, 0) * ConvertFactor) / @USDRate AS RealizedAmountFCYUSD,
		--Under.TotalExport AS UnRealizedAmountFCY,
		--(ISNULL(Under.TotalExport, 0) * ConvertFactor) / @USDRate AS UnRealizedAmountFCYUSD,
		UnRealizedAmountFCY=Case when (Isnull(PRSM.RealizedValue,0)+Isnull(ARV.RMTAdjustedAmount,0)=0 or Isnull(PRSM.RealizedValue,0)+Isnull(ARV.RMTAdjustedAmount,0) is null) then EBIM.ExportBillAmount
		when (isnull(Isnull(PRSM.RealizedValue,0)+Isnull(ARV.RMTAdjustedAmount,0),0)/EBIM.ExportBillAmount)*100>=95 then 0
		else isnull(EBIM.ExportBillAmount,0)-isnull(Isnull(PRSM.RealizedValue,0)+Isnull(ARV.RMTAdjustedAmount,0),0) end,
		UnRealizedAmountFCYUSD=((Case when (PRSM.RealizedValue=0 or PRSM.RealizedValue is null) then EBIM.ExportBillAmount
		when (isnull(PRSM.RealizedValue,0)/EBIM.ExportBillAmount)*100>=95 then 0
		else isnull(EBIM.ExportBillAmount,0)-isnull(PRSM.RealizedValue,0) end)* ConvertFactor)/@USDRate,
		PRSM.SyncDate AS DateofRealization,
		EBIM.CustomerCode CustomerID,
		MD.GroupSysID,
		G.GroupRefNo,
		CPM.CustomerName,
		BPB.BranchName,
		ConvertFactor
	FROM ExportBillInitiationMaster EBIM
		INNER JOIN MasterDoc MD ON MD.MasterDocID = EBIM.MasterDocID
		INNER JOIN GroupLC G ON G.GroupSysID = ISNULL(MD.GroupSysID, '')
		LEFT JOIN ExportBillMonitoring EM ON EM.EBIID = EBIM.EBIID AND EM.IsDeleted = 0
		LEFT JOIN (SELECT 
                ISNULL(ARV.AdjustmentAmount, 0) + ISNULL(ARV.ForeignBankCharge, 0) + ISNULL(ARV.ForeignCommission, 0) + ISNULL(ARV.DiscountAmount, 0) RMTAdjustedAmount,ARV.EBIIRMTD EBIID,ARV.RMTCMID
         FROM  (
			SELECT  ebaa.EBIIRMTD,SUM(rmtc.TotalRMTAmount)TotalRMTAmount,SUM(ebaa.AdjustmentAmount) AdjustmentAmount, SUM(ebaa.ForeignBankCharge) ForeignBankCharge, SUM(ebaa.ForeignCommission) ForeignCommission, 
			SUM(ebaa.DiscountAmount) DiscountAmount,MAX(rmtc.RMTCMID)RMTCMID
			FROM 
			 RMTCreationMaster rmtc
			 Left Join (Select ebaa.EBIIRMTD, ebaa.RMTCCID,SUM(ebaa.AdjustmentAmount) AdjustmentAmount, SUM(ebaa.ForeignBankCharge) ForeignBankCharge, SUM(ebaa.ForeignCommission) ForeignCommission, SUM(ebaa.DiscountAmount) DiscountAmount,max(ebaa.DateAdded) ARVDATE from ExportBillAgainstRMTAdjustmentDetails ebaa WHERE ebaa.IsDeleted = 0 AND ebaa.IsCancelled = 0 group by ebaa.EBIIRMTD, ebaa.RMTCCID) ebaa
			 
			 
			 on rmtc.RMTCMID=ebaa.RMTCCID
			 
			GROUP BY ebaa.EBIIRMTD)ARV) ARV ON ARV.EBIID = EBIM.EBIID
		LEFT JOIN (
			select EBIID, MAX(Product) Product
			from (
				select EBIID, 'Purchase' Product from PurchaseDiscountForeignDocumentMaster 
				where IsDeleted = 0 and IsCancelled = 0 and LoanNumber is not null and IsPurchaseLoanType = 1 and IsExportLoan = 0
				union
				select EBIID, 'OBU' Product from PurchaseDiscountForeignDocumentMaster 
				where IsDeleted = 0 and IsCancelled = 0 and LoanNumber is not null and IsPurchaseLoanType = 0 and IsExportLoan = 0
				union
				select PC.EBIID, 'Export Loan' Product from PurchaseDiscountForeignDocumentChild PC
				LEFT JOIN PurchaseDiscountForeignDocumentMaster PD ON PD.PDFDMID = PC.PDFDMID
				where PD.IsDeleted = 0 and PD.IsCancelled = 0 and PD.LoanNumber is not null and PD.IsExportLoan = 1
			) Pro
			where EBIID is not null
			group by Pro.EBIID
		) ProductCSV ON ProductCSV.EBIID = EBIM.EBIID
		LEFT JOIN (
			SELECT EBIID, SUM(DisbursedAmount) DisbursedAmount 
			FROM PurchaseDiscountForeignDocumentMaster 
			WHERE IsDeleted = 0 AND IsCancelled = 0 
			GROUP BY EBIID
		) PDFDM ON PDFDM.EBIID =  EBIM.EBIID
		LEFT JOIN (
			select EBIID, sum(C_Amount) RealizedValue, MAX(SyncDate) SyncDate
			from (
				Select 
					PCM.PRSSysID, 
					PCM.C_Amount,
					PRDS.SyncDate,
					PCM.EBIID
				From PRSCreationMaster PCM 
					LEFT JOIN (
						SELECT 
							PRSSysID,
							CONVERT(DATE, A.SyncTime) SyncDate,
							CASE
								WHEN ISNULL(A.SyncCount, 0) = ISNULL(A.SyncSum, 0) THEN 1
								ELSE 0
							END IsSync
						FROM (
							SELECT PRSSysID, MAX(TransactionSendingTimeToCBS) SyncTime, COUNT(IsSendTransactionToCBS) SyncCount, SUM(CAST(IsSendTransactionToCBS AS INT)) SyncSum
							FROM PRSCreationDistributionDetails 
							WHERE IsDeleted = 0
							GROUP BY PRSSysID
						) A
					) PRDS ON PRDS.PRSSysID = PCM.PRSSysID
					LEFT JOIN (
						SELECT 
							PRSSysID,
							CONVERT(DATE, A.RevTime) RevDate,
							CASE
								WHEN ISNULL(A.RevCount, 0) = ISNULL(A.RevSum, 0) THEN 1
								ELSE 0
							END IsReverse
						FROM (
							SELECT PRSSysID, MAX(TransReversedTime) RevTime, COUNT(IsReversedFromCBS) RevCount, SUM(CAST(IsReversedFromCBS AS INT)) RevSum
							FROM PRSCreationDistributionDetails 
							WHERE IsDeleted = 0 AND TransactionSendingTimeToCBS IS NOT NULL AND CBSTransactionResponseRef IS NOT NULL
							GROUP BY PRSSysID
						) A
					) PRDR ON PRDR.PRSSysID = PCM.PRSSysID
				Where PCM.IsDeleted = 0 and ISNULL(PRDS.IsSync, 0) = 1 and ISNULL(PRDR.IsReverse, 0) = 0
			) P
			group by EBIID
		) PRSM ON PRSM.EBIID = EBIM.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = EBIM.CURRENCY_CODE AND CLR.RateFor = ((Select top 1 l.ConvertRateForExportRealizedAmount  from SystemManager..SystemSettings l))
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = EBIM.CustomerCode
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN (
				SELECT EBIID, SUM(ExportBillAmount) TotalExport 
				FROM (
					SELECT EBIM.EBIID, EBIM.MasterDocID, ExportBillAmount
					FROM (
						SELECT EBIM.EBIID, EBIM.MasterDocID, ExportBillAmount
						FROM ExportBillInitiationMaster EBIM
						WHERE ExportBillNo IS NOT NULL AND IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0
					) EBIM
						LEFT JOIN (
							SELECT EBIID FROM PRSCreationMaster WHERE IsDeleted = 0 GROUP BY EBIID
						) PRS ON PRS.EBIID = EBIM.EBIID
						LEFT JOIN MasterDoc MD ON MD.MasterDocID = EBIM.MasterDocID
					WHERE PRS.EBIID IS NULL

					UNION ALL

					SELECT EBIM.EBIID, EBIM.MasterDocID, EBIM.ExportBillAmount
					FROM (
						SELECT EBIM.EBIID, EBIM.MasterDocID, ExportBillAmount
						FROM ExportBillInitiationMaster EBIM
						WHERE ExportBillNo IS NOT NULL AND IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0
					) EBIM
						INNER JOIN (
							SELECT P.EBIID, SUM(C_Amount) + ISNULL(SUM(FCC.ChargeAmount), 0) RealizedAmountChargeAmount
							FROM PRSCreationMaster P
								LEFT JOIN (
									SELECT C.PRSSysID, SUM(C.ChargeAmount) ChargeAmount
									FROM PRSCreationForeignCharges C
									WHERE C.IsDeleted = 0
									GROUP BY C.PRSSysID
								) FCC ON FCC.PRSSysID = P.PRSSysID
							WHERE P.IsDeleted = 0
							GROUP BY P.EBIID
						) PRS ON PRS.EBIID = EBIM.EBIID
						LEFT JOIN MasterDoc MD ON MD.MasterDocID = EBIM.MasterDocID
						LEFT JOIN GroupLC G ON G.GroupSysID = MD.GroupSysID
					WHERE (ISNULL(PRS.RealizedAmountChargeAmount, 0) / EBIM.ExportBillAmount) * 100 < 95
				) EBIM 
				GROUP BY EBIID
			) Under ON Under.EBIID = EBIM.EBIID
	WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND EBIM.ExportBillNo IS NOT NULL 

	UNION ALL

	SELECT 
		EBIM.ExportLocalBillNo AS FDBCFDBPNo,
		EBIM.BillGenerationDate AS Date,
		EBIM.CURRENCY_CODE AS BillCurrency,
		EBIM.ExportLocalBillAmount AS BillAmount,
		(EBIM.ExportLocalBillAmount * ConvertFactor) / @USDRate AS BillAmountUSD,
		MD.LCNo AS ExportLCSCNumber,
		EM.MaturityDate AS DueDate,
		ProductCSV.Product AS Product,
		PDFDM.DisbursedAmount AS PurchaseDiscountingAmountTimeLoan,
		(ISNULL(PDFDM.DisbursedAmount,0) * ConvertFactor) / @USDRate AS PurchaseDiscountingAmountTimeLoanUSD,
		PRSM.RealizedValue AS RealizedAmountFCY,
		(ISNULL(PRSM.RealizedValue, 0) * ConvertFactor) / @USDRate AS RealizedAmountFCYUSD,
		--Under.TotalExport AS UnRealizedAmountFCY,
		--(ISNULL(Under.TotalExport, 0) * ConvertFactor) / @USDRate AS UnRealizedAmountFCYUSD,
		UnRealizedAmountFCY=Case when (PRSM.RealizedValue=0 or PRSM.RealizedValue is null) then EBIM.ExportLocalBillAmount
		when (isnull(PRSM.RealizedValue,0)/EBIM.ExportLocalBillAmount)*100>=95 then 0
		else isnull(EBIM.ExportLocalBillAmount,0)-isnull(PRSM.RealizedValue,0) end,
		UnRealizedAmountFCYUSD=((Case when (PRSM.RealizedValue=0 or PRSM.RealizedValue is null) then EBIM.ExportLocalBillAmount
		when (isnull(PRSM.RealizedValue,0)/EBIM.ExportLocalBillAmount)*100>=95 then 0
		else isnull(EBIM.ExportLocalBillAmount,0)-isnull(PRSM.RealizedValue,0) end)* ConvertFactor)/@USDRate,
		PRSM.SyncDate AS DateofRealization,
		EBIM.CustomerCode CustomerID,
		MD.GroupSysID,
		G.GroupRefNo,
		CPM.CustomerName,
		BPB.BranchName,
		ConvertFactor
	FROM LocalExportBillInitiationMaster EBIM
		INNER JOIN MasterDoc MD ON MD.MasterDocID = EBIM.MasterDocID
		INNER JOIN GroupLC G ON G.GroupSysID = ISNULL(MD.GroupSysID, '')
		LEFT JOIN ExportBillMonitoring EM ON EM.EBIID = EBIM.EBIID AND EM.IsDeleted = 0
		LEFT JOIN (
			select EBIID, MAX(Product) Product
			from (
				select EBIID, 'Purchase' Product from PurchaseDiscountForeignDocumentMaster 
				where IsDeleted = 0 and IsCancelled = 0 and LoanNumber is not null and IsPurchaseLoanType = 1 and IsExportLoan = 0
				union
				select EBIID, 'OBU' Product from PurchaseDiscountForeignDocumentMaster 
				where IsDeleted = 0 and IsCancelled = 0 and LoanNumber is not null and IsPurchaseLoanType = 0 and IsExportLoan = 0
				union
				select PC.EBIID, 'Export Loan' Product from PurchaseDiscountForeignDocumentChild PC
				LEFT JOIN PurchaseDiscountForeignDocumentMaster PD ON PD.PDFDMID = PC.PDFDMID
				where PD.IsDeleted = 0 and PD.IsCancelled = 0 and PD.LoanNumber is not null and PD.IsExportLoan = 1
			) Pro
			where EBIID is not null
			group by Pro.EBIID
		) ProductCSV ON ProductCSV.EBIID = EBIM.EBIID
		LEFT JOIN (
			SELECT EBIID, SUM(DisbursedAmount) DisbursedAmount 
			FROM PurchaseDiscountForeignDocumentMaster 
			WHERE IsDeleted = 0 AND IsCancelled = 0 
			GROUP BY EBIID
		) PDFDM ON PDFDM.EBIID =  EBIM.EBIID
		LEFT JOIN (
			select EBIID, sum(C_Amount) RealizedValue, MAX(SyncDate) SyncDate
			from (
				Select 
					PCM.PRSSysID, 
					PCM.C_Amount,
					PRDS.SyncDate,
					PCM.EBIID
				From PRSCreationMaster PCM 
					LEFT JOIN (
						SELECT 
							PRSSysID,
							CONVERT(DATE, A.SyncTime) SyncDate,
							CASE
								WHEN ISNULL(A.SyncCount, 0) = ISNULL(A.SyncSum, 0) THEN 1
								ELSE 0
							END IsSync
						FROM (
							SELECT PRSSysID, MAX(TransactionSendingTimeToCBS) SyncTime, COUNT(IsSendTransactionToCBS) SyncCount, SUM(CAST(IsSendTransactionToCBS AS INT)) SyncSum
							FROM PRSCreationDistributionDetails 
							WHERE IsDeleted = 0
							GROUP BY PRSSysID
						) A
					) PRDS ON PRDS.PRSSysID = PCM.PRSSysID
					LEFT JOIN (
						SELECT 
							PRSSysID,
							CONVERT(DATE, A.RevTime) RevDate,
							CASE
								WHEN ISNULL(A.RevCount, 0) = ISNULL(A.RevSum, 0) THEN 1
								ELSE 0
							END IsReverse
						FROM (
							SELECT PRSSysID, MAX(TransReversedTime) RevTime, COUNT(IsReversedFromCBS) RevCount, SUM(CAST(IsReversedFromCBS AS INT)) RevSum
							FROM PRSCreationDistributionDetails 
							WHERE IsDeleted = 0 AND TransactionSendingTimeToCBS IS NOT NULL AND CBSTransactionResponseRef IS NOT NULL
							GROUP BY PRSSysID
						) A
					) PRDR ON PRDR.PRSSysID = PCM.PRSSysID
				Where PCM.IsDeleted = 0 and ISNULL(PRDS.IsSync, 0) = 1 and ISNULL(PRDR.IsReverse, 0) = 0
			) P
			group by EBIID
		) PRSM ON PRSM.EBIID = EBIM.EBIID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = EBIM.CURRENCY_CODE AND CLR.RateFor = ((Select top 1 l.ConvertRateForExportRealizedAmount  from SystemManager..SystemSettings l))
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = EBIM.CustomerCode
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN (
				SELECT EBIID, SUM(ExportLocalBillAmount) TotalExport 
				FROM (
					SELECT EBIM.EBIID, EBIM.MasterDocID, ExportLocalBillAmount
					FROM (
						SELECT EBIM.EBIID, EBIM.MasterDocID, ExportLocalBillAmount
						FROM LocalExportBillInitiationMaster EBIM
						WHERE ExportLocalBillNo IS NOT NULL AND IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0
					) EBIM
						LEFT JOIN (
							SELECT EBIID FROM PRSCreationMaster WHERE IsDeleted = 0 GROUP BY EBIID
						) PRS ON PRS.EBIID = EBIM.EBIID
						LEFT JOIN MasterDoc MD ON MD.MasterDocID = EBIM.MasterDocID
					WHERE PRS.EBIID IS NULL

					UNION ALL

					SELECT EBIM.EBIID, EBIM.MasterDocID, EBIM.ExportLocalBillAmount
					FROM (
						SELECT EBIM.EBIID, EBIM.MasterDocID, ExportLocalBillAmount
						FROM LocalExportBillInitiationMaster EBIM
						WHERE ExportLocalBillNo IS NOT NULL AND IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0
					) EBIM
						INNER JOIN (
							SELECT P.EBIID, SUM(C_Amount) + ISNULL(SUM(FCC.ChargeAmount), 0) RealizedAmountChargeAmount
							FROM PRSCreationMaster P
								LEFT JOIN (
									SELECT C.PRSSysID, SUM(C.ChargeAmount) ChargeAmount
									FROM PRSCreationForeignCharges C
									WHERE C.IsDeleted = 0
									GROUP BY C.PRSSysID
								) FCC ON FCC.PRSSysID = P.PRSSysID
							WHERE P.IsDeleted = 0
							GROUP BY P.EBIID
						) PRS ON PRS.EBIID = EBIM.EBIID
						LEFT JOIN MasterDoc MD ON MD.MasterDocID = EBIM.MasterDocID
						LEFT JOIN GroupLC G ON G.GroupSysID = MD.GroupSysID
					WHERE (ISNULL(PRS.RealizedAmountChargeAmount, 0) / EBIM.ExportLocalBillAmount) * 100 < 95
				) EBIM 
				GROUP BY EBIID
			) Under ON Under.EBIID = EBIM.EBIID
	WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND
	EBIM.ExportLocalBillNo IS NOT NULL  
	)x
	Group by x.GroupSysID
---End Export Bill FDBC Information

--- Margin information

Select x.GroupSysID,MarginCredit=Sum(x.CalCreditAmount) ,
MarginDebit=SUM(x.CalDebitAmount),MarginBalance=Sum(x.Balance) into #MarginInformation from (
Select 
		y.*,Balance=y.CalCreditAmount-y.CalDebitAmount
	from (
		select
			d.*,
			CalCreditAmount = case when d.Currency = 'USD' then d.CreditAmount else (d.CreditAmount * CLR.ConvertFactor)/@USDRate end,
			CalDebitAmount = 0
		from dbo.ViewTransactionLedgerOBL d
			left join SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = d.Currency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		where d.DRCR = 'C' and AC_NO in (
			SELECT CA.AccountCode
			FROM SystemManager..CustomerProfileAccounts CA
				INNER JOIN SystemManager..EntityFixedVariables EN ON EN.EntityID = CA.AccountTypeID
				LEFT JOIN SystemManager..BankProfileGLAccounts GL ON GL.AccountNo = CA.AccountCode
			WHERE CA.IsDeleted = 0 and EN.ExternalID = 'MARGIN'  and GL.AccountNo IS NULL and 
			CA.CustomerID=d.CustomerCode
		)

		union all

		select
			d.*,
			CalCreditAmount = 0,
			CalDebitAmount = case when d.Currency = 'USD' then d.DebitAmount else (d.DebitAmount * CLR.ConvertFactor)/@USDRate end
		from dbo.ViewTransactionLedgerOBL d
			left join SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = d.Currency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		where d.DRCR = 'D' and AC_NO in (
			SELECT CA.AccountCode
			FROM SystemManager..CustomerProfileAccounts CA
				INNER JOIN SystemManager..EntityFixedVariables EN ON EN.EntityID = CA.AccountTypeID
				LEFT JOIN SystemManager..BankProfileGLAccounts GL ON GL.AccountNo = CA.AccountCode
			WHERE CA.IsDeleted = 0 and EN.ExternalID = 'MARGIN'  and GL.AccountNo IS NULL and 
			CA.CustomerID=d.CustomerCode
		)
	) y
)x
Group by x.GroupSysID
--- END Margin Information

---- Force Loan
SELECT
			
			Sum((L.BillAmount*ConvertFactor)/@USDRate) AS ForceLoanAmountBDT,
			
			 OutstandingAmountBDT=Sum(Case when L.Currency='USD' then (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end)/nullif(l.ExchangeRate,0) else (Case when l.OutstandingAmount is null then l.LoanAmount else l.OutstandingAmount end)/@USDRate end),
			G.GroupSysID into #ForceLoan
		FROM LoanCreation L
		INNER JOIN BBLCMaster B ON B.BBLCID = L.BBLCID
		INNER JOIN GroupLC G ON G.GroupSysID = B.GroupSysID
		LEFT JOIN (SELECT RELATED_ACCOUNT, SUM(LCY_AMOUNT) LCY_AMOUNT, SUM(FCY_AMOUNT) FCY_AMOUNT, MAX(VALUE_DT) VALUE_DT
					FROM LoanPayment with(nolock) 
					WHERE IsDeleted = 0 AND DRCR_IND = 'C' 
					GROUP BY RELATED_ACCOUNT
		) LPay ON LPay.RELATED_ACCOUNT = L.ACCOUNT_NUMBER 
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = L.Currency AND CLR.RateFor = (Select top 1 l.ConvertRateForGroupAmount  from SystemManager..SystemSettings l)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = L.Customer
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = G.BankBranchID
		LEFT JOIN SystemManager..EntityFixedVariables loantype on loantype.EntityID=l.LoanAgainst
		WHERE L.IsDeleted = 0 AND  (l.ExternalID like '%TM13%' or l.ExternalID like '%TM14%'or l.ExternalID like '%TMFL%' or l.ExternalID like '%TM11%')
		AND L.UBSSyncProcessID > 0 
		group by g.GroupSysID
----- End Force Loan

--- Expired LC

SELECT 
		GroupSysID,
		TotalAmountFOBINSFREFCUSD=Sum(((Case when ReplacedLCSC=1 then null else FobValue+ Insurance+ Freight+ ForeignCommision end)*ConvertFactor)/@USDRate)

		into #ExpiredExportLCDetails
		
		 FROM (
		 SELECT
		 MD.GroupSysID,
		    MD.ReplacedLCSC,			
			 FobValue=CASE
                WHEN IsLienToGroup = 1
                THEN
                    CASE
                            WHEN ReplacedLCSC = 1 
							THEN 
								CASE
								WHEN Commission.FOBChargesTypeID = 'Percent'
								THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
								ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
							END
                            ELSE                              
                                CASE WHEN IsSC = 0 THEN
                                    CASE
                                            WHEN Commission.FOBChargesTypeID = 'Percent'
											THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
											ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
                                    END
                                ELSE
                                    CASE
                                            WHEN ReplacedAmount > LCAmount THEN 0
                                            ELSE
                                                CASE
                                                    WHEN Commission.FOBChargesTypeID = 'Percent'
													THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - MD.ReplacedAmount
													ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.ReplacedAmount
                                                END
                                    END
                                END
                    END
                ELSE 0
            END ,          
			CLR.ConvertFactor,MD.LCAmount,
			ISNULL(Insurance.FOBChargesValue, 0) Insurance,
			ISNULL(Freight.FOBChargesValue, 0) Freight,
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 ELSE ISNULL(Commission.FOBChargesValue, 0) END AS ForeignCommision,
			MD.LCAmount + CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 ELSE ISNULL(Commission.FOBChargesValue, 0) END + ISNULL(Insurance.FOBChargesValue, 0) + ISNULL(Freight.FOBChargesValue, 0) AS TotalAmountFOBINSFREFC,
			MD.TolerancePercent Tolerance
			
			
			
		FROM (SELECT * FROM MasterDoc with(nolock) WHERE IsDeleted = 0 AND IsCancelled = 0 AND IsConformed = 1 AND IsLienToGroup = 1) MD
		LEFT JOIN (SELECT * FROM GroupLC with(nolock) WHERE IsDeleted = 0) GLC ON GLC.GroupSysID = MD.GroupSysID
		LEFT JOIN (SELECT MasterDocID,MAX(NewExpiryDate)ExpiryDate,MAX(NewShipDate)ShipmentDate FROM MasterLCAmmendment with(nolock)
					WHERE IsDeleted = 0 AND IsCancelled = 0 GROUP BY MasterDocID) MLCAM ON MLCAM.MasterDocID = MD.MasterDocID
		LEFT JOIN (SELECT MasterDocID,ReplacedAmount SCReplacedByLCAmount FROM MasterDoc with(nolock) WHERE IsDeleted = 0 AND IsCancelled = 0 AND IsScReplacedByLC = 1 AND IsConformed = 1) SCReplacedByLC ON SCReplacedByLC.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'ForeignCommission'
		) Commission ON Commission.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'Freight'
		) Freight ON Freight.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'Insurance'
		) Insurance ON Insurance.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
		LEFT JOIN SystemManager..CustomerProfileMaster CPM with(nolock) ON CPM.CustomerID = MD.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = GLC.BankBranchID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = SSG.ConvertRateForExportLCAmount		
		  LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR ON GRPCLR.CurrencyCode = Glc.CurrencyCode AND GRPCLR.RateFor = SSG.ConvertRateForGroupAmount		  
 where Cast(md.ShipmentDate as date)<Cast(Getdate() as date))x group by x.GroupSysID


--- END Expired LC
--- Expired LC within 15 days

SELECT 
		GroupSysID,
		TotalAmountFOBINSFREFCUSD=Sum(((Case when ReplacedLCSC=1 then null else FobValue+ Insurance+ Freight+ ForeignCommision end)*ConvertFactor)/@USDRate)

		into #ExpiredExportLCDetails15Days
		
		 FROM (
		 SELECT
		 MD.GroupSysID,
		    MD.ReplacedLCSC,			
			 FobValue=CASE
                WHEN IsLienToGroup = 1
                THEN
                    CASE
                            WHEN ReplacedLCSC = 1 
							THEN 
								CASE
								WHEN Commission.FOBChargesTypeID = 'Percent'
								THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
								ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
							END
                            ELSE                              
                                CASE WHEN IsSC = 0 THEN
                                    CASE
                                            WHEN Commission.FOBChargesTypeID = 'Percent'
											THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
											ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
                                    END
                                ELSE
                                    CASE
                                            WHEN ReplacedAmount > LCAmount THEN 0
                                            ELSE
                                                CASE
                                                    WHEN Commission.FOBChargesTypeID = 'Percent'
													THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - MD.ReplacedAmount
													ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.ReplacedAmount
                                                END
                                    END
                                END
                    END
                ELSE 0
            END ,          
			CLR.ConvertFactor,MD.LCAmount,
			ISNULL(Insurance.FOBChargesValue, 0) Insurance,
			ISNULL(Freight.FOBChargesValue, 0) Freight,
			CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 ELSE ISNULL(Commission.FOBChargesValue, 0) END AS ForeignCommision,
			MD.LCAmount + CASE WHEN Commission.FOBChargesTypeID = 'Percent'
    		   	 THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 ELSE ISNULL(Commission.FOBChargesValue, 0) END + ISNULL(Insurance.FOBChargesValue, 0) + ISNULL(Freight.FOBChargesValue, 0) AS TotalAmountFOBINSFREFC,
			MD.TolerancePercent Tolerance
			
			
			
		FROM (SELECT * FROM MasterDoc with(nolock) WHERE IsDeleted = 0 AND IsCancelled = 0 AND IsConformed = 1 AND IsLienToGroup = 1) MD
		LEFT JOIN (SELECT * FROM GroupLC with(nolock) WHERE IsDeleted = 0) GLC ON GLC.GroupSysID = MD.GroupSysID
		LEFT JOIN (SELECT MasterDocID,MAX(NewExpiryDate)ExpiryDate,MAX(NewShipDate)ShipmentDate FROM MasterLCAmmendment with(nolock)
					WHERE IsDeleted = 0 AND IsCancelled = 0 GROUP BY MasterDocID) MLCAM ON MLCAM.MasterDocID = MD.MasterDocID
		LEFT JOIN (SELECT MasterDocID,ReplacedAmount SCReplacedByLCAmount FROM MasterDoc with(nolock) WHERE IsDeleted = 0 AND IsCancelled = 0 AND IsScReplacedByLC = 1 AND IsConformed = 1) SCReplacedByLC ON SCReplacedByLC.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'ForeignCommission'
		) Commission ON Commission.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'Freight'
		) Freight ON Freight.MasterDocID = MD.MasterDocID
		LEFT JOIN (
			SELECT  FOBChargesValue, FOBChargesTypeID, MasterDocID
			FROM ChargesAgainstLCValueFOBCalculation with(nolock)
			WHERE TemplateID = 'Insurance'
		) Insurance ON Insurance.MasterDocID = MD.MasterDocID
		LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
		LEFT JOIN SystemManager..CustomerProfileMaster CPM with(nolock) ON CPM.CustomerID = MD.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BPB ON BPB.BranchID = GLC.BankBranchID
		LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = SSG.ConvertRateForExportLCAmount		
		  LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR ON GRPCLR.CurrencyCode = Glc.CurrencyCode AND GRPCLR.RateFor = SSG.ConvertRateForGroupAmount		  
 where Cast(md.ShipmentDate as date) between Cast(getdate() as date) and Cast(DATEADD(DAY, 15, getdate()) as date) )x group by x.GroupSysID


--- END Expired LC within 15 days

	SELECT * 
	FROM 
	(
		SELECT
			Adbpb.BranchName,
			CPM.CustomerName AS ClientName,	
			GLC.GroupRefNo AS GroupRefNo,
			GLC.CurrencyCode AS GroupCurrency,
			LCSCValue=ExportLCDetails.TotalAmountFOBINSFREFCUSD,				
			ReplacedLCValue=	ExportLCDetails.ReplacedbyLCUSD,
			LCnotyetReplaced=ExportLCDetails.TotalAmountFOBINSFREFCUSD - ExportLCDetails.ReplacedbyLCUSD ,	
			GroupValue=ExportLCDetails.FobValueUSD,



			--CASE
			--	WHEN GrpCalcFromMasterDoc.GroupAmount <> 0
			--	THEN CONVERT(DECIMAL(18, 2), (ISNULL(Util.AmtUtilizedSQ, 0) / ISNULL(GrpCalcFromMasterDoc.GroupAmount / GCLR.ConvertFactor, 0)) * 100)
			--	ELSE 0
			--END BBLCPercent,
			BBLCPercent=Isnull(GLC.EntitlementPercent,0),
			ISNULL(GLC.GrpEntitlementAmt, 0) AS BBLCEntitlement,
			ISNULL(Util.AmtUtilizedWithoutTol, 0) AS BBLCValue,
			(ISNULL(GrpCalcFromMasterDoc.GroupAmount / GCLR.ConvertFactor, 0) * GLC.EntitlementPercent / 100) - ISNULL(Util.AmtUtilizedSQ, 0)  AS AllowableBBLCValue,
			isnull(AcceptenceInfoSubReport.AcceptanceBillAmountFCYUSD,0) AS AcceptanceValue		,
			Isnull(AcceptenceInfoSubReport.OutstandingAcceptanceAmountFCY,0) AS UnpaidAcceptance		,
			Isnull(AcceptenceInfoSubReport.OverdueAmount,0) AS OverdueAmount,
			--ISNULL(PADEDF.LoanAmount, 0) AS PADEDF,
			PADEDF=isnull(PADEDFInformation.PADEDFAmountFCY,0),
			UnpaidPADEDF=isnull(PADEDFInformation.UnpaidPADUSD,0),
			OverduePADEDF=isnull(PADEDFInformation.OverdueAmountUSD,0),
			--ISNULL(EDF.LoanAmount, 0) AS EDF,
			EDF=isnull(EDFInfo.EDFAmountFCYUSD,0),
			isnull(EDFInfo.UnpaidFCY,0) AS UnpaidEDF,
			isnull(EDFInfo.OverdueUSD,0) AS OverdueEDF,
			--ISNULL(PC.PCAmount, 0) AS PCTimeLoanDisbursed	,
			PCTimeLoanDisbursed=isnull(PCTimeLoanInformation.PCTimeLoanAmountFCYUSD,0),
			isnull(PCTimeLoanInformation.OutstandingAmountFCYUSD,0) AS PCTimeLoanOutstanding,
			Isnull(PCTimeLoanInformation.OverdueAmountUSD,0) AS PCTimeLoanOverdue,
			--ISNULL(Bill.ExportMade, 0) AS ExportMade			,
			--ISNULL(Bill.ExportNotMade, 0) AS ExportNotMade,
			--ISNULL(Realized.ProcessReceivedAmount,0) AS RealizedAmount		,
			ExportMade=isnull(ExportBillFDBCInformation.ExportMade,0),
			ExportNotMade=isnull(ExportLCDetails.TotalAmountFOBINSFREFCUSD,0)-isnull(ExportBillFDBCInformation.ExportMade,0),
			RealizedAmount=isnull(ExportBillFDBCInformation.RealizedAmount,0),
			UnRealizedAmount=isnull(ExportBillFDBCInformation.UnrealizedAmount,0)		,
			MarginRetained=isnull(MarginInformation.MarginCredit,0)		,
			MarginUtilized=isnull(MarginInformation.MarginDebit	,0)	,
			MarginBalance=isnull(MarginInformation.MarginBalance,0),
			--MarginBuildupRequirement=isnull(ExportLCDetails.TotalAmountFOBINSFREFCUSD*(CASE
			--	WHEN GrpCalcFromMasterDoc.GroupAmount <> 0
			--	THEN CONVERT(DECIMAL(18, 2), (ISNULL(Util.AmtUtilizedSQ, 0) / ISNULL(GrpCalcFromMasterDoc.GroupAmount / GCLR.ConvertFactor, 0)))
			--	ELSE 0
			--END),0),
			MarginBuildupRequirement=ExportLCDetails.FobValueUSD * 
			((CASE WHEN ISNULL(FCBBLC.Value, 0) > GLC.EntitlementPercent 
			THEN ISNULL(FCBBLC.Value, 0) 
			ELSE GLC.EntitlementPercent END) / 100),

			--MarginSurplusShortfall=isnull(MarginInformation.MarginBalance-(ExportLCDetails.TotalAmountFOBINSFREFCUSD*(CASE
			--	WHEN GrpCalcFromMasterDoc.GroupAmount <> 0
			--	THEN CONVERT(DECIMAL(18, 2), (ISNULL(Util.AmtUtilizedSQ, 0) / ISNULL(GrpCalcFromMasterDoc.GroupAmount / GCLR.ConvertFactor, 0)))
			--	ELSE 0
			--END)),0),
			MarginSurplusShortfall=ExportLCDetails.FobValueUSD * 
			((CASE WHEN ISNULL(FCBBLC.Value, 0) > GLC.EntitlementPercent 
			THEN ISNULL(FCBBLC.Value, 0) 
			ELSE GLC.EntitlementPercent END) / 100)-isnull(MarginInformation.MarginCredit,0),
			--ISNULL(FircedLoan.LoanAmount, 0) AS ForcedLoanDisbursed,
			--0 AS OutstandingForceLoan	,
			ForcedLoanDisbursed=isnull(ForceLoan.ForceLoanAmountBDT,0),
			OutstandingForceLoan=isnull(ForceLoan.OutstandingAmountBDT,0),
			ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) AS GroupValueOfLCSC,
			ISNULL(ExpiredExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) AS ExpiredLCSC,
			ISNULL(ExpiredExportLCDetails15Days.TotalAmountFOBINSFREFCUSD, 0) AS ExpiryWithin15DaysOfLCSC,
			 ExpiryAfter15DaysOfLCSC=ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0)-ISNULL(ExpiredExportLCDetails.TotalAmountFOBINSFREFCUSD, 0)-ISNULL(ExpiredExportLCDetails15Days.TotalAmountFOBINSFREFCUSD, 0),
			isnull(ExportBillFDBCInformation.ExportMade,0) AS TotalExportMade,
			 TotalExportNotMade=isnull(ExportLCDetails.TotalAmountFOBINSFREFCUSD,0)-isnull(ExportBillFDBCInformation.ExportMade,0),

			ExportExecutedagainstExpiredLCSC=ISNULL(ExpiredLCSC.ExportBillAmount, 0) ,

			UnutilizedExpiredLCSC=ISNULL(ExpiredLCSC.LCAmount, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0)  ,


			ISNULL(LiveLCSC.ExportBillAmount, 0) AS ExportExecutedagainstLiveLCSC,

			ISNULL(LiveLCSC.LCAmount, 0) - ISNULL(LiveLCSC.ExportBillAmount,0)  AS UnutilizedLiveLCSC,


			ISNULL(Bill.ExportMade, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.ExportBillAmount, 0)  AS ExportExecutedagainstLiveLCSCAfter15Days,
			(ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExpiredLCSC.LCAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.LCAmount, 0)) - (ISNULL(Bill.ExportMade, 0) - ISNULL(ExpiredLCSC.ExportBillAmount, 0) - ISNULL(ExpiryWithin15DaysOfLCSC.ExportBillAmount, 0))  AS UnutilizedLiveLCSCAfter15Days,


			Replace(MD.ApplicantName,'&amp;','&') AS BuyerName,
			MD.CountryName AS BuyerCountry,
 			GLC.CustomerID AS CustomerID,
			MD.Applicant AS Applicant,
			Adbpb.BranchName AS Branch,
			GLC.BankBranchID AS BranchID,
			GLC.GroupSysID AS GroupSysID,
			CASE WHEN GLC.IsClosedGroup = 1 THEN 'Closed' ELSE 'Live' END AS GroupStatus,
			MD.CountryID AS CountryID , CONVERT(DATE,GETDATE()) AS AsOnDate,
			GLC.DateAdded GroupDate,
			LShipmentDate=ld.ShipmentDate,
			LExpirydate=ld.ExpiryDate,
			Glclist=Replace(gLClist.gLCList,'&amp;','&'),
			glc.DateAdded GroupCreationDate,
			GroupFromDate=glc.DateAdded,
			GroupToDate=glc.DateAdded
		FROM GroupLC GLC
		    LEFT JOIN (Select md.GroupSysID,ShipmentDate=Max(ShipmentDate),ExpiryDate=Max(ExpiryDate) from MasterDoc md
			group by md.GroupSysID ) ld on ld.GroupSysID=glc.GroupSysID
			LEFT JOIN (Select GroupSysID, STUFF((SELECT distinct ', ' +  Replace(CombinedE.LCNo,'&amp;','&')  FROM (SELECT distinct MD.LCNo,GroupSysID FROM MasterDoc MD						 
						 WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0) CombinedE WHERE CombinedE.GroupSysID = glc.GroupSysID
						 FOR XML PATH('')),1,1,'') AS gLCList from GroupLC glc) gLClist on gLClist.GroupSysID=glc.GroupSysID
			LEFT JOIN SystemManager..CurrencyLatestRate GCLR ON GCLR.CurrencyCode = GLC.CurrencyCode AND GCLR.RateFor = 'BC SELLING'
			left join #ExportLCDetails ExportLCDetails on ExportLCDetails.GroupSysID=glc.GroupSysID
			Left Join #AcceptenceInfoSubReport AcceptenceInfoSubReport on AcceptenceInfoSubReport.GroupSysID=glc.GroupSysID
			LEFT JOIN #PADEDFInformation PADEDFInformation on PADEDFInformation.GroupSysID=glc.GroupSysID
			LEFT JOIN #EDFInfo EDFInfo on EDFInfo.GroupSysID=glc.GroupSysID
			LEFT JOIN #PCTimeLoanInformation PCTimeLoanInformation on PCTimeLoanInformation.GroupSysID=glc.GroupSysID
			LEFT JOIN #ExportBillFDBCInformation ExportBillFDBCInformation on ExportBillFDBCInformation.GroupSysID=glc.GroupSysID
			LEFT JOIN #MarginInformation MarginInformation on MarginInformation.GroupSysID=glc.GroupSysID
			LEFT JOIN #ExpiredExportLCDetails ExpiredExportLCDetails on ExpiredExportLCDetails.GroupSysID=glc.GroupSysID
			LEFT JOIN #ExpiredExportLCDetails15Days ExpiredExportLCDetails15Days on ExpiredExportLCDetails15Days.GroupSysID=glc.GroupSysID
			LEFT JOIN #ForceLoan ForceLoan  on ForceLoan.GroupSysID=glc.GroupSysID
			LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR ON GRPCLR.CurrencyCode = GLC.CurrencyCode AND GRPCLR.RateFor = 'BC SELLING'
			LEFT JOIN (
				select MasterID, sum(Value) Value
				from PRSAllocationTransaction
				where IsDeleted = 0 and AllocationHead='FC BBLC Margin'
				group by MasterID 
			) FCBBLC ON FCBBLC.MasterID = GLC.GroupSysID
			LEFT JOIN (
				SELECT BBLCM.GroupSysID, ISNULL(SUM((BBLCAmount + (BBLCAmount * Toleranace / 100)) * CASE WHEN G.CurrencyCode = BBLCM.Currency THEN 1 ELSE CLR.ConvertFactor / GRPCLR.ConvertFactor END), 0) AmtUtilizedSQ, ISNULL(SUM((BBLCAmount) * CASE WHEN G.CurrencyCode = BBLCM.Currency THEN 1 ELSE CLR.ConvertFactor / GRPCLR.ConvertFactor END), 0) AmtUtilizedWithoutTol
				FROM BBLCMaster BBLCM
					INNER JOIN GroupLC G ON G.GroupSysID = BBLCM.GroupSysID
					LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
					LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR ON GRPCLR.CurrencyCode = G.CurrencyCode AND GRPCLR.RateFor = SSG.ConvertRateForGroupAmount
					LEFT JOIN SystemManager..SystemSettings SSM ON '' = ''
		   			LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = BBLCM.Currency AND CLR.RateFor = SSM.ConvertRateForImportLCAmount
 				WHERE BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 and bblcm.BBLCNo is not null
				GROUP BY BBLCM.GroupSysID
			) Util ON Util.GroupSysID = GLC.GroupSysID
			LEFT JOIN (SELECT G.GroupSysID,SUM(LoanAmount)LoanAmount FROM LoanCreation L 
						INNER JOIN BBLCMaster B ON B.BBLCID = L.BBLCID
						INNER JOIN GroupLC G ON G.GroupSysID = B.GroupSysID
						WHERE B.IsDeleted = 0 AND B.IsCancelled = 0 AND B.IsDeleted = 0 AND LoanAgainst = 'LoanType/PAID'
						AND G.IsDeleted = 0 AND B.LCode IN ('03','05','11') GROUP BY G.GroupSysID)PADEDF ON PADEDF.GroupSysID = GLC.GroupSysID
			LEFT JOIN (SELECT G.GroupSysID,SUM(LoanAmount)LoanAmount FROM LoanCreation L 
						INNER JOIN BBLCMaster B ON B.BBLCID = L.BBLCID
						INNER JOIN GroupLC G ON G.GroupSysID = B.GroupSysID
						WHERE B.IsDeleted = 0 AND B.IsCancelled = 0 AND B.IsDeleted = 0 AND LoanAgainst = 'LoanType/LEDF'
						AND G.IsDeleted = 0 GROUP BY G.GroupSysID)EDF ON EDF.GroupSysID = GLC.GroupSysID
			LEFT JOIN (
				SELECT GroupSysID, SUM(LCAmount*clr.ConvertFactor)/@USDRate LCAmount, SUM(B.ExportBillAmount)/@USDRate ExportBillAmount 
				FROM MasterDoc M 
				LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
				LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode =	 m.Currency AND CLR.RateFor = SSG.ConvertRateForImportLCAmount
					LEFT JOIN (
						SELECT SUM(ExportBillAmount) ExportBillAmount, MasterDocID 
						FROM (
							SELECT eb.MasterDocID,ExportBillAmount=eb.ExportBillAmount *CLR.ConvertFactor
							FROM ExportBillInitiationMaster eb
							Inner join MasterDoc md on md.MasterDocID=eb.MasterDocID
							LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
							LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode =	 eb.CURRENCY_CODE AND CLR.RateFor = SSG.ConvertRateForImportLCAmount
							WHERE eb.IsDeleted = 0 AND ISNULL(eb.IsCancelled,0) = 0 AND eb.ExportBillNo IS NOT NULL and Cast(eb.BillGenerationDate as date)<=Cast(md.ShipmentDate as date)
							UNION ALL
							SELECT eb.MasterDocID,ExportLocalBillAmount=eb.ExportLocalBillAmount *CLR.ConvertFactor 
							FROM LocalExportBillInitiationMaster eb
							Inner join MasterDoc md on md.MasterDocID=eb.MasterDocID
							LEFT JOIN SystemManager..SystemSettings SSG ON '' = ''
							LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode =	 eb.CURRENCY_CODE AND CLR.RateFor = SSG.ConvertRateForImportLCAmount
							WHERE eb.IsDeleted = 0 AND ISNULL(eb.IsCancelled,0) = 0 AND eb.ExportLocalBillNo IS NOT NULL and Cast(eb.BillGenerationDate as date)<=Cast(md.ShipmentDate as date)
						) A GROUP BY MasterDocID
					) B ON B.MasterDocID = M.MasterDocID 
				WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND CONVERT(DATE, M.ShipmentDate) < CONVERT(DATE, GETDATE())
				GROUP BY GroupSysID
			)ExpiredLCSC ON ExpiredLCSC.GroupSysID = GLC.GroupSysID
			LEFT JOIN (
				SELECT GroupSysID, SUM(LCAmount) LCAmount, SUM(B.ExportBillAmount) ExportBillAmount 
				FROM MasterDoc M 
					LEFT JOIN (
						SELECT SUM(ExportBillAmount) ExportBillAmount, MasterDocID 
						FROM (
							SELECT MasterDocID,ExportBillAmount 
							FROM ExportBillInitiationMaster 
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled,0) = 0 AND ExportBillNo IS NOT NULL 
							UNION ALL
							SELECT MasterDocID,ExportLocalBillAmount 
							FROM LocalExportBillInitiationMaster 
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled,0) = 0 AND ExportLocalBillNo IS NOT NULL
						) A GROUP BY MasterDocID
					) B ON B.MasterDocID = M.MasterDocID 
				WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND CONVERT(DATE, M.ShipmentDate) > CONVERT(DATE, DATEADD(DAY, 15, GETDATE())) GROUP BY GroupSysID
			) ExpiryWithin15DaysOfLCSC ON ExpiryWithin15DaysOfLCSC.GroupSysID = GLC.GroupSysID
			
			LEFT JOIN (
				SELECT GroupSysID, SUM(LCAmount) LCAmount, SUM(B.ExportBillAmount) ExportBillAmount 
				FROM MasterDoc M 
					LEFT JOIN (
						SELECT SUM(ExportBillAmount) ExportBillAmount, MasterDocID 
						FROM (
							SELECT MasterDocID,ExportBillAmount 
							FROM ExportBillInitiationMaster 
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled,0) = 0 AND ExportBillNo IS NOT NULL 
							UNION ALL
							SELECT MasterDocID,ExportLocalBillAmount 
							FROM LocalExportBillInitiationMaster 
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled,0) = 0 AND ExportLocalBillNo IS NOT NULL
						) A 
						GROUP BY MasterDocID
					) B ON B.MasterDocID = M.MasterDocID 
				WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND CONVERT(DATE, GETDATE()) < CONVERT(DATE, M.ExpiryDate) 
				GROUP BY GroupSysID
			) LiveLCSC ON LiveLCSC.GroupSysID = GLC.GroupSysID
			LEFT JOIN (SELECT GroupSysID,MAX(ShipmentDate)ShipmentDate,MAX(ExpiryDate)ExpiryDate,MAX(Applicant)Applicant,MAX(APP.CountryID)CountryID,MAX(CC.CountryName)CountryName,
						 STUFF((SELECT distinct ', ' +  CombinedE.Name  FROM (SELECT distinct APP.Name,GroupSysID FROM MasterDoc MD
						 LEFT JOIN SystemManager..Contacts APP ON APP.Code = MD.Applicant
						 WHERE IsDeleted = 0 AND IsCancelled = 0) CombinedE WHERE CombinedE.GroupSysID = E.GroupSysID
						 FOR XML PATH('')),1,1,'') AS ApplicantName
						 FROM MasterDoc E LEFT JOIN SystemManager..Contacts APP ON APP.Code = E.Applicant
						 LEFT JOIN SystemManager..Country CC ON CC.CountryID = APP.CountryID  WHERE E.IsDeleted = 0 AND IsCancelled = 0 GROUP BY GroupSysID) MD ON MD.GroupSysID = GLC.GroupSysID
			LEFT JOIN (
				SELECT GroupSysID, SUM(LCAmount) ReplacedLCSCAmount 
				FROM MasterDoc 
				WHERE IsScReplacedByLC = 1 AND IsDeleted = 0 AND IsCancelled = 0 
				GROUP BY GroupSysID
			) TotalWillbeReplacedLCSC  ON TotalWillbeReplacedLCSC.GroupSysID = GLC.GroupSysID				 			
			LEFT JOIN (SELECT GroupSysID, SUM(LCAmount) ReplacedLCSCAmount FROM MasterDoc WHERE ReplacedLCSC = 1  AND IsDeleted = 0 AND IsCancelled = 0 GROUP BY GroupSysID) AlreadyReplacedLCSC  ON AlreadyReplacedLCSC.GroupSysID = GLC.GroupSysID				 			
			LEFT JOIN (
				SELECT M.GroupSysID, SUM((M.ReplacedAmount + Commission.FOBChargesValue + Freight.FOBChargesValue + Insurance.FOBChargesValue) * CLR.ConvertFactor) ReplacedLCSCAmount 
				FROM MasterDoc M 
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = M.Currency AND CLR.RateFor = 'BC SELLING'
					LEFT JOIN (
						SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
						FROM ChargesAgainstLCValueFOBCalculation
						WHERE TemplateID = 'ForeignCommission'
					) Commission ON Commission.MasterDocID = M.MasterDocID
					LEFT JOIN (
						SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
						FROM ChargesAgainstLCValueFOBCalculation
						WHERE TemplateID = 'Freight'
					) Freight ON Freight.MasterDocID = M.MasterDocID
					LEFT JOIN (
						SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
						FROM ChargesAgainstLCValueFOBCalculation
						WHERE TemplateID = 'Insurance'
					) Insurance ON Insurance.MasterDocID = M.MasterDocID
				WHERE M.IsDeleted = 0 AND M.IsCancelled = 0 AND M.ReplacedAmount > 0
				GROUP BY M.GroupSysID
			) ReplacedAmount  ON ReplacedAmount.GroupSysID = GLC.GroupSysID
			LEFT JOIN (
    			SELECT ISNULL(SUM(AmountToGroup), 0) GroupAmount, GroupSysID 
				FROM (
    				SELECT CASE
    		   				WHEN Commission.FOBChargesTypeID = 'Percent'
    		   				THEN CASE
						 	WHEN ((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
						 	THEN LCAmount 
						 	ELSE ReplacedAmount
						 	END - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - CASE
						 					WHEN ((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
						 					THEN LCAmount 
						 					ELSE ReplacedAmount
						 				END * ISNULL(Commission.FOBChargesValue, 0) / 100
    		   				ELSE CASE
						 	WHEN ((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
						 	THEN LCAmount 
						 	ELSE ReplacedAmount
						 	END - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
    		   			END * CLR.ConvertFactor AmountToGroup, GroupSysID
    				FROM MasterDoc MD
    		   			LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = 'BC SELLING'
						LEFT JOIN (
							SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
							FROM ChargesAgainstLCValueFOBCalculation
							WHERE TemplateID = 'ForeignCommission'
						) Commission ON Commission.MasterDocID = MD.MasterDocID
						LEFT JOIN (
							SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
							FROM ChargesAgainstLCValueFOBCalculation
							WHERE TemplateID = 'Freight'
						) Freight ON Freight.MasterDocID = MD.MasterDocID
						LEFT JOIN (
							SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
							FROM ChargesAgainstLCValueFOBCalculation
							WHERE TemplateID = 'Insurance'
						) Insurance ON Insurance.MasterDocID = MD.MasterDocID
					WHERE MD.IsCancelled = 0
						AND MD.IsDeleted = 0
						AND IsLienToGroup = 1
						AND ReplacedLCSC = 0
    			) GrpCalcFromMasterDoc 
				GROUP BY GroupSysID
    		) GrpCalcFromMasterDoc ON GrpCalcFromMasterDoc.GroupSysID =  GLC.GroupSysID
			LEFT JOIN (SELECT SUM(ProcessReceivedAmount)ProcessReceivedAmount,GroupSysID FROM (SELECT ProcessReceivedAmount,GroupSysID FROM(SELECT ISNULL(PRS.ProceedsRecvd, 0) ProcessReceivedAmount,MasterDocID FROM PRSCreationMaster PCM

							INNER JOIN (SELECT PRSSysID,MAX(ProceedsRecvd) ProceedsRecvd FROM PRSCreationDistributionDetails 
							WHERE IsDeleted = 0 GROUP BY PRSSysID,MasterDocID)PRS ON PRS.PRSSysID = PCM.PRSSysID WHERE PCM.IsDeleted = 0)PRSM
							LEFT JOIN MasterDoc MD ON MD.MasterDocID = PRSM.MasterDocID)Realized
							GROUP BY GroupSysID)Realized ON Realized.GroupSysID = GLC.GroupSysID
			LEFT JOIN (
				SELECT GroupSysID, SUM(ExportBillAmount) ExportMade, SUM(LCAmount) - ISNULL(SUM(ExportBillAmount), 0) ExportNotMade, SUM(LCAmount) LCAmount
				FROM MasterDoc MD
					LEFT JOIN  (
						SELECT MasterDocID, SUM(ExportBillAmount) ExportBillAmount 
						FROM (
							SELECT MasterDocID, SUM(ExportBillAmount) ExportBillAmount
							FROM ExportBillInitiationMaster 
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL
							GROUP BY MasterDocID
							UNION ALL
							SELECT MasterDocID, SUM(ExportLocalBillAmount)ExportLocalBillAmount
							FROM LocalExportBillInitiationMaster
							WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
							GROUP BY MasterDocID
						) A GROUP BY MasterDocID
					) Bill ON BILL.MasterDocID = MD.MasterDocID
				WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0 AND MD.IsLienToGroup = 1
				GROUP BY GroupSysID
			) Bill ON Bill.GroupSysID = GLC.GroupSysID
			LEFT JOIN (
				SELECT SUM(BillAmount) BillAmount, GroupSysID 
				FROM (
					SELECT BBLCID, SUM(BillAmount) BillAmount 
					FROM ForeignDocumentAcceptanceMaster 
					WHERE BillNo IS NOT NULL AND IsDeleted = 0 AND IsCancelled = 0 AND AcceptanceStatus = 'EFV/20/74'
					GROUP BY BBLCID
				) AcceptanceBTB
					INNER JOIN BBLCMaster BTB ON BTB.BBLCID = AcceptanceBTB.BBLCID
				GROUP BY GroupSysID
			) AcceptanceBTB ON AcceptanceBTB.GroupSysID = GLC.GroupSysID

			LEFT JOIN (SELECT ISNULL(ISNULL(Util.AmtUtilizedSQ, 0) / GRPCLR.ConvertFactor, 0) BBLCOpened,GLC.GroupSysID,
									CASE
									WHEN GrpCalcFromMasterDoc.GroupAmount / GRPCLR.ConvertFactor <> 0
									THEN CONVERT(DECIMAL(18, 2), (Util.AmtUtilizedSQ / GrpCalcFromMasterDoc.GroupAmount) * 100)
									ELSE 0
								END BBLCPercent
								FROM GroupLC GLC
								LEFT JOIN (
								 SELECT ISNULL(SUM(BBLCAmount * CLR.ConvertFactor), 0) AmtUtilizedSQ, GroupSysID
		   						 FROM BBLCMaster BBLCM
		   							 LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = BBLCM.Currency AND CLR.RateFor = 'BC SELLING'
 		   						 WHERE BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 GROUP BY GroupSysID
							   ) Util ON GLC.GroupSysID = Util.GroupSysID
							   LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR ON GRPCLR.CurrencyCode = GLC.CurrencyCode AND GRPCLR.RateFor = 'BC SELLING'
							   INNER JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = GLC.CustomerID
								LEFT JOIN (
    								  SELECT ISNULL(SUM(AmountToGroup), 0) GroupAmount,GroupSysID FROM (
    									SELECT CASE
    		   									 WHEN Commission.FOBChargesTypeID = 'Percent'
    		   									 THEN CASE
						 							WHEN ((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
						 							THEN LCAmount 
						 							ELSE ReplacedAmount
						 						 END - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - CASE
						 										 WHEN ((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
						 										 THEN LCAmount 
						 										 ELSE ReplacedAmount
						 									  END * ISNULL(Commission.FOBChargesValue, 0) / 100
    		   									 ELSE CASE
						 							WHEN ((IsSC = 1 AND LCAmount > ReplacedAmount) OR (IsSC = 0))
						 							THEN LCAmount 
						 							ELSE ReplacedAmount
						 						 END - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
    		   								   END * CLR.ConvertFactor AmountToGroup,GroupSysID
    									FROM MasterDoc MD
    		   								 LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = 'BC SELLING'
											 LEFT JOIN (
												SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
												FROM ChargesAgainstLCValueFOBCalculation
												WHERE TemplateID = 'ForeignCommission'
											) Commission ON Commission.MasterDocID = MD.MasterDocID
											LEFT JOIN (
												SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
												FROM ChargesAgainstLCValueFOBCalculation
												WHERE TemplateID = 'Freight'
											) Freight ON Freight.MasterDocID = MD.MasterDocID
											LEFT JOIN (
												SELECT FOBChargesValue, FOBChargesTypeID, MasterDocID
												FROM ChargesAgainstLCValueFOBCalculation
												WHERE TemplateID = 'Insurance'
											) Insurance ON Insurance.MasterDocID = MD.MasterDocID
										 AND MD.IsCancelled = 0
										 AND MD.IsDeleted = 0
										 AND IsLienToGroup = 1
										 AND ReplacedLCSC = 0
    									) GrpCalcFromMasterDoc GROUP BY GroupSysID
    							   ) GrpCalcFromMasterDoc ON GrpCalcFromMasterDoc.GroupSysID =  GLC.GroupSysID
						   GROUP BY GLC.IsMigrated,
								  GLC.EntitlementPercent,
								  CPM.MaxPerPCMDLEntitlement,
								 GLC.GroupSysID,
								  GRPCLR.ConvertFactor,
								  GrpCalcFromMasterDoc.GroupAmount,
								  Util.AmtUtilizedSQ) ToatlBTB ON ToatlBTB.GroupSysID = GLC.GroupSysID
			LEFT JOIN (SELECT SUM(ISNULL(PCDM.PCAmountTK, 0)) PCAmount,GroupSysID  FROM PCDisbursementMaster PCDM
						INNER JOIN GroupLC G ON G.GroupSysID = ISNULL(PCDM.GroupRefID, '')
						WHERE PCDM.IsDeleted = 0 GROUP BY GroupSysID) PC ON PC.GroupSysID = GLC.GroupSysID
			LEFT JOIN (SELECT SUM(ISNULL(L.LoanAmount, 0)) LoanAmount,G.GroupSysID  FROM LoanCreation L
						INNER JOIN BBLCMaster BTB ON BTB.BBLCID = L.BBLCID
						INNER JOIN GroupLC G ON G.GroupSysID = BTB.GroupSysID
						WHERE L.IsDeleted = 0 GROUP BY G.GroupSysID)FircedLoan ON FircedLoan.GroupSysID = GLC.GroupSysID
			LEFT JOIN (SELECT   B.BranchID ,B.BranchName from SystemManager..BankProfileBranch B
						INNER JOIN (SELECT BranchID FROM SystemManager..CustomerBranchMap GROUP BY BranchID) C ON B.BranchID = C.BranchID
						WHERE IsADCode = 0) NonADbpb ON NonADbpb.BranchID = GLC.BankBranchID
			LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = GLC.CustomerID
			LEFT JOIN SystemManager..BankProfileBranch Adbpb ON Adbpb.BranchID = GLC.ADBranchID
			
		WHERE GLC.IsDeleted = 0 and glc.IsMigrated=0
	) A 
	--where isnull(a.LCSCValue,0)>0 	
	order by A.GroupDate asc
END
GO
