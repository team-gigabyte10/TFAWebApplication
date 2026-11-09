USE EFA
GO

Create Or Alter Proc spRPT_MarginRegisterPBL
	@FromDate Date,
	@ToDate Date
As

 -- spRPT_MarginRegisterPBL '2024-01-01', '2026-10-27'

 -- Margin Register (columns of Doc\Margin Register.xlsx)
 -- Data comes from the same query as ViewTransactionLedgerOBL (copied into this procedure, so the view is not needed),
 -- only for margin accounts (same rule as SP_RPT_MarginRegisterOBL), and also all Margin Encashment rows
 -- (their account is the margin account of the record, even when it is not in CustomerProfileAccounts).
 -- A record must be authorized (IsCheck = 1) to show.
 -- Margin balance = total Margin Credit - total Margin Debit, for each margin account and margin currency.
 --   OpeningBalance = balance before this row
 --   PresentBalance = OpeningBalance + MarginCredit - MarginDebit
 -- Older rows (before @FromDate) are read too, because they are part of the balance.
 -- Rows with an empty transaction date are not included.
 -- Customer name and Branch name are plain names, like spRPT_LCAdvisingReport (CustomerProfileMaster.CustomerName, BankProfileBranch.BranchName).
 -- BranchID and CustomerID are not shown. The Report Viewer menu uses them for its Bank Branch and Customer Name filters
 -- (SystemManager ReportSuiteField, ReportId 1100339).
 -- A Margin Encashment row shows the branch of the record, or else the branch of the group.

Begin
	Set NoCount On;

	-- Step 1: all margin transactions up to To Date
	select
		ROW_NUMBER() Over (Order By L.TransanctionDate, L.TransRefNo, L.RefSystemID)	Seq,
		L.TransanctionDate,
		L.BillType,
		L.TransRefNo,
		L.GroupRefNo,
		L.BranchName,
		L.BranchID,
		L.CustomerName,
		L.CustomerCode,
		L.BillCCY,
		L.BillAmount,
		L.AC_NO,
		L.Currency,
		L.CreditAmount,
		L.DebitAmount,
		L.Remarks
	into #Ledger
	from
	(
		-- Body of view ViewTransactionLedgerOBL, copied here because the view does not exist on this database
			SELECT 
				Bill.ExportBillNo TransRefNo, 
				D.TransactionSendingTimeToCBS TransanctionDate, 
				D.DistributedCCY Currency, 
				CASE WHEN D.DistributedCCY = 'BDT' THEN D.FCCPer ELSE D.DistributedValue END CreditAmount, 
				0 DebitAmount, 
				'C' DRCR, 
				D.AC_NO, 
				D.CustomerCode, 
				CPM.CustomerName CustomerName,
				Bill.BillType BillType, 
				GLC.GroupSysID, 
				GLC.GroupRefNo,
				Bill.ExportBillAmount BillAmount,
				Bill.CURRENCY_CODE BillCCY,
				D.ProductCode,
				NULL Remarks,
				MD.MasterDocID LCSystemID,
				MD.LCNo LCNumber,
				D.PRSDDID RefSystemID,
				GLC.BankBranchID BranchID,
				BPB.BranchName BranchName,
				0 IsMarginRow
			FROM PRSCreationDistributionDetails D WITH(NOLOCK)
				INNER JOIN PRSCreationMaster M WITH(NOLOCK) ON M.PRSSysID = D.PRSSysID AND M.IsDeleted = 0 AND M.IsCheck = 1
				INNER JOIN (
					SELECT EBIID, ExportBillNo, MasterDocID, 'Export Proceeds Realization' BillType, ExportBillAmount, CURRENCY_CODE
					FROM ExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL
					UNION ALL
					SELECT EBIID, ExportLocalBillNo, MasterDocID, 'Export Proceeds Realization' BillType, ExportLocalBillAmount, CURRENCY_CODE
					FROM LocalExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
					UNION ALL
					SELECT RMTCMID, RMTNo, MasterDocOrEBIID, 'ARV Realization' BillType, TotalRMTAmount, CurrencyCode
					FROM RMTCreationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND RMTNo IS NOT NULL
				) Bill ON Bill.EBIID = ISNULL(D.BillRefNo, '')
				INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = Bill.MasterDocID
				INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = ISNULL(MD.GroupSysID, '')
				LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = ISNULL(D.CustomerCode, '') AND CPM.IsDeleted = 0
				LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = GLC.BankBranchID AND BPB.IsDeleted = 0
			WHERE D.IsDeleted = 0 AND D.DRCR_IND = 'C' AND D.IsSendTransactionToCBS = 1 AND D.IsReversedFromCBS = 0
		
			UNION ALL
		
			SELECT 
				Bill.ExportBillNo TransRefNo, 
				D.TransactionSendingTimeToCBS TransanctionDate, 
				D.DistributedCCY Currency, 
				0 CreditAmount, 
				CASE WHEN D.DistributedCCY = 'BDT' THEN D.LCY_AMOUNT ELSE D.D_Amount END DebitAmount, 
				'D' DRCR, 
				D.AC_NO, 
				D.CustomerCode, 
				CPM.CustomerName CustomerName,
				Bill.BillType BillType, 
				GLC.GroupSysID, 
				GLC.GroupRefNo,
				Bill.ExportBillAmount BillAmount,
				Bill.CURRENCY_CODE BillCCY,
				D.ProductCode,
				NULL Remarks,
				MD.MasterDocID LCSystemID,
				MD.LCNo LCNumber,
				D.PRSDDID RefSystemID,
				GLC.BankBranchID BranchID,
				BPB.BranchName BranchName,
				0 IsMarginRow
			FROM PRSCreationDistributionDetails D WITH(NOLOCK)
				INNER JOIN PRSCreationMaster M WITH(NOLOCK) ON M.PRSSysID = D.PRSSysID AND M.IsDeleted = 0 AND M.IsCheck = 1
				INNER JOIN (
					SELECT EBIID, ExportBillNo, MasterDocID, 'Export Proceeds Realization' BillType, ExportBillAmount, CURRENCY_CODE
					FROM ExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL
					UNION ALL
					SELECT EBIID, ExportLocalBillNo, MasterDocID, 'Export Proceeds Realization' BillType, ExportLocalBillAmount, CURRENCY_CODE
					FROM LocalExportBillInitiationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
					UNION ALL
					SELECT RMTCMID, RMTNo, MasterDocOrEBIID, 'ARV Realization' BillType, TotalRMTAmount, CurrencyCode
					FROM RMTCreationMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND RMTNo IS NOT NULL
				) Bill ON Bill.EBIID = ISNULL(D.BillRefNo, '')
				INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = Bill.MasterDocID
				INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = ISNULL(MD.GroupSysID, '')
				LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = ISNULL(D.CustomerCode, '') AND CPM.IsDeleted = 0
				LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = GLC.BankBranchID AND BPB.IsDeleted = 0
			WHERE D.IsDeleted = 0 AND D.DRCR_IND = 'D' AND D.IsSendTransactionToCBS = 1 AND D.IsReversedFromCBS = 0
		--PRS END
		
			UNION ALL
		
		--MARGIN ENCASHMENT START
			SELECT 
				CASE 
					WHEN E.DisplayCode = 'Import Payment' THEN BillOrLoan.LoanNo + ', ' + ISNULL(BillOrLoan.ExternalID, '')
					ELSE MD.MAEMID
				END TransRefNo, 
				CASE 
					WHEN E.DisplayCode = 'Adjustment' OR E.DisplayCode = 'Transfer Group' THEN MD.CheckDate
					ELSE (SELECT MAX(TransactionSendingTimeToCBS) FROM MarginTransactionDetails WITH(NOLOCK) WHERE IsDeleted = 0 AND MAEMID = MD.MAEMID AND IsSendTransactionToCBS = 1 AND IsReversedFromCBS = 0)
				END TransanctionDate, 
				GLC.CurrencyCode Currency, 
				CASE WHEN D.DebitCredit = 'Credit' THEN D.NetMarginPosition ELSE 0 END CreditAmount, 
				CASE WHEN D.DebitCredit = 'Credit' THEN 0 ELSE D.NetMarginPosition END DebitAmount, 
				CASE WHEN D.DebitCredit = 'Credit' THEN 'C' ELSE 'D' END DRCR, 
				MD.MarginAC ACCNo, 
				MD.CustomerID CustomerCode,
				CPM.CustomerName CustomerName,
				CASE 
					WHEN E.DisplayCode = 'Import Payment' THEN 
						CASE 
							WHEN MD.IsBill = 1 THEN 'Import Payment (Bill)'
							ELSE 'Import Payment (Loan)'
						END
					ELSE E.DisplayCode
				END BillType, 
				GLC.GroupSysID, 
				GLC.GroupRefNo,
				CASE 
					WHEN E.DisplayCode = 'Import Payment' THEN BillOrLoan.LoanAmount
					ELSE NULL
				END BillAmount,
				CASE 
					WHEN E.DisplayCode = 'Import Payment' THEN BillOrLoan.LoanCurrency
					ELSE NULL
				END BillCCY,
				NULL ProductCode,
				MD.Remarks,
				LC.BBLCID LCSystemID,
				LC.BBLCNo LCNumber,
				D.MAECID RefSystemID,
				ISNULL(NULLIF(MD.AdditionalFilter, ''), GLC.BankBranchID) BranchID,	-- branch of the record, or else branch of the group
				-- branch of the record; if there is no such branch, branch of the group
				ISNULL(BPB.BranchName, BPG.BranchName) BranchName,
				1 IsMarginRow
			FROM MarginEncashmentChild D WITH(NOLOCK)
				INNER JOIN MarginEncashmentMaster MD WITH(NOLOCK) ON MD.MAEMID = D.MAEMID AND MD.IsDeleted = 0 AND MD.IsCheck = 1
				LEFT JOIN SystemManager..EntityFixedVariables E WITH(NOLOCK) ON E.EntityID = ISNULL(MD.ExportBillType, '')
				LEFT JOIN GroupLC GLC WITH(NOLOCK) ON ISNULL(GLC.GroupSysID, '') = ISNULL(D.GroupSysID, '')
				LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = ISNULL(MD.CustomerID, '') AND CPM.IsDeleted = 0
				LEFT JOIN (
					SELECT LoanCreationID, LoanNo, ExternalID, LoanAmount, LoanCurrency, BBLCID 
					FROM LoanCreation WITH(NOLOCK)
					WHERE IsDeleted = 0 AND LoanNo IS NOT NULL
					UNION ALL
					SELECT FDAID, BillNo, ReferenceNo, BillAmount, Currency, BBLCID 
					FROM ForeignDocumentAcceptanceMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND IsCancelled = 0 AND BillNo IS NOT NULL
				) BillOrLoan ON BillOrLoan.LoanCreationID = ISNULL(MD.BillOrLoanID, '')
				LEFT JOIN (
					SELECT BBLCID, BBLCNo 
					FROM BBLCMaster WITH(NOLOCK)
					WHERE IsDeleted = 0 AND IsCancelled = 0
					UNION ALL
					SELECT ImportLCID, ImportLCNo 
					FROM ImportLCMaster WITH(NOLOCK)
					WHERE IsDeleted = 0
				) LC ON LC.BBLCID = ISNULL(BillOrLoan.BBLCID, '')
				LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(MD.AdditionalFilter, '') AND BPB.IsDeleted = 0
				LEFT JOIN SystemManager..BankProfileBranch BPG WITH(NOLOCK) ON BPG.BranchID = ISNULL(GLC.BankBranchID, '') AND BPG.IsDeleted = 0
			WHERE MD.IsDeleted = 0 AND MD.IsCheck = 1
		--MARGIN ENCASHMENT END
		
			UNION ALL
		
		--IMPORT BILL PAYMENT START
			SELECT 
				M.BillNo + ', ' + ISNULL(M.ReferenceNo, '') TransRefNo, 
				D.DateAdded TransanctionDate, 
				D.CreditCurrency Currency, 
				D.CreditAmount, 
				0 DebitAmount, 
				'C' DRCR, 
				D.CreditAccountNo AC_NO, 
				M.CustomerID CustomerCode, 
				CPM.CustomerName CustomerName,
				'BTB Bill''s Payment' BillType, 
				GLC.GroupSysID, 
				GLC.GroupRefNo,
				M.BillAmount,
				M.Currency BillCCY,
				D.TransType ProductCode,
				NULL Remarks,
				BB.BBLCID LCSystemID,
				BB.BBLCNo LCNumber,
				D.CVTD RefSystemID,
				GLC.BankBranchID BranchID,
				BPB.BranchName BranchName,
				0 IsMarginRow
			FROM CustomerVoucherTransDetails D WITH(NOLOCK)
				INNER JOIN ForeignDocumentAcceptanceMaster M WITH(NOLOCK) ON ISNULL(M.ExternalID, '') = ISNULL(D.AdditionalMasterID, '') AND M.IsDeleted = 0 AND M.IsCancelled = 0
				INNER JOIN BBLCMaster BB WITH(NOLOCK) ON BB.BBLCID = M.BBLCID
				INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = BB.GroupSysID
				LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = M.CustomerID AND CPM.IsDeleted = 0
				LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = GLC.BankBranchID AND BPB.IsDeleted = 0
			WHERE D.IsDeleted = 0 AND D.CreditAmount > 0 AND D.AdditionalFilter = 'Foreign Document Acceptance Master'
		
			UNION ALL
		
			SELECT 
				M.BillNo + ', ' + ISNULL(M.ReferenceNo, '') TransRefNo, 
				D.DateAdded TransanctionDate, 
				D.DebitCurrency Currency, 
				0 CreditAmount, 
				D.DebitAmount, 
				'D' DRCR, 
				D.DebitAccountNo AC_NO, 
				M.CustomerID CustomerCode, 
				CPM.CustomerName CustomerName,
				'BTB Bill''s Payment' BillType, 
				GLC.GroupSysID, 
				GLC.GroupRefNo,
				M.BillAmount,
				M.Currency BillCCY,
				D.TransType ProductCode,
				NULL Remarks,
				BB.BBLCID LCSystemID,
				BB.BBLCNo LCNumber,
				D.CVTD RefSystemID,
				GLC.BankBranchID BranchID,
				BPB.BranchName BranchName,
				0 IsMarginRow
			FROM CustomerVoucherTransDetails D WITH(NOLOCK)
				INNER JOIN ForeignDocumentAcceptanceMaster M WITH(NOLOCK) ON ISNULL(M.ExternalID, '') = ISNULL(D.AdditionalMasterID, '') AND M.IsDeleted = 0 AND M.IsCancelled = 0
				INNER JOIN BBLCMaster BB WITH(NOLOCK) ON BB.BBLCID = M.BBLCID
				INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = BB.GroupSysID
				LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = M.CustomerID AND CPM.IsDeleted = 0
				LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = GLC.BankBranchID AND BPB.IsDeleted = 0
			WHERE D.IsDeleted = 0 AND D.DebitAmount > 0 AND D.AdditionalFilter = 'Foreign Document Acceptance Master'
	) L
	where L.TransanctionDate Is Not Null
	  and CAST(L.TransanctionDate As Date) <= @ToDate
	  and (
			L.IsMarginRow = 1	-- margin encashment rows use the margin account of the record, so they are always margin rows
			or L.AC_NO in
			(
				select CA.AccountCode
				from SystemManager..CustomerProfileAccounts CA WITH(NOLOCK)
					Inner Join SystemManager..EntityFixedVariables EN WITH(NOLOCK) ON EN.EntityID = CA.AccountTypeID
					Left Join SystemManager..BankProfileGLAccounts GL WITH(NOLOCK) ON GL.AccountNo = CA.AccountCode
				where CA.IsDeleted = 0 and EN.ExternalID = 'MARGIN' and GL.AccountNo Is Null
			)
		)

	-- Step 2: running balance for each margin account and currency, then keep only the rows between From Date and To Date
	;With Running As
	(
		select
			T.*,
			SUM(ISNULL(T.CreditAmount, 0) - ISNULL(T.DebitAmount, 0))
				Over (Partition By T.AC_NO, T.Currency Order By T.Seq Rows Between Unbounded Preceding And Current Row)	PresentBalance
		from #Ledger T
	)
	select
		R.TransanctionDate															TransactionDate,
		R.BillType																	RelatedProduct,
		R.TransRefNo																RelatedReferenceNo,
		R.GroupRefNo																GroupRefNo,
		R.BranchName																BranchName,
		R.CustomerName																CustomerName,
		R.BillCCY																	Currency,
		R.BillAmount																BillValue,
		R.AC_NO																		MarginAccount,
		R.Currency																	MarginCurrency,
		ISNULL(R.CreditAmount, 0)													MarginCredit,
		ISNULL(R.DebitAmount, 0)													MarginDebit,
		R.Remarks																	Reason,
		R.PresentBalance - (ISNULL(R.CreditAmount, 0) - ISNULL(R.DebitAmount, 0))	OpeningBalance,
		R.PresentBalance															PresentBalance,
		R.BranchID																	BranchID,
		R.CustomerCode																CustomerID
	from Running R
	where CAST(R.TransanctionDate As Date) >= @FromDate
	order by R.TransanctionDate, R.TransRefNo, R.Seq

	Drop Table #Ledger
End
GO
