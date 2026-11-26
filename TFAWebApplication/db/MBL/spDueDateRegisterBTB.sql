USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spDueDateRegisterBTB]    Script Date: 11/26/2026 1:30:53 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROC [dbo].[spDueDateRegisterBTB] @FromDate date, @ToDate date
AS
	-- spDueDateRegisterBTB '2024-08-01','2025-10-01'
BEGIN  
    WITH LC_Aggregated AS (
        SELECT 
            GroupSysID,
            STRING_AGG(ISNULL(lcno, ''), ', ') AS all_lcs
        FROM masterdoc
        GROUP BY GroupSysID
    )
	SELECT DISTINCT
		B.BranchName,
		LC.BBLCNo LCNo,
		FD.ReferenceNo TFNoBILL,
		App.CustomerName Applicant,
		Bene.Name Beneficiary,
		G.GroupRefNo JobNo,
		ISNULL(LCA.all_lcs, '') ExportLCSalesContractNo,
		'' CurrentFCHeldBalance,
		FD.Currency Currency,
		FD.BillAmount DocumentValue,
		FD.MATURITY_DATE MaturityDate,
		FD.AcceptanceIDNo AcceptanceNo,
		'' BBAcceptanceID,
		'' BillStatus,
		'' DocumentIdentifierNo
	FROM ForeignDocumentAcceptanceMaster FD
		INNER JOIN BBLCMaster LC ON LC.BBLCID = FD.BBLCID
		LEFT JOIN GroupLC G ON G.GroupSysID = LC.GroupSysID
		LEFT JOIN LC_Aggregated LCA ON LCA.GroupSysID = G.GroupSysID
		LEFT JOIN SystemManager..CustomerProfileMaster App ON App.CustomerID = FD.CustomerID 
		LEFT JOIN SystemManager..Contacts Bene ON Bene.Code = LC.Benificiary
		LEFT JOIN SystemManager..CommodityMaster C ON C.CommodityMasterID = LC.Commodity
		LEFT JOIN SystemManager..BankProfileBranch B ON B.BranchID = FD.BranchID
		
	WHERE FD.IsDeleted = 0 AND FD.IsCancelled = 0 AND FD.BillNo IS NOT NULL AND CONVERT(DATE, FD.DocReceiveDate) BETWEEN @FromDate AND @ToDate
END
GO


