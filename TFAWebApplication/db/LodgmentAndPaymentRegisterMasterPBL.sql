USE EFA
GO

Create Or Alter Proc spRPT_LodgmentAndPaymentRegisterMasterPBL
	@FromDate Date,
	@ToDate Date
As

 -- spRPT_LodgmentAndPaymentRegisterMasterPBL '2022-01-01', '2026-12-31'

 -- Lodgment and Payment Register (Master) for export bills (FDBC). Used by LodgmentAndPaymentRegisterMasterPBL.rdl.
 -- This procedure replaces SP_RPT_LodgmentAndPaymentRegisterMaster_PBL. It returns the same columns, in the same order.
 -- One row for each export bill (ExportBillInitiationMaster). The bill is not deleted and not cancelled.
 -- Lodgment date = BillGenerationDate, between @FromDate and @ToDate.
 -- Step 1: exchange rates of the purchase/discount records (#PurchaseDiscount).
 -- Step 2: charges and commission paid for each bill (#BillCharge, #BillOtherCharge, #BillCommCurrency).
 --         Each charge has one account number (see #ChargeAccount). The bill gets the sum of the PRS distribution
 --         amount and the voucher amount.
 -- Step 3: ARV (export proceeds against RMT) adjustments (#TempARV).
 -- Step 4: the register rows.
 -- Overdue_Days = days after the maturity date, when the bill has no realization (Remarks = 'Overdue').
 -- Exchange_Rate = exchange rate of the realization (PRSCreationDistributionDetails.ExchangeRate).
 -- BranchID, CustomerID, ApplicantID, EBIID and other ID columns are not shown. The Report Viewer filters use them.

Begin
	Set NoCount On;

	-- Step 1: exchange rates of the purchase/discount records
	select distinct
		M.ExchangeRate,
		M.LoanNumber,
		FinalEBIID = isnull(M.EBIID, (select top 1 C.EBIID from PurchaseDiscountForeignDocumentChild C with(nolock) where C.PDFDMID = M.PDFDMID))
	into #PurchaseDiscount
	from PurchaseDiscountForeignDocumentMaster M with(nolock)

	-- Step 2: charges. One account number for each charge.
	create table #ChargeAccount (Source varchar(20) not null, AccountNo varchar(20) not null)
	insert into #ChargeAccount (Source, AccountNo) values
		('Tax',				'202090210'),
		('CC',				'303010243'),
		('EXP Charge',		'304010322'),
		('Central Fund',	'202090563'),
		('Local',			'304010313'),
		('Foreign',			'304010323'),
		('Swift',			'304010325'),
		('CommPaid',		'202090529')

	-- PRS distribution amounts and voucher amounts
	select
		CA.Source,
		L.BillRefNo						EBIID,
		sum(L.FCCPER - L.D_Amount)		Amount
	into #Charge
	from PRSCreationDistributionDetails L with(nolock)
		inner join #ChargeAccount CA on CA.AccountNo = L.AC_NO
	where L.IsDeleted = 0 and L.IsSendTransactionToCBS = 1 and L.IsReversedFromCBS = 0
	group by CA.Source, L.BillRefNo
	union all
	select
		CA.Source,
		PRSM.EBIID,
		isnull(sum(VC.CreditTK - VC.DebitTK), 0)
	from VoucherInterfaceChild VC with(nolock)
		inner join VoucherInterfaceMaster VM with(nolock) on VM.MAEMID = VC.MAEMID
		inner join PRSCreationMaster PRSM with(nolock) on PRSM.PRSSysID = VM.EventID
		inner join #ChargeAccount CA on CA.AccountNo = VC.AccountNo
	where VC.IsDeleted = 0
	group by CA.Source, PRSM.EBIID

	select
		C.EBIID,
		Tax							= sum(case when C.Source = 'Tax' then C.Amount end),
		CollectionCommission		= sum(case when C.Source = 'CC' then C.Amount end),
		EXPCharge					= sum(case when C.Source = 'EXP Charge' then C.Amount end),
		OBLCentralFund				= sum(case when C.Source = 'Central Fund' then C.Amount end),
		PostageLocal				= sum(case when C.Source = 'Local' then C.Amount end),
		PostageForeign				= sum(case when C.Source = 'Foreign' then C.Amount end),
		SWIFTCommunicationCharge	= sum(case when C.Source = 'Swift' then C.Amount end),
		CommPaidAmount				= sum(case when C.Source = 'CommPaid' then C.Amount end)
	into #BillCharge
	from #Charge C
	group by C.EBIID

	-- Vessel tracking charge, government fee on jute and the currency of the commission paid (PRS rows)
	select
		L.BillRefNo		EBIID,
		VesselTrackingCharge	= sum(case when L.AC_NO = '304010357' then L.FCCPER end),
		GovtfeeonJute			= sum(case when L.AC_NO = '202090566' then L.FCCPER end),
		CommCurrency			= max(case when L.AC_NO = '202090529' then L.DistributedCCY end)
	into #BillOtherCharge
	from PRSCreationDistributionDetails L with(nolock)
	where L.IsDeleted = 0 and L.IsSendTransactionToCBS = 1 and L.IsReversedFromCBS = 0
		and L.AC_NO in ('304010357', '202090566', '202090529')
	group by L.BillRefNo

	-- Currency of the commission paid (voucher rows). Used when the PRS rows have no currency.
	select
		PRSM.EBIID,
		CommCurrency = max(VC.CCY)
	into #BillCommCurrency
	from VoucherInterfaceChild VC with(nolock)
		inner join VoucherInterfaceMaster VM with(nolock) on VM.MAEMID = VC.MAEMID
		inner join PRSCreationMaster PRSM with(nolock) on PRSM.PRSSysID = VM.EventID
	where VC.IsDeleted = 0 and VC.IsSendTransactionToCBS = 1 and VC.IsReversedFromCBS = 0 and VC.AccountNo = '202090529'
	group by PRSM.EBIID

	-- Step 3: ARV adjustments
	---ARV
SELECT 
                ISNULL(ARV.AdjustmentAmount, 0) + ISNULL(ARV.ForeignBankCharge, 0) + ISNULL(ARV.ForeignCommission, 0) + ISNULL(ARV.DiscountAmount, 0) RMTAdjustedAmount,ARV.EBIIRMTD EBIID,RealizeDate=RealizeDate into #TempARV
         FROM  (
			SELECT  ebaa.EBIIRMTD,SUM(rmtc.TotalRMTAmount)TotalRMTAmount,SUM(ebaa.AdjustmentAmount) AdjustmentAmount, SUM(ebaa.ForeignBankCharge) ForeignBankCharge, SUM(ebaa.ForeignCommission) ForeignCommission, 
			SUM(ebaa.DiscountAmount) DiscountAmount,RealizeDate=Max(ARVDATE)
			FROM 
			 RMTCreationMaster rmtc with(nolock)
			 Left Join (Select ebaa.EBIIRMTD, ebaa.RMTCCID,SUM(ebaa.AdjustmentAmount) AdjustmentAmount, SUM(ebaa.ForeignBankCharge) ForeignBankCharge, SUM(ebaa.ForeignCommission) ForeignCommission, SUM(ebaa.DiscountAmount) DiscountAmount,max(isnull(PRDS.SyncDate,ebaa.DateAdded)) ARVDATE from ExportBillAgainstRMTAdjustmentDetails ebaa with(nolock) 
			 LEFT JOIN (
										SELECT 
											BillRefNo,
											CONVERT(DATE, A.SyncTime) SyncDate,
											CASE
												WHEN ISNULL(A.SyncCount, 0) = ISNULL(A.SyncSum, 0) THEN 1
												ELSE 0
											END IsSync
										FROM (
											SELECT BillRefNo, MAX(TransactionSendingTimeToCBS) SyncTime, COUNT(IsSendTransactionToCBS) SyncCount, SUM(CAST(IsSendTransactionToCBS AS INT)) SyncSum
											FROM PRSCreationDistributionDetails 
											WHERE IsDeleted = 0
											GROUP BY BillRefNo
										) A
									) PRDS ON PRDS.BillRefNo = ebaa.EBIIRMTD
			 WHERE ebaa.IsDeleted = 0 AND ebaa.IsCancelled = 0
			  group by ebaa.EBIIRMTD, ebaa.RMTCCID) ebaa
			 
			 
			 on rmtc.RMTCMID=ebaa.RMTCCID
			 where rmtc.IsCancelled=0 and rmtc.IsDeleted=0
			GROUP BY ebaa.EBIIRMTD,rmtc.RMTCMID)ARV
--- END ARV

	-- Step 4: register rows
	select
		F.*,
		CommPaidAmountForeign	= case when F.CommCurruncy != 'BDT' then F.CommPaidAmount else null end,
		CommPaidAmountLocal		= case when F.CommCurruncy = 'BDT' then F.CommPaidAmount else null end
	from
	(
	SELECT distinct
		LodgmentDate=ebim.BillGenerationDate,	
		FDBCNumber	=Rtrim(Ltrim(ebim.ExportBillNo)),
		ClientName	=isnull(client.CustomerName,ebim.CustomerCode),
		CASE WHEN ISNULL(client.IsUsed,0) = 1 THEN 'EPZ' ELSE 'Non-EPZ' END AS CustomerType,	
		BuyerorApplicantName	=isnull(applicant.Name,ebim.ApplicantID),
		BuyerCountry=BuyersCountry.CountryName,	
		isnull(ADBranch.BranchName,ADBranch2.BranchName) AS ADBranch,
		NonADBranch = Case when Rtrim(Ltrim(isnull(Branch.BranchName,Branch2.BranchName)))=Rtrim(Ltrim(isnull(ADBranch.BranchName,ADBranch2.BranchName))) then '' Else isnull(Branch.BranchName,Branch2.BranchName) END,		
		BillCurr=ebim.CURRENCY_CODE,
		BillAmount=ebim.ExportBillAmount,	
		PaymentTermFromTenor=CASE 
			WHEN ebim.TenorType = 'Deferred' THEN CONCAT(Cast(ebim.TENOR_DAYS as Varchar(10)) , ' Days ',TenorDes.DisplayCode)
			 ELSE tenor.DisplayCode
		END ,	
		--PaymentTermFromTenor = ebim.billnature,
		InstrumentType=case when (md.IsSC=1 or lcar.LCSCTypeId='SC') then 'SC' Else 'LC' end,	
		
		LCorSCNumber=isnull(md.LCNo,lcar.LCNumber),	
		DocumentsReceivingBank.Name AS DocumentsReceivingBank,
		DocumentsReceivingBankCountry.CountryName AS CountryofDocumentsReceivingBank,
		LCIssuingBankCollectingBankPayingBank=isnull(issueingBank.Name,OpeningBank.Name),	
		CountryofLCIssuingBankCollectingBank=isnull(ibCountry.CountryName,obCountry.CountryName),

		NameoftheBankHavingNostroAccountwith=nostro.AccountName,	
		NostroAccountCountry=(Select top 1 cu.CountryName from [SystemManager]..Country cu
								inner join [SystemManager]..Contacts c on c.CountryID=cu.CountryID
								where c.SwiftCode=nostro.SwiftCode),


		PurchaseDate=pdf.date,--loandisbursedate
		PurchaseAmountFCY=Case when PDF.IsExportLoan=1 then PDF.Value/pdf.Exchangerate else PDF.Value end,
		ConversionRate	=A2.Exchangerate,
		PurchaseAmountBDT=Case when PDF.IsExportLoan=1 then PDF.Value2/pdf.Exchangerate else PDF.Value2 end,	

		SettlementDate	=Case 
		when PDF.IsExportLoan=1 then LPay.VALUE_DT
		when fdcm.IsPurchaseLoanType=0 then (Select CONVERT(Date,max(v.TransactionSendingTimeToCBS)) from PRSCreationDistributionDetails v WITH(NOLOCK)
			inner join [SystemManager]..BankProfileNostroAccounts n WITH(NOLOCK) on n.AccountNo=v.AC_NO where v.BillRefNo=fdcm.EBIID)
		when fdcm.IsPurchaseLoanType=1 then (Select CONVERT(Date,Max(l.DateAdded)) from [EFA]..CustomerVoucherTransDetails l where l.AdditionalFilter='Purchase Discount Foreign Document Master' and CreditAccountNo='503010101' and fdcm.ExternalID=l.AdditionalMasterID)
		 end,
		fdcm.ExternalID,

		CourierDate.CourierDate AS DocumentsForwardingDate,
		CourierName	=CourierCompany.CourierCompany,
		CourierReceiptNumber=CourierReceipt.CourierReceipt,	
		BillAcknowledgementDate	=isnull(ebm.AckReceivedOnDate,ebim.AcceptanceReceivedOnDate),
		DiscrepancyDate	=isnull(ebm.DiscrepancyReceivedOnDate,ebim.DiscrepancyReceivedOnDate ),
		MaturityDate	=isnull(ebm.MaturityDate,ebim.MaturityDate ),
		RealizedDate	=Case 
		when PRSM.Date is null then (Select max(arv.RealizeDate) from #TempARV arv where arv.ebiid=ebim.ebiid)
		when (Select max(arv.RealizeDate) from #TempARV arv where arv.ebiid=ebim.ebiid) is null then PRSM.Date
		when PRSM.Date is not null and (Select max(arv.RealizeDate) from #TempARV arv where arv.ebiid=ebim.ebiid) is not null and PRSM.Date>(Select max(arv.RealizeDate) from #TempARV arv where arv.ebiid=ebim.ebiid)
		then PRSM.Date
		else (Select max(arv.RealizeDate) from #TempARV arv where arv.ebiid=ebim.ebiid) end
		,
		RealizedFromDate=Isnull(PRSM.Date,null),
		RealizedToDate=Isnull(PRSM.Date,null),
		RealizedAmount=Isnull(PRSM.RealizedValue,0)+Isnull((Select Sum(arv.RMTAdjustedAmount) from #TempARV arv where arv.ebiid=ebim.ebiid),0),
		PRSM.RealizedValue,
		
		PartialPaymentReceivedDate=(CASE WHEN (CAST((m.ShortAmount / CASE WHEN m.PaymentType = 'ARV' THEN m.C_Amount ELSE Ebim.ExportBillAmount END) * 100 AS DECIMAL(18, 2)))>5 THEN PRSM.Date ELSE NULL END),
		PartialPaymentReceivedAmount=CASE WHEN (CAST((m.ShortAmount / CASE WHEN m.PaymentType = 'ARV' THEN m.C_Amount ELSE Ebim.ExportBillAmount END) * 100 AS DECIMAL(18, 2)))>5 THEN PRSM.RealizedValue ELSE NULL END,	
		Remarks=CASE
	            WHEN ISNULL(EBIM.IsCancelled, 0) = 0
					THEN 
						CASE 					   
	   						WHEN PRSM.BillRefNo IS NOT NULL
	   						THEN
							CASE
								WHEN  ISNULL(PRSM.FinalLiquidation, 0) > 0
								THEN 'Regular (and fully liquidated)'
								ELSE 'Regular (and partially liquidated)'
							END
	   						ELSE
							CASE 
								WHEN CONVERT(DATE, ebm.MaturityDate) < CONVERT(DATE, GETDATE()) THEN 'Overdue'
								ELSE 'Regular'
							END
						END
				ELSE
	            CASE
	   		        WHEN EBIM.ReplacementEBIID IS NOT NULL
	   		        THEN 'Cancelled (and Rpl by another)'
	   		        ELSE 'Cancelled'
	            END
            END,
		Tax							= CH.Tax,
		CollectionCommission		= CH.CollectionCommission,
		EXPCharge					= CH.EXPCharge,
		OBLCentralFund				= CH.OBLCentralFund,
		PostageLocal				= CH.PostageLocal,
		PostageForeign				= CH.PostageForeign,
		SWIFTCommunicationCharge	= CH.SWIFTCommunicationCharge,
		VesselTrackingCharge		= OC.VesselTrackingCharge,
		GovtfeeonJute				= OC.GovtfeeonJute,
		CommPaidAmount				= CH.CommPaidAmount,
		BuyingHouseNameForeign=Case when fstBeniCountry.CountryName !='Bangladesh' and  fstBeniCountry.CountryCode !='BD' then fstBeni.Name Else '' end,
		CommCurruncy				= isnull(OC.CommCurrency, CCY.CommCurrency),
		BuyingHouseNameLocal=Case when fstBeniCountry.CountryName ='Bangladesh' or  fstBeniCountry.CountryCode='BD' then fstBeni.Name Else '' end,
		BillNature=Isnull(BillNature.DisplayCode,ebim.BillNature),
		-- Parameters--
		ebim.EBIID, -- FDBC No
		CustomerID=isnull(ebim.CustomerCode,lcar.Beneficiary),
	    ApplicantID=	isnull(md.Applicant,lcar.Applicant),
		isnull(ADBranch.ADBranchID,ADBranch2.ADBranchID) ADBranchID,
		isnull(Branch.BranchID, Branch2.BranchID) BranchID,
		CASE WHEN ISNULL(client.IsUsed,0) = 1 THEN 'EPZ' ELSE 'Non-EPZ' END AS EPZnonEPZ,	
		PaymentTerm=ebim.TenorType,
		isnull(md.MasterDocID,lcar.LCReceiveID) MasterDocID,
		PurchasedDiscountedThrough=Case 
		when PDF.IsExportLoan=1 then 'Export Loan'
		when fdcm.IsPurchaseLoanType=0 then 'OBU'
		when fdcm.IsPurchaseLoanType=1 then 'CTPC'
		 end,
		 fdcm.LoanNumber,
		 Transaction_Ref = ebim.ExternalID,
		 Customer_ID = client.CIF,
		 LCSC_Date = LCAD.IssueDate,
		 LCSC_Value = LCAD.LCAmount,
		 Job_Number = GLC.GroupRefNo,
		 Overdue_Days = case
			when PRSM.BillRefNo is null and CONVERT(DATE, isnull(ebm.MaturityDate, ebim.MaturityDate)) < CONVERT(DATE, GETDATE())
			then DATEDIFF(DAY, isnull(ebm.MaturityDate, ebim.MaturityDate), GETDATE())
			end,
		 Exchange_Rate = PRSM.ExchangeRate
		from ExportBillInitiationMaster ebim with(nolock)
		
		
		LEFT JOIn ExportBillMonitoring ebm with(nolock) on ebm.EBIID=ebim.EBIID	
		
		LEFT JOIN SystemManager..EntityFixedVariables  tenor ON tenor.EntityID=ebim.TenorType
		LEFT JOIN MasterDoc md with(nolock)  on md.MasterDocID=ebim.MasterDocID
		Left join [SystemManager]..Contacts fstBeni with(nolock) on Rtrim(ltrim(fstBeni.Name))=Rtrim(ltrim(md.FirstBeneficiary))
		Left join [SystemManager]..Country fstBeniCountry with(nolock) on fstBeniCountry.CountryID=fstBeni.CountryID
		LEFT JOIN LCAdvisingRegister lcar with(nolock)  on lcar.LCReceiveID=isnull(md.LCReceiveID,ebim.MasterDocID)
		LEFT JOIN PurchaseDiscountForeignDocumentMaster fdcm with(nolock) on fdcm.EBIID=ebim.EBIID and fdcm.IsCancelled=0 and fdcm.IsDeleted=0
		LEFT JOIN LCAdvisingRegister LCAD with(nolock) ON LCAD.LCReceiveID = ISNULL(md.LCReceiveID, ebim.MasterDocID)
		LEFT JOIN GROUPLC GLC with(nolock) ON GLC.GroupSysID = MD.GroupSysID
	    
		LEFT JOIN (
		Select EBIID,Sum(pm.ShortAmount)ShortAmount,PaymentType=Max(pm.PaymentType),Sum(pm.C_Amount)C_Amount from
		PRSCreationMaster  pm group by pm.EBIID
		)M ON M.EBIID = ebim.EBIID
		LEFT JOIN SystemManager..EntityFixedVariables  BillNature ON BillNature.EntityID=ebim.BillNature
		LEFT JOIN SystemManager..BankProfileNostroAccounts nostro on nostro.BPNACID=ebim.NostroAccount								   
		LEFT JOIN SystemManager..Contacts applicant on applicant.Code=isnull(md.Applicant,lcar.Applicant)
		LEFT JOIN SystemManager..Country BuyersCountry on BuyersCountry.CountryID=applicant.CountryID
		LEFT JOIN SystemManager..BankProfileBranch Branch ON Branch.BranchID = GLC.BankBranchID
		LEFT JOIN SystemManager..BankProfileBranch ADBranch ON ADBranch.BranchID = GLC.ADBranchID
		LEFT JOIN SystemManager..BankProfileBranch Branch2 ON Branch2.BranchID = LCAD.BranchID
		LEFT JOIN SystemManager..BankProfileBranch ADBranch2 ON ADBranch2.BranchID = LCAD.ADBranchID
		LEFT JOIN SystemManager..EntityFixedVariables  tenordes on tenordes.EntityID=ebim.TenorDescription
		LEFT JOIN SystemManager..Contacts OpeningBank on OpeningBank.Code=isnull(md.OpeningBankCode,lcar.BankID)
		LEFT JOIN SystemManager..Contacts issueingBank on issueingBank.Code=lcar.BankID

		LEFT JOIN SystemManager..Contacts DocumentsReceivingBank ON DocumentsReceivingBank.Code = EBIM.DocSendToBank
		LEFT JOIN SystemManager..Country DocumentsReceivingBankCountry ON DocumentsReceivingBankCountry.CountryID = DocumentsReceivingBank.CountryID 
		 
		LEFT JOIN SystemManager..Country obCountry on obCountry.CountryID=OpeningBank.CountryID
		LEFT JOIN SystemManager..Country ibCountry on ibCountry.CountryID=issueingBank.CountryID
		
		left join SystemManager..CustomerProfileMaster client with(nolock) on client.CustomerID=ebim.CustomerCode
		LEFT JOIN (SELECT MasterId EBIID ,
							STUFF((SELECT distinct ', ' +  CourierReceipt
										FROM CourierInfo CombinedE with(nolock)
										WHERE CombinedE.MasterId = E.MasterId
										FOR XML PATH('')),1,1,'') AS CourierReceipt
					FROM  CourierInfo E  GROUP BY MasterId) CourierReceipt ON CourierReceipt.EBIID = EBIM.EBIID
		LEFT JOIN (SELECT MasterId EBIID ,
							STUFF((SELECT distinct ', ' +  FORMAT(CourierDate,'dd-MM-yyyy') 
										FROM CourierInfo CombinedE with(nolock)
										WHERE CombinedE.MasterId = E2.MasterId
										FOR XML PATH('')),1,1,'') AS CourierDate
					FROM  CourierInfo E2  GROUP BY MasterId) CourierDate ON CourierDate.EBIID = EBIM.EBIID
		LEFT JOIN ( SELECT MasterId EBIID ,
							STUFF((SELECT distinct ', ' +  Name
										FROM (SELECT A.Name,MasterId FROM CourierInfo B
										LEFT JOIN SystemManager..Contacts A ON  A.CODE = B.CourierCompany) CombinedE  
										WHERE CombinedE.MasterId = E.MasterId
										FOR XML PATH('')),1,1,'') AS CourierCompany
					FROM  (SELECT A.Name,MasterId FROM CourierInfo B
						  LEFT JOIN SystemManager..Contacts A ON  A.CODE = B.CourierCompany) E  
						  GROUP BY MasterId) CourierCompany ON CourierCompany.EBIID = ebim.EBIID
	LEFT JOIN (
				SELECT distinct M.BillRefNo, MAX(M.Date) Date, MAX(M.ExchangeRate) ExchangeRate, SUM(M.ProceedsRecvd) RealizedValue, MAX(Syncdate) Syncdate,MAX(CAST(ISNULL(M.FinalLiquidation, 0) AS int)) FinalLiquidation
				FROM
				(
					SELECT P.BillRefNo, MAX(P.TransactionSendingTimeToCBS) Date, MAX(P.ProceedsRecvd) ProceedsRecvd, MAX(P.UBSSynctime) Syncdate,MAX(P.ExchangeRate) ExchangeRate,MAX(CAST(M.IsFinalLiquidation AS int)) FinalLiquidation,p.PRSSysID
					FROM PRSCreationDistributionDetails P
					INNER JOIN PRSCreationMaster M ON M.PRSSysID = P.PRSSysID
					WHERE P.IsDeleted = 0 and p.IsSendTransactionToCBS=1 and p.IsReversedFromCBS=0
					GROUP BY P.BillRefNo, P.Date,p.PRSSysID
				) M
				GROUP BY M.BillRefNo
			) PRSM ON PRSM.BillRefNo = EBIM.EBIID
	LEFT JOIN (
				SELECT M1.EBIID, MAX(Exchangerate)Exchangerate, MAX(M1.addate) addate, MAX(M1.Date) Date, SUM(M1.Value) Value, SUM(M1.Value2) Value2,IsExportLoan=Max(M1.IsExportLoan)
				FROM
				(
					SELECT isnull(PD.EBIID,PDD.EBIID) EBIID, Max(PD.Exchangerate)Exchangerate, MAX(PD.AdjustmentStartDate) addate, MAX(PD.applydate) Date, MAX(PD.DisbursedAmount) Value, max(pd.DisbursedAmount*ExchangeRate) Value2,Max(Cast(pd.IsExportLoan as int))IsExportLoan
					FROM PurchaseDiscountForeignDocumentMaster PD
					LEFT JOIN PurchaseDiscountForeignDocumentChild PDD ON PDD.PDFDMID = PD.PDFDMID
					WHERE PD.IsDeleted = 0 and PD.loannumber is not null
					GROUP BY PD.EBIID, PD.applydate, PDD.EBIID
				) M1 
				GROUP BY M1.EBIID 
			) PDF ON PDF.EBIID = EBIM.EBIID

		LEFT JOIN (SELECT EBIID=E1.FinalEBIID  ,
							STUFF((SELECT distinct ', ' +  cast(ExchangeRate as varchar)
										FROM #PurchaseDiscount CombinedE with(nolock)										
										WHERE CombinedE.FinalEBIID = E1.FinalEBIID AND CombinedE.LoanNumber is not null 
										FOR XML PATH('')),1,1,'') AS Exchangerate
					FROM  #PurchaseDiscount E1	
					where E1.FinalEBIID is not null
					GROUP BY FinalEBIID
					) A2 ON A2.EBIID = EBIM.EBIID
LEFT JOIN (
		                    SELECT RELATED_ACCOUNT, SUM(LCY_AMOUNT) LCY_AMOUNT, SUM(FCY_AMOUNT) FCY_AMOUNT, MAX(VALUE_DT) VALUE_DT
			                FROM LoanPayment with(nolock) 
			                WHERE IsDeleted = 0 AND DRCR_IND = 'C' 
			                GROUP BY RELATED_ACCOUNT
	                    ) LPay ON LPay.RELATED_ACCOUNT = fdcm.Account_Number
		LEFT JOIN #BillCharge CH on CH.EBIID = ebim.EBIID
		LEFT JOIN #BillOtherCharge OC on OC.EBIID = ebim.EBIID
		LEFT JOIN #BillCommCurrency CCY on CCY.EBIID = ebim.EBIID
		where ebim.IsDeleted = 0 and ebim.IsCancelled = 0
			and cast(ebim.BillGenerationDate as date) between @FromDate and @ToDate
	) F
	order by F.FDBCNumber asc
End
GO
