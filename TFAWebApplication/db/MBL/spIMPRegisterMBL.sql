USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spIMPRegisterMBL]    Script Date: 11/26/2026 1:27:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[spIMPRegisterMBL]
    @FromDate date, @ToDate date
AS
	-- spIMPRegisterMBL '2024-08-01','2025-10-01'
BEGIN
	SELECT
		BP.BranchName,
		BP.ADCode,
		FD.IMPNumber,
		LC.BBLCNo LCNo,
		FD.PaymentDate,
		FD.Currency,
		FD.BillAmount DocumentValue,
		'' FOBValue,
		LC.Freight Freight,
		CP.CustomerName Applicant,
		ISNULL(Bene.Name, LC.Benificiary) Beneficiary,
		'' PresentingBank,
		FD.AddedBy Inputter
	FROM ForeignDocumentAcceptanceMaster FD
		LEFT JOIN (
			SELECT BBLCID, BBLCAmount, BBLCNo, ExpiryDate, LATEST_SHIPMENT_DATE, GroupSysID, Benificiary, 'BTB' Type, Freight FROM BBLCMaster
			UNION ALL
			SELECT ImportLCID, ImportLCAmount, ImportLCNo, ExpiryDate, LATEST_SHIPMENT_DATE, '' GroupSysID, Benificiary, 'Cash' Type, Freight FROM ImportLCMaster
		) LC ON LC.BBLCID = FD.BBLCID
		LEFT Join SystemManager..Contacts Bene ON Bene.Code = LC.Benificiary
		LEFT JOIN SystemManager..CustomerProfileMaster CP ON CP.CustomerID = FD.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BP ON BP.BranchID = FD.BranchID
    WHERE FD.IsDeleted = 0 AND FD.IsCancelled = 0 AND FD.BillNo IS NOT NULL AND CONVERT(DATE, FD.DocReceiveDate) BETWEEN @FromDate AND @ToDate
END
GO


