USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spFDBCorFDBPorExportRegisterMBL]    Script Date: 11/26/2026 1:32:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[spFDBCorFDBPorExportRegisterMBL]
    @FromDate date, @ToDate date
AS
	-- spFDBCorFDBPorExportRegisterMBL '2024-08-01','2025-10-01'
BEGIN
	SELECT
		EB.BillGenerationDate BillDate,
		EB.ExportBillNo ExportBillNo,
		EB.ExternalID ExportBillTFID,
		BP.BranchName BranchName,
		'' DrawType,
		'' BeneficiaryID,
		CP.CustomerName Drawer,
		App.Name Drawee,
		'' ParticularsGoodsSector,
		EB.CURRENCY_CODE DrawCurrency,
		EB.ExportBillAmount BillAmount,
		EB.ExchangeRate ExRate,
		'' AmountTk,
		'' PurchaseCollection,
		'' FCNegoAmount,
		'' LoanACNo,
		'' NegoDate,
		'' LoanExpiryDate,
		'' LACAmount,
		'' PCAdjust,
		'' PCNumber,
		'' FCBuildUp,
		'' OtherLoanSettlementExceptPC,
		'' ERM,
		'' AmtPaidtoPartyAC,
		'' TaxDeducted,
		'' CFRMGAmount,
		'' CollectionCommission,
		'' CourierCharge,
		'' InspectionFee,
		'' EXPCharges,
		'' OtherCharges,
		'' EXPNo,
		'' DraweeBank,
		'' NOSTROBank,
		EB.TENOR_DAYS Tenor,
		'' BillAcceptanceDate,
		'' BillMaturityDate,
		'' AmountRealized,
		'' DateofRealization,
		'' FCHELD,
		'' FCHeldACNo,
		'' AmountCreditedtoERQAC,
		'' ExcessERQ,
		'' DateofReportingtoBB,
		'' DateofPRCIssued,
		'' FDBPAdjustedDate,
		'' AginginDays,
		MD.LCNo ExportLCNo,
		CASE WHEN MD.IsSC = 0 THEN 'LC' ELSE 'SC' END LCSC,
		G.GroupRefNo JobNumber
	FROM ExportBillInitiationMaster EB
		INNER JOIN MasterDoc MD ON MD.MasterDocID = EB.MasterDocID
		LEFT JOIN GroupLC G ON G.GroupSysID = MD.GroupSysID
		LEFT JOIN SystemManager..CustomerProfileMaster CP ON CP.CustomerID = G.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BP ON BP.BranchID = G.BankBranchID
		LEFT JOIN SystemManager..Contacts App ON App.Code = MD.Applicant
    WHERE EB.IsDeleted = 0 AND EB.IsCancelled = 0 AND EB.ExportBillNo IS NOT NULL AND CONVERT(DATE, EB.BillGenerationDate) BETWEEN @FromDate AND @ToDate
END
GO


