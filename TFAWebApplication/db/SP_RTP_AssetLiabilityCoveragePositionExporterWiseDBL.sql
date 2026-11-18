USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RTP_AssetLiabilityCoveragePositionExporterWiseDBL]    Script Date: 11/18/2026 12:31:07 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[SP_RTP_AssetLiabilityCoveragePositionExporterWiseDBL]
	@BranchID    VARCHAR(50),
	@CustomerID	 VARCHAR(50)
AS									
	-- SP_RTP_AssetLiabilityCoveragePositionExporterWiseDBL 'OBPB/2020/9', '21Aug202C/1379'
BEGIN
	DECLARE @Amount2Million DECIMAL(18,6) = 0.000001
	
	SELECT CustomerName,BranchID,CustomerID,
		CASE WHEN SUM(ISNULL(DocumentsUnderCollection,0)) > 0 THEN SUM(ISNULL(DocumentsUnderCollection,0)) ELSE 0 END DocumentsUnderCollection,
		CASE WHEN SUM(ISNULL(ExportLC_in_hand_ConfirmedSales_contract_in_hand,0)) > 0 THEN SUM(ISNULL(ExportLC_in_hand_ConfirmedSales_contract_in_hand,0)) ELSE 0 END ExportLC_in_hand_ConfirmedSales_contract_in_hand,
		SUM(BBLCWithTolAmount)BBLCWithTolAmount,SUM(SavedAndGeneratedBTBBillAmount)SavedAndGeneratedBTBBillAmount,SUM(OutstandingSGAmount)OutstandingSGAmount,
		CASE WHEN SUM(ISNULL(BBLC,0)) > 0 THEN SUM(ISNULL(BBLC,0)) ELSE 0 END BBLC,
		0 DFCBalance,
		CASE WHEN SUM(ISNULL(ABP,0)) > 0 THEN SUM(ISNULL(ABP,0)) ELSE 0 END ABP,
		SUM(DocNotLodgeYet) DocNotLodgeYet,
		CASE WHEN SUM(ISNULL(SG,0)) > 0 THEN SUM(ISNULL(SG,0)) ELSE 0 END SG,
		CASE WHEN SUM(ISNULL(EDF,0)) > 0 THEN SUM(ISNULL(EDF,0)) ELSE 0 END EDF,
		CASE WHEN SUM(ISNULL(ABP_M,0)) > 0 THEN SUM(ISNULL(ABP_M,0)) ELSE 0 END ABP_M,
		SUM(DocNotLodgeYet_M) DocNotLodgeYet_M,
		CASE WHEN SUM(ISNULL(SG_M,0)) > 0 THEN SUM(ISNULL(SG_M,0)) ELSE 0 END SG_M,
		CASE WHEN SUM(ISNULL(EDF_M,0)) > 0 THEN SUM(ISNULL(EDF_M,0)) ELSE 0 END EDF_M,
		CASE WHEN SUM(ISNULL(FLAB_M,0)) > 0 THEN SUM(ISNULL(FLAB_M,0)) ELSE 0 END FLAB_M,
		CASE WHEN SUM(ISNULL(PC,0)) > 0 THEN SUM(ISNULL(PC,0)) ELSE 0 END PC,
		CASE WHEN SUM(ISNULL(FDBP,0)) > 0 THEN SUM(ISNULL(FDBP,0)) ELSE 0 END FDBP,
		CASE WHEN SUM(ISNULL(Documents_under_collection_unpurchased,0)) > 0 THEN SUM(ISNULL(Documents_under_collection_unpurchased,0)) ELSE 0 END Documents_under_collection_unpurchased,
		CASE WHEN SUM(ISNULL(Documents_under_collection_unpurchased_M,0)) > 0 THEN SUM(ISNULL(Documents_under_collection_unpurchased_M,0)) ELSE 0 END Documents_under_collection_unpurchased_M,
		CASE WHEN SUM(ISNULL(OutstandingBBLCAmount,0)) > 0 THEN SUM(ISNULL(OutstandingBBLCAmount,0)) ELSE 0 END OutstandingBBLCAmount, MAX(CURRENCY_CODE) CURRENCY_CODE, MAX(ConvertFactor) ConvertFactor,
		SUM(ISNULL(TimeLoan, 0)) TimeLoan, SUM(ISNULL(STLWC, 0)) STLWC,
		CASE WHEN SUM(ISNULL(FLAB,0)) > 0 THEN SUM(ISNULL(FLAB,0)) ELSE 0 END FLAB
	FROM(
		SELECT CustomerName,Customer.BranchID,Customer.CustomerID,	
		ISNULL(ALLData.UnRealizedValue,0)  DocumentsUnderCollection,
		ISNULL(ALLData.TotalExportLCSCAmount,0) - (ALLData.ExportBillAmount + ALLData.ClosedAmount) ExportLC_in_hand_ConfirmedSales_contract_in_hand ,
		BBLCWithTolAmount,SavedAndGeneratedBTBBillAmount,OutstandingSGAmount,
		--ISNULL(ALLData.BBLCWithTolAmount,0) - (ISNULL(ALLData.SavedAndGeneratedBTBBillAmount,0) + ISNULL(ALLData.OutstandingSGAmount,0) + (ALLData.BBLCClosedAmount) + (ALLData.DocNotLodgeYet)) BBLC,
		ISNULL(ALLData.OutstandingBBLCAmount,0) BBLC,
		0 DFCBalance,
		ISNULL(ALLData.OutstandingBTBBillAmount,0) ABP,
		ISNULL(ALLData.OutstandingSGAmount,0) SG,
		ISNULL(ALLData.OutstandingEDFAmount,0) EDF,
		ISNULL(ALLData.OutstandingFLABAmount,0) FLAB,
		ISNULL(ALLData.OutstandingPCAmount,0) PC,
		(ISNULL(ALLData.FDBPAmount,0) + ISNULL(ALLData.FDBPLocalAmount,0)) FDBP,
		ISNULL(ALLData.DocumentsUnderCollectionUnpurchasedAmount,0)Documents_under_collection_unpurchased,
		(CAST(ISNULL(ALLData.DocumentsUnderCollectionUnpurchasedAmount,0) AS DECIMAL(20,10)) * @Amount2Million) Documents_under_collection_unpurchased_M,
		(CAST(ISNULL(ALLData.OutstandingBBLCAmount,0) AS DECIMAL(20,10)) * @Amount2Million)  OutstandingBBLCAmount,
		(CAST(ISNULL(ALLData.OutstandingBTBBillAmount,0) AS DECIMAL(20,10)) * @Amount2Million) ABP_M,
		(CAST(ISNULL(ALLData.OutstandingSGAmount,0) AS DECIMAL(18,6)) * @Amount2Million) SG_M,
		(CAST(ISNULL(ALLData.OutstandingEDFAmount,0) AS DECIMAL(20,10)) * @Amount2Million) EDF_M,
		(CAST(ISNULL(ALLData.OutstandingFLABAmount,0) AS DECIMAL(20,10)) * @Amount2Million) FLAB_M,
		CURRENCY_CODE, ConvertFactor, 
		ISNULL(DocNotLodgeYet, 0) DocNotLodgeYet, 
		ISNULL(DocNotLodgeYet, 0) * @Amount2Million DocNotLodgeYet_M,
		ISNULL(TimeLoan, 0) TimeLoan,
		ISNULL(STLWC, 0) STLWC

	FROM (

	--Time loan

	SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
		           0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount,0 OutstandingBBLCAmount,0 FDBPLocalAmount ,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, SUM(ISNULL(TimeLoanOutAmount,0)) TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
		FROM (
			SELECT P.CustomerID, P.BranchID, CURRENCY CURRENCY_CODE, ConvertFactor, case when P.UBSSyncProcessID > 0 then TOT_OS * ConvertFactor else p.DisbursedAmount * ConvertFactor end TimeLoanOutAmount
			FROM PurchaseDiscountForeignDocumentMaster P
				LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(P.CURRENCY, '') AND CLR.RateFor = 'BC SELLING'
			WHERE P.IsDeleted = 0 AND P.IsExportLoan = 1 AND P.LoanNumber IS NOT NULL AND P.PRODUCT_CODE IN ('TMLN', 'OTML')
		) TimeLoan
		WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
		GROUP BY BranchID,CustomerID, CURRENCY_CODE, ConvertFactor

		union all

	--STLWC

	SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
		           0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount,0 OutstandingBBLCAmount,0 FDBPLocalAmount ,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, SUM(ISNULL(TimeLoanOutAmount,0)) STLWC, 0 OutstandingFLABAmount
		FROM (
			SELECT P.CustomerID, P.BranchID, CURRENCY CURRENCY_CODE, ConvertFactor, case when P.UBSSyncProcessID > 0 then TOT_OS * ConvertFactor else p.DisbursedAmount * ConvertFactor end TimeLoanOutAmount
			FROM PurchaseDiscountForeignDocumentMaster P
				LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(P.CURRENCY, '') AND CLR.RateFor = 'BC SELLING'
			WHERE P.IsDeleted = 0 AND P.IsExportLoan = 1 AND P.LoanNumber IS NOT NULL AND P.PRODUCT_CODE IN ('STLN', 'STLO', 'OSTL')
		) TimeLoan
		WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
		GROUP BY BranchID,CustomerID, CURRENCY_CODE, ConvertFactor

		union all

	--Start Doc Under Collection
		 SELECT E.BranchID, E.CustomerCode CustomerID, 0 ExportBillAmount, SUM(ExportBillAmount) UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount ,
					0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
		FROM (
			SELECT EBIID, (ExportBillAmount * ConvertFactor) ExportBillAmount, CustomerCode, BranchID, CURRENCY_CODE, ConvertFactor
			FROM ExportBillInitiationMaster E 
					INNER JOIN (
						SELECT MasterDocID FROM MasterDoc WHERE GroupSysID IS NOT NULL AND IsDeleted = 0 AND IsCancelled = 0
					) MD ON MD.MasterDocID = E.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
				WHERE E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL AND IsARVAdjusted = 0
		) E 
		left join PRSCreationDistributionDetails d on ISNULL(d.BillRefNo, '') = E.EBIID AND d.PRSNCADID != 'NOT_NCA'
		WHERE E.BranchID = @BranchID AND E.CustomerCode = @CustomerID AND d.BillRefNo IS NULL
		GROUP BY E.BranchID, E.CustomerCode, CURRENCY_CODE, ConvertFactor
					
		UNION ALL

			SELECT E.BranchID, E.CustomerCode CustomerID, 0 ExportBillAmount, SUM(ExportLocalBillAmount) UnRealizedValue, 0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount ,
					0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT EBIID,(ExportLocalBillAmount * ConvertFactor)ExportLocalBillAmount,CustomerCode,BranchID, CURRENCY_CODE, ConvertFactor 
				FROM LocalExportBillInitiationMaster E
					 INNER JOIN (SELECT MasterDocID FROM MasterDoc WHERE GroupSysID IS NOT NULL AND IsDeleted = 0 AND IsCancelled = 0
					 ) MD ON MD.MasterDocID = E.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
					WHERE E.IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
			) E 
			left join PRSCreationDistributionDetails d on ISNULL(d.BillRefNo, '') = E.EBIID AND d.PRSNCADID != 'NOT_NCA' 
		WHERE E.BranchID = @BranchID AND E.CustomerCode = @CustomerID AND d.BillRefNo IS NULL
		GROUP BY E.BranchID, E.CustomerCode, CURRENCY_CODE, ConvertFactor 

		--End of Doc Under Collection

		UNION ALL

		-- LC Outs
		select 
			BankBranchID BranchID, CustomerID, 0 ExportBillAmount, 0 UnRealizedValue, 0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount ,
					0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount , SUM(BBLCOutAmount_BDT) OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					Currency CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
		from (
			select 
				BankBranchID, CustomerID, Year, Currency, ConvertFactor, BBLCID, case when (ISNULL(BBLCAmount, 0) - ISNULL(BillAmount, 0) - ISNULL(SGAmount, 0) - ISNULL(ClosedAmount, 0)) < 0 then 0 else (ISNULL(BBLCAmount, 0) - ISNULL(BillAmount, 0) - ISNULL(SGAmount, 0) - ISNULL(ClosedAmount, 0)) end BBLCOutAmount, case when (ISNULL(BBLCAmount_BDT, 0) - ISNULL(BillAmount_BDT, 0) - ISNULL(SGAmount_BDT, 0) - ISNULL(ClosedAmount_BDT, 0)) < 0 then 0 else (ISNULL(BBLCAmount_BDT, 0) - ISNULL(BillAmount_BDT, 0) - ISNULL(SGAmount_BDT, 0) - ISNULL(ClosedAmount_BDT, 0)) end BBLCOutAmount_BDT
			from (
				select
					g.BankBranchID,
					g.CustomerID,
					YEAR(m.IssueDate) Year,
					m.Currency,
					clr.ConvertFactor,
					m.BBLCID,
					BBLCAmount = m.BBLCAmount + (m.BBLCAmount * Toleranace/100),
					BBLCAmount_BDT = (m.BBLCAmount + (m.BBLCAmount * Toleranace/100)) * clr.ConvertFactor,
					ClosedAmount = case when m.IsClosed = 1 then clo.CLOSED_VALUE else 0 end,
					ClosedAmount_BDT = case when m.IsClosed = 1 then clo.CLOSED_VALUE * clr.ConvertFactor else 0 end,
					BillAmount = bill.BillAmount,
					BillAmount_BDT = bill.BillAmount * clr.ConvertFactor,
					SGAmount = sg.Amount,
					SGAmount_BDT = sg.Amount * clr.ConvertFactor
				from BBLCMaster m
					inner join BBLCIssuance b on b.BBLCID = m.BBLCID
					inner join GroupLC g on g.GroupSysID = m.GroupSysID
					left join SystemManager..CustomerProfileMaster cpm on cpm.CustomerID = g.CustomerID
					left join SystemManager..BankProfileBranch bpb on bpb.BranchID = g.BankBranchID
					left join SystemManager..CurrencyLatestRate clr on clr.CurrencyCode = m.Currency and clr.RateFor = 'BC SELLING'
					left join ClosureTransaction clo on clo.UBS_CONT_REF_NO = m.ExternalID and clo.IsDeleted = 0
					left join (
						select BBLCID, SUM(BillAmount) BillAmount 
						from ForeignDocumentAcceptanceMaster
						where IsDeleted = 0 and IsCancelled = 0 and BillNo is not null
						group by BBLCID
					) bill on bill.BBLCID = m.BBLCID
					left join (
						select sm.ImportOrBBLCID, SUM(sm.Amount) Amount
						from ShippingGuaranteeMaster sm
							left join ForeignDocumentShippingGuaranteeMap fsm on fsm.SGMID = sm.SGMID and fsm.IsDeleted = 0 and fsm.IsCancelled = 0
						where sm.IsDeleted = 0 and sm.IsCancelled = 0 and sm.SGRefNo is not null and fsm.SGMID is null
						group by ImportOrBBLCID

						union

						select sm.ImportOrBBLCID, SUM(sm.Amount) Amount
						from ShippingGuaranteeMaster sm
							inner join ForeignDocumentShippingGuaranteeMap fsm on fsm.SGMID = sm.SGMID
							inner join ForeignDocumentAcceptanceMaster bm on bm.FDAID = fsm.FDAID
						where sm.IsDeleted = 0 and sm.IsCancelled = 0 and sm.SGRefNo is not null and bm.BillNo is null
						group by ImportOrBBLCID
					) sg on sg.ImportOrBBLCID = m.BBLCID
				where m.IsDeleted = 0 and m.IsCancelled = 0 and m.BBLCNo is not null and g.IsDeleted = 0 and g.IsClosedGroup = 0
					and g.BankBranchID = @BranchID and g.CustomerID = @CustomerID
			) A
			where (ISNULL(BBLCAmount, 0) - ISNULL(BillAmount, 0) - ISNULL(SGAmount, 0) - ISNULL(ClosedAmount, 0)) > 0
		) LCOut
		group by BankBranchID, CustomerID, Currency, ConvertFactor

		--end lc outs



			UNION ALL



			SELECT BranchID,CustomerID,SUM(ExportBillAmount) ExportBillAmount, 0 UnRealizedValue,SUM(LCAmount)TotalExportLCSCAmount, SUM(ClosedAmount) ClosedAmount,0 BBLCWithTolAmount,
			           0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					   0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount,0 FDBPLocalAmount ,
					   0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					   Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM(
				SELECT G.GroupSysID, ((LCAmount + (LCAmount * TolerancePercent / 100 )) * ConvertFactor) LCAmount, G.BankBranchID BranchID, G.CustomerID CustomerID, M.ExternalID, CASE WHEN M.IsClosed = 1 THEN (ISNULL(Closed.CLOSED_VALUE, 0) * ConvertFactor) ELSE 0 END ClosedAmount, M.Currency, ConvertFactor, (Bill.ExportBillAmount * ConvertFactor)  ExportBillAmount
				FROM MasterDoc M
					INNER JOIN (SELECT GroupSysID,BankBranchID,CustomerID FROM GroupLC WHERE IsDeleted = 0 AND IsClosedGroup = 0
					) G ON G.GroupSysID = M.GroupSysID
					LEFT JOIN (
						SELECT UBS_CONT_REF_NO, CLOSED_VALUE FROM ClosureTransaction WHERE IsDeleted = 0
					) Closed ON Closed.UBS_CONT_REF_NO = M.ExternalID
					LEFT JOIN (
						select MasterDocID, SUM(ExportBillAmount) ExportBillAmount
						from (
							select MasterDocID, ExportBillAmount from ExportBillInitiationMaster where IsDeleted = 0 and ISNULL(IsCancelled, 0) = 0 and ExportBillNo is not null
							union
							select MasterDocID, ExportLocalBillAmount from LocalExportBillInitiationMaster where IsDeleted = 0 and ISNULL(IsCancelled, 0) = 0 and ExportLocalBillNo is not null
						) B
						GROUP BY MasterDocID
					) Bill on Bill.MasterDocID = M.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(M.Currency, '') AND CLR.RateFor = 'BC SELLING'
					WHERE M.IsDeleted = 0 AND M.IsCancelled = 0
			)MD
			WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
			GROUP BY BranchID,CustomerID, Currency, ConvertFactor

		--End of Export LC in Hand

		UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			           0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					   0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount , 0 BBLCClosedAmount,0 OutstandingBBLCAmount  ,0 FDBPLocalAmount,
					   0 DocumentsUnderCollectionUnpurchasedLoclAmount, Currency, ConvertFactor,
					   SUM(OnlySavedBills) DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT ISNULL(BillAmount,0) * ConvertFactor AS OnlySavedBills,
					   BranchID,CustomerID, FDAM.Currency, ConvertFactor 
				FROM (
					SELECT ISNULL(BillAmount,0) AS BillAmount,BBLCID,FDAID,BranchID,CustomerID,Currency 
					FROM ForeignDocumentAcceptanceMaster 
					WHERE IsDeleted = 0 AND IsCancelled = 0 AND BillNo IS NULL
				) FDAM 
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(FDAM.Currency, '') AND CLR.RateFor = 'BC SELLING'
					INNER JOIN (SELECT BBLCID FROM BBLCMaster WHERE IsDeleted = 0 AND IsCancelled = 0 AND BBLCNo IS NOT NULL
					) BBLCM ON BBLCM.BBLCID = FDAM.BBLCID 	   
			)A
			WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
			GROUP BY BranchID,CustomerID, Currency, ConvertFactor

           --END OF DocNotLodge

			UNION ALL 


			SELECT BankBranchID BranchID, CustomerID, 0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount, SUM(LCAmount) BBLCWithTolAmount,
			           0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					   0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount,SUM(ClosedAmount) BBLCClosedAmount ,0 OutstandingBBLCAmount,0 FDBPLocalAmount ,
					   0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					   Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT BankBranchID, ((BBLCAmount + (BBLCAmount * Toleranace / 100 )) * ConvertFactor) LCAmount,
					   B.GroupSysID, GLC.CustomerID, B.ExternalID, CASE WHEN B.IsClosed = 1 THEN (ISNULL(Closed.CLOSED_VALUE, 0) * ConvertFactor) ELSE 0 END ClosedAmount, Currency, ConvertFactor 
				FROM BBLCMaster B (NOLOCK)
					   INNER JOIN (SELECT * FROM GroupLC WHERE IsDeleted = 0 AND IsClosedGroup = 0) GLC ON GLC.GroupSysID = B.GroupSysID
					   LEFT JOIN (SELECT UBS_CONT_REF_NO, CLOSED_VALUE  FROM ClosureTransaction  WHERE IsDeleted = 0 
					   ) Closed ON Closed.UBS_CONT_REF_NO = B.ExternalID
					   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(B.Currency, '') AND CLR.RateFor = 'BC SELLING'
				WHERE B.IsDeleted = 0 AND B.IsCancelled = 0 AND B.BBLCNo IS NOT NULL
			)BBLC	
			WHERE  BankBranchID = @BranchID AND CustomerID = @CustomerID 						
			GROUP BY BankBranchID,CustomerID, Currency, ConvertFactor

	--END OF BBLCWithTol

			UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			           0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					   0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount , 0 BBLCClosedAmount,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					   0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					   Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT BranchID,CustomerID,BBLCAmount, Currency, ConvertFactor 
				FROM  (
					SELECT BranchID,CustomerID,BBLCID,Currency,(BBLCAmount * ConvertFactor)BBLCAmount, ConvertFactor 
					FROM BBLCMaster B
					   INNER JOIN (SELECT BankBranchID BranchID,CustomerID,GroupSysID FROM GroupLC WHERE IsDeleted = 0 and IsClosedGroup = 0
					   ) G ON B.GroupSysID = G.GroupSysID
					   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(B.Currency, '') AND CLR.RateFor = 'BC SELLING'
					   WHERE B.IsDeleted = 0 AND IsCancelled = 0 AND BBLCNo IS NOT NULL
					 ) BBLCM 
						inner JOIN(
							SELECT BBLCID FROM ForeignDocumentAcceptanceMaster 
							WHERE IsDeleted = 0 AND IsCancelled = 0 AND BillNo IS NOT NULL
						) FDAM ON FDAM.BBLCID = BBLCM.BBLCID
					   WHERE FDAM.BBLCID IS NULL
					)A
					WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
					GROUP BY BranchID,CustomerID, Currency, ConvertFactor

			--END OF OutstandingBBLC

			UNION ALL

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,SUM(BillAmount)SavedAndGeneratedBTBBillAmount,
			           0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,0 FDBPAmount ,
					   0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					   0 DocumentsUnderCollectionUnpurchasedLoclAmount, Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			   FROM (
					SELECT (ISNULL(BillAmount,0) * ConvertFactor) BillAmount,ConvertFactor,CustomerID ,BranchID,Currency
					FROM (
						SELECT (ISNULL(BillAmount,0)) AS BillAmount,BBLCID,CustomerID,BranchID,Currency 
						FROM ForeignDocumentAcceptanceMaster 
					   WHERE IsDeleted = 0 AND IsCancelled = 0 AND BillNo IS NOT NULL 
					) FDAM 
					   INNER JOIN (SELECT BBLCID FROM BBLCMaster WHERE IsDeleted = 0 AND IsCancelled = 0 AND BBLCAmount > 0 AND BBLCNo IS NOT NULL
						) BBLCM ON BBLCM.BBLCID = FDAM.BBLCID
					   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(FDAM.Currency, '') AND CLR.RateFor = 'BC SELLING')A 
					WHERE BranchID = @BranchID AND CustomerID = @CustomerID 
					GROUP BY BranchID,CustomerID, Currency, ConvertFactor

			--END OF SavedAndGeneratedBTBBills

		 UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			           SUM(ISNULL(OutstandingBTBBills,0))OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					   0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount , 0 BBLCClosedAmount,0 OutstandingBBLCAmount  ,0 FDBPLocalAmount,
					   0 DocumentsUnderCollectionUnpurchasedLoclAmount, Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT ((ISNULL(BillAmount,0) * ConvertFactor) - ISNULL(FDPM.PaymentAmount,0)) AS OutstandingBTBBills,
					   BranchID,CustomerID, FDAM.Currency, ConvertFactor 
				FROM (
					SELECT ISNULL(BillAmount,0) AS BillAmount,BBLCID,FDAID,BranchID,CustomerID,Currency 
					FROM ForeignDocumentAcceptanceMaster 
					WHERE IsDeleted = 0 AND IsCancelled = 0 AND BillNo IS NOT NULL AND BillAmount > 0 AND IsImportLC = 0
				) FDAM 
					   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(FDAM.Currency, '') AND CLR.RateFor = 'BC SELLING'
					   INNER JOIN (SELECT BBLCID FROM BBLCMaster WHERE IsDeleted = 0 AND IsCancelled = 0 AND BBLCAmount > 0 AND BBLCNo IS NOT NULL
					  ) BBLCM ON BBLCM.BBLCID = FDAM.BBLCID 
					   LEFT JOIN  (
							SELECT M.FDAID,  SUM(M.PaymentAmount) PaymentAmount,Currency 
							FROM (
								SELECT  M.FDAID,  (M.PaymentAmount * ConvertFactor) PaymentAmount,Currency 
								FROM ForeignDocumentPaymentMaster M
									LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(M.Currency, '') AND CLR.RateFor = 'BC SELLING' 
									WHERE M.IsDeleted = 0 AND ISNULL(M.PaymentAmount, 0) > 0
						) M
					   GROUP BY M.FDAID,Currency)FDPM ON FDPM.FDAID = FDAM.FDAID
					  )A
					   WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
					   GROUP BY BranchID,CustomerID, Currency, ConvertFactor

           --END OF OutstandingBTBBills

			UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			         0 OutstandingBTBBillAmount,SUM(Amount) OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,0 FDBPAmount,
					 0 DocumentsUnderCollectionUnpurchasedAmount , 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					 0 DocumentsUnderCollectionUnpurchasedLoclAmount, Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT Amount * ConvertFactor Amount,BranchID,CustomerID, Currency, ConvertFactor 
				FROM (
					SELECT SGMID,Amount,BranchID,CustomerID,ImportOrBBLCID,Currency 
		            FROM ShippingGuaranteeMaster 
					WHERE IsDeleted = 0 AND IsCancelled = 0 AND SGRefNo IS NOT NULL
				)SGM
					 INNER JOIN (
						SELECT BBLCID FROM BBLCMaster WHERE IsDeleted = 0 AND IsCancelled = 0
					 ) BBLCM ON BBLCM.BBLCID = SGM.ImportOrBBLCID
					 LEFT JOIN (
						SELECT SGMID FROM ForeignDocumentShippingGuaranteeMap B WHERE IsDeleted = 0 AND IsCancelled = 0
					) FSGM ON FSGM.SGMID = SGM.SGMID
					 LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(SGM.Currency, '') AND CLR.RateFor = 'BC SELLING'
					 WHERE FSGM.SGMID IS NULL
				)A 
				WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
				GROUP BY BranchID,CustomerID, Currency, ConvertFactor
							

		 --END OF OutstandingSG

			UNION ALL 


			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,
				   SUM(ISNULL(EDFLoan.LoanAmount,0)) OutstandingEDFAmount,
				   0 OutstandingPCAmount,0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, EDFLoan.Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT (TOT_OS * ConvertFactor) LoanAmount,LoanNo,BBLCID,BankBranchID BranchID,Customer CustomerID,Currency, ConvertFactor 
				FROM LoanCreation L
				   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(L.Currency, '') AND CLR.RateFor = 'BC SELLING'
				   WHERE L.IsDeleted = 0 AND Product = 'LEDF' AND LoanNo IS NOT NULL
				)EDFLoan
				INNER JOIN (SELECT * FROM BBLCMaster WHERE IsDeleted = 0 AND IsCancelled = 0 and BBLCNo is not null) BBLCM ON BBLCM.BBLCID = EDFLoan.BBLCID
			WHERE BranchID = @BranchID AND CustomerID = @CustomerID 
		    GROUP BY BranchID,CustomerID, EDFLoan.Currency, ConvertFactor
					

		--END OF OutstandingEDF
		Union ALL
		 


			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,
				  0 OutstandingEDFAmount,
				   0 OutstandingPCAmount,0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, EDFLoan.Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC,
					 SUM(ISNULL(EDFLoan.LoanAmount,0)) OutstandingFLABAmount
			FROM (
				SELECT (TOT_OS * ConvertFactor) LoanAmount,LoanNo,BBLCID,BankBranchID BranchID,Customer CustomerID,Currency, ConvertFactor 
				FROM LoanCreation L
				   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(L.Currency, '') AND CLR.RateFor = 'BC SELLING'
				   WHERE L.IsDeleted = 0 AND Product = 'FLAB' AND LoanNo IS NOT NULL
				)EDFLoan
				INNER JOIN (SELECT * FROM BBLCMaster WHERE IsDeleted = 0 AND IsCancelled = 0 and BBLCNo is not null) BBLCM ON BBLCM.BBLCID = EDFLoan.BBLCID
			WHERE BranchID = @BranchID AND CustomerID = @CustomerID 
		    GROUP BY BranchID,CustomerID, EDFLoan.Currency, ConvertFactor
					

		--END OF OutstandingFLAB
			UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,
				   SUM(ISNULL(TOT_OS, 0)) OutstandingPCAmount,
				   0 FDBPAmount ,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, Currency, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT case when P.UBSSyncProcessID > 0 then P.TOT_OS else P.PCAmountTK end TOT_OS,BranchID,CustomerID, Currency, 1 ConvertFactor
				FROM PCDisbursementMaster P
		        WHERE P.IsDeleted = 0
			) PCDM
		    WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
			GROUP BY BranchID,CustomerID, Currency, ConvertFactor

		--END OF OutstandingPC

			UNION ALL 

			SELECT FDBP.BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
		           SUM(ISNULL(DisbursedAmount,0))FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount,0 OutstandingBBLCAmount  ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
		    FROM (
				SELECT PDFDM.EBIID,(DisbursedAmount * ConvertFactor) DisbursedAmount,BranchID,CustomerID, CURRENCY_CODE, ConvertFactor
		        FROM (
					SELECT EBIID,SUM(ISNULL(DisbursedAmount,0))DisbursedAmount,MAX(BranchID)BranchID,MAX(CustomerID)CustomerID 
					FROM (
						SELECT  EBIID, ISNULL(DisbursedAmount,0) DisbursedAmount, BranchID, CustomerID 
						FROM PurchaseDiscountForeignDocumentMaster P
						WHERE P.IsDeleted = 0 AND IsCancelled = 0 AND LoanNumber IS NOT NULL and P.EBIID IS NOT NULL AND ISNULL(P.IsExportLoan, 0) = 0
					) PDFD 
					GROUP BY EBIID
				) PDFDM
				INNER JOIN (SELECT EBIID,CURRENCY_CODE,ConvertFactor FROM ExportBillInitiationMaster E
				   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING' 
				   WHERE  E.IsDeleted = 0 AND IsCancelled = 0 AND ExportBillNo IS NOT NULL
				  ) E ON E.EBIID = PDFDM.EBIID
				)FDBP
				LEFT JOIN PRSCreationDistributionDetails d on isnull(d.BillRefNo, '') = isnull(FDBP.EBIID, '') AND d.PRSNCADID != 'NOT_NCA'
				WHERE  FDBP.BranchID = @BranchID AND FDBP.CustomerID = @CustomerID AND d.BillRefNo is null
				GROUP BY FDBP.BranchID,CustomerID, CURRENCY_CODE, ConvertFactor

		--END OF OutstandingExportBillPurchasedAndDiscount

			UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
		           0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount,0 OutstandingBBLCAmount,SUM(ISNULL(DisbursedAmount,0))FDBPLocalAmount ,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
		    FROM (
				SELECT PDFDM.EBIID,(DisbursedAmount * ConvertFactor) DisbursedAmount,BranchID,CustomerCode CustomerID, CURRENCY_CODE, ConvertFactor 
		        FROM (
					SELECT EBIID,SUM(ISNULL(DisbursedAmount,0))DisbursedAmount 
					FROM (
						SELECT  EBIID,ISNULL(DisbursedAmount,0) DisbursedAmount 
						FROM LDBCPurchase P
						WHERE P.IsDeleted = 0 AND IsCancelled = 0 AND LoanNumber IS NOT NULL AND ISNULL(DisbursedAmount,0) > 0
					) PDFD 
					WHERE ISNULL(DisbursedAmount,0) > 0 GROUP BY EBIID
				) PDFDM
				   INNER JOIN (SELECT EBIID,CURRENCY_CODE,ConvertFactor,BranchID,CustomerCode  FROM LocalExportBillInitiationMaster E
				   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING' 
				   WHERE  E.IsDeleted = 0 AND IsCancelled = 0 AND ExportLocalBillNo IS NOT NULL AND 
				   ExportLocalBillAmount > 0
				 ) E ON E.EBIID = PDFDM.EBIID
			)FDBP
			WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
			GROUP BY BranchID,CustomerID, CURRENCY_CODE, ConvertFactor

		--END OF OutstandingLocalExportBillPurchasedAndDiscount

			UNION ALL 

			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
		           0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount, CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT (ExportBillAmount * ConvertFactor)ExportBillAmount,BranchID,ExportBillAmount aa,CustomerCode CustomerID , CURRENCY_CODE, ConvertFactor
				FROM (
		           SELECT EBIID,ExportBillAmount,BranchID,CustomerCode ,CURRENCY_CODE 
				   FROM ExportBillInitiationMaster 
				   WHERE  IsDeleted = 0 AND IsCancelled = 0 AND ExportBillNo IS NOT NULL AND ExportBillAmount > 0
				) E 
				   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
				   LEFT JOIN (SELECT EBIID FROM PurchaseDiscountForeignDocumentMaster WHERE IsDeleted = 0 AND IsCancelled = 0 AND LoanNumber IS NOT NULL AND DisbursedAmount > 0
				   GROUP BY EBIID)PDFDM ON PDFDM.EBIID = E.EBIID WHERE PDFDM.EBIID IS NULL
				)A 
				WHERE  BranchID = @BranchID AND CustomerID = @CustomerID
				GROUP BY BranchID,CustomerID, CURRENCY_CODE, ConvertFactor

				--END OF OutstandingNotPurchasedExportBill

			UNION ALL
			
			SELECT BranchID,CustomerID,0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount,0 SavedAndGeneratedBTBBillAmount,
			       0 OutstandingBTBBillAmount,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
		           0 FDBPAmount,0 DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
				   0 DocumentsUnderCollectionUnpurchasedLoclAmount, CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT (ExportLocalBillAmount * ConvertFactor)ExportBillAmount,BranchID,CustomerCode CustomerID, CURRENCY_CODE, ConvertFactor 
				FROM (
		           SELECT EBIID,ExportLocalBillAmount,BranchID,CustomerCode ,CURRENCY_CODE 
				   FROM LocalExportBillInitiationMaster WHERE  IsDeleted = 0 AND IsCancelled = 0 AND ExportLocalBillNo IS NOT NULL AND ExportLocalBillAmount > 0
				 ) E 
				   LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
				   LEFT JOIN (SELECT EBIID FROM LDBCPurchase WHERE IsDeleted = 0 AND IsCancelled = 0 AND LoanNumber IS NOT NULL AND DisbursedAmount > 0
				   GROUP BY EBIID)PDFDM ON PDFDM.EBIID = E.EBIID  WHERE PDFDM.EBIID IS NULL
				)A 
				WHERE  BranchID = @BranchID AND CustomerID = @CustomerID 
				GROUP BY BranchID,CustomerID, CURRENCY_CODE, ConvertFactor

				--END OF OutstandingNotPurchasedExportBill


				union all

	--Start Doc Under Collection unpurchased
		 SELECT E.BranchID, E.CustomerCode CustomerID, 0 ExportBillAmount, 0 UnRealizedValue,0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount ,
					0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					0 FDBPAmount,SUM(ExportBillAmount) DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
		FROM (
			SELECT EBIID, (ExportBillAmount * ConvertFactor) ExportBillAmount, CustomerCode, BranchID, CURRENCY_CODE, ConvertFactor
			FROM ExportBillInitiationMaster E 
					INNER JOIN (
						SELECT MasterDocID FROM MasterDoc WHERE GroupSysID IS NOT NULL AND IsDeleted = 0 AND IsCancelled = 0
					) MD ON MD.MasterDocID = E.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
				WHERE E.IsDeleted = 0 AND ISNULL(E.IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL AND IsARVAdjusted = 0
		) E 
		left join PRSCreationDistributionDetails d on ISNULL(d.BillRefNo, '') = E.EBIID AND d.PRSNCADID != 'NOT_NCA'
		left join PurchaseDiscountForeignDocumentMaster pm on isnull(pm.EBIID, '') = E.EBIID and isnull(pm.IsExportLoan, 0) = 0 and pm.EBIID is not null
		WHERE E.BranchID = @BranchID AND E.CustomerCode = @CustomerID AND d.BillRefNo IS NULL and pm.EBIID is null
		GROUP BY E.BranchID, E.CustomerCode, CURRENCY_CODE, ConvertFactor
					
		UNION ALL

			SELECT E.BranchID, E.CustomerCode CustomerID, 0 ExportBillAmount, 0 UnRealizedValue, 0 TotalExportLCSCAmount,0 ClosedAmount,0 BBLCWithTolAmount ,
					0 SavedAndGeneratedBTBBillAmount, 0 OutstandingBTBBillAmount ,0 OutstandingSGAmount,0 OutstandingEDFAmount,0 OutstandingPCAmount,
					0 FDBPAmount ,SUM(ExportLocalBillAmount) DocumentsUnderCollectionUnpurchasedAmount, 0 BBLCClosedAmount ,0 OutstandingBBLCAmount ,0 FDBPLocalAmount,
					0 DocumentsUnderCollectionUnpurchasedLoclAmount,
					CURRENCY_CODE, ConvertFactor, 0 DocNotLodgeYet, 0 TimeLoan, 0 STLWC, 0 OutstandingFLABAmount
			FROM (
				SELECT EBIID,(ExportLocalBillAmount * ConvertFactor)ExportLocalBillAmount,CustomerCode,BranchID, CURRENCY_CODE, ConvertFactor 
				FROM LocalExportBillInitiationMaster E
					 INNER JOIN (SELECT MasterDocID FROM MasterDoc WHERE GroupSysID IS NOT NULL AND IsDeleted = 0 AND IsCancelled = 0
					 ) MD ON MD.MasterDocID = E.MasterDocID
					LEFT JOIN SystemManager..CurrencyLatestRate CLR ON CLR.CurrencyCode = ISNULL(E.CURRENCY_CODE, '') AND CLR.RateFor = 'BC SELLING'
					WHERE E.IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
			) E 
			left join PRSCreationDistributionDetails d on ISNULL(d.BillRefNo, '') = E.EBIID AND d.PRSNCADID != 'NOT_NCA' 
			left join PurchaseDiscountForeignDocumentMaster pm on isnull(pm.EBIID, '') = E.EBIID and isnull(pm.IsExportLoan, 0) = 0 and pm.EBIID is not null
		WHERE E.BranchID = @BranchID AND E.CustomerCode = @CustomerID AND d.BillRefNo IS NULL and pm.EBIID is null
		GROUP BY E.BranchID, E.CustomerCode, CURRENCY_CODE, ConvertFactor 

		--End of Doc Under Collection unpurchsed

		) ALLData
			LEFT JOIN (
				SELECT DISTINCT CPM.CustomerName+ ' - '+CPM.CIF CustomerName, CPM.CustomerID ,BPB.BranchID 
				FROM SystemManager..CustomerProfileMaster CPM 
				INNER JOIN SystemManager..CustomerBranchMap CBM ON CBM.CustomerID = CPM.CustomerID AND CBM.IsDeleted = 0
				INNER JOIN SystemManager..BankProfileBranch BPB On CBM.BranchID = BPB.BranchID WHERE CPM.IsDeleted = 0)Customer ON Customer.BranchID = ALLData.BranchID AND Customer.CustomerID = ALLData.CustomerID 
	)A
		 
	GROUP BY BranchID,CustomerID,CustomerName
END

