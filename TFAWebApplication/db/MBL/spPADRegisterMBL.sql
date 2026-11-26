USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spPADRegisterMBL]    Script Date: 11/26/2026 1:28:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROC [dbo].[spPADRegisterMBL] @FromDate date, @ToDate date
AS
	-- spPADRegisterMBL '2024-08-01','2025-10-01'
BEGIN  
	SELECT DISTINCT
		FD.BillGenerationDate Date,	
		FD.BillNo,	
		LC.BBLCNo LCNo,	
		App.CustomerName Drawee,	
		Bene.Name Drawer,	
		'' ReceivedFrom,	
		FD.Currency,
		FD.BillAmount Amount,	
		C.CommodityName Commodity,	
		FD.TENOR_DAYS Tenor,	
		FD.AcceptanceDate AcceptanceDate,
		FD.MATURITY_DATE DueDate,	
		FD.PaymentDate PaymentDate,	
		FD.IMPNumber IMPSerial,
		FD.BranchID,
		FD.CustomerID
	FROM ForeignDocumentAcceptanceMaster FD
		LEFT JOIN (
			SELECT BBLCID, BBLCNo, Benificiary, Commodity FROM BBLCMaster
			UNION ALL
			SELECT ImportLCID, ImportLCNo, Benificiary, Commodity FROM ImportLCMaster
		) LC ON LC.BBLCID = FD.BBLCID
		LEFT JOIN SystemManager..CustomerProfileMaster App ON App.CustomerID = FD.CustomerID 
		LEFT JOIN SystemManager..Contacts Bene ON Bene.Code = LC.Benificiary
		LEFT JOIN SystemManager..CommodityMaster C ON C.CommodityMasterID = LC.Commodity
	WHERE FD.IsDeleted = 0 AND FD.IsCancelled = 0 AND FD.BillNo IS NOT NULL AND CONVERT(DATE, FD.BillGenerationDate) BETWEEN @FromDate AND @ToDate
END
GO


