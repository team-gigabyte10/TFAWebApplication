USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_ARVA2O2ReportPBL]    Script Date: 11/9/2026 6:00:16 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_ARVA2O2ReportPBL]
	@FromDate DATETIME, 
	@ToDate DATETIME, 
	@ADBranchID VARCHAR(50), 
	@CurrencyCode VARCHAR(10)
AS	
	-- SP_RPT_ARVA2O2ReportPBL '2024-01-01', '2024-06-30', 'BPB/22/6', 'USD'
BEGIN
	SET NOCOUNT ON;

	SELECT
		ISNULL(CPM.CustomerName, '') AS NameofExporter,
		DATENAME(month, @ToDate) AS [Period],
		CASE 
			WHEN COALESCE(ADbpb.BranchName, BPB_R.BranchName, '') <> '' 
				THEN 'Prime Bank PLC, ' + COALESCE(ADbpb.BranchName, BPB_R.BranchName)
			ELSE 'Prime Bank PLC'
		END AS NameofAuthorizedDealer,
		R.CurrencyCode AS CCY,
		ISNULL(R.Quantity, 0) AS Quantity,
		U.UnitShortCode AS Unit,
		U.UnitDesc AS UnitCode,
		ISNULL(R.Quantity, 0) AS Volume,
		ISNULL(R.TotalRMTAmount, 0) AS Amount,
		NULL AS CodeNumber,
		ISNULL(ExpCC.SequenceNo, C.SequenceNo) AS CountryofDestination,
		ISNULL(ExpCC.HSCODE, CO.HSCode) AS Commodity,
		CONVERT(DATE, EOMONTH(@ToDate)) AS finaldate,
		COALESCE(ADbpb.ADBranchID, BPB_R.ADBranchID, MD.ADBranchID, R.BranchID, '') AS ADBranchID,
		R.CurrencyCode AS CurrencyCode,
		CASE 
			WHEN MONTH(@ToDate) = 1 THEN 'Y'
			WHEN MONTH(@ToDate) = 2 THEN 'X'
			WHEN MONTH(@ToDate) = 3 THEN '0'
			WHEN MONTH(@ToDate) = 4 THEN '1'
			WHEN MONTH(@ToDate) = 5 THEN '2'
			WHEN MONTH(@ToDate) = 6 THEN '3'
			WHEN MONTH(@ToDate) = 7 THEN '4'
			WHEN MONTH(@ToDate) = 8 THEN '5'
			WHEN MONTH(@ToDate) = 9 THEN '6'
			WHEN MONTH(@ToDate) = 10 THEN '7'
			WHEN MONTH(@ToDate) = 11 THEN '8'
			WHEN MONTH(@ToDate) = 12 THEN '9'
		END AS PeriodCode,
		COALESCE(ADbpb.ADCode, BPB_R.ADCode, '') AS ADCode,
		CLR.CurrencyCodeNumeric AS CurrencyNumericCode
	FROM RMTCreationMaster R
		LEFT JOIN MasterDoc MD ON MD.MasterDocID = R.MasterDocOrEBIID
		LEFT JOIN SystemManager..Currency CLR ON CLR.CurrencyCode = R.CurrencyCode
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = R.CustomerID
		LEFT JOIN SystemManager..Unit U ON R.UOM = U.UnitCode
		LEFT JOIN SystemManager..Contacts Applicant ON Applicant.Code = MD.Applicant	
		LEFT JOIN SystemManager..CommodityMaster CO WITH(NOLOCK) ON CO.CommodityMasterID = MD.Commodity
		LEFT JOIN SystemManager..Country C ON C.CountryID = Applicant.CountryID
		LEFT JOIN SystemManager..BankProfileBranch ADbpb ON ADbpb.BranchID = MD.ADBranchID
		LEFT JOIN SystemManager..BankProfileBranch BPB_R ON BPB_R.BranchID = R.BranchID
		LEFT JOIN (
			SELECT A.RMTCMID, MAX(CN.SequenceNo) AS SequenceNo, MAX(C.HSCODE) AS HSCODE
			FROM ARVexpInvoiceDetails A
				INNER JOIN EXPRegisterChild C ON C.EXPRMCID = A.ExpID
				LEFT JOIN SystemManager..Country CN ON CN.CountryID = C.CountryID
			WHERE A.IsDeleted = 0
			GROUP BY A.RMTCMID
		) ExpCC ON ExpCC.RMTCMID = R.RMTCMID
	WHERE CONVERT(DATE, COALESCE(R.BBARVGenerationDate, R.RMTDate, R.DateAdded)) BETWEEN @FromDate AND @ToDate
		AND R.IsCancelled = 0 
		AND R.IsDeleted = 0 
		AND (
			@ADBranchID IS NULL 
			OR @ADBranchID = '' 
			OR @ADBranchID = 'All' 
			OR R.BranchID = @ADBranchID
			OR MD.ADBranchID = @ADBranchID
			OR ADbpb.BranchID = @ADBranchID
			OR ADbpb.ADBranchID = @ADBranchID
			OR ADbpb.ADCode = @ADBranchID
			OR ADbpb.BranchCode = @ADBranchID
			OR BPB_R.BranchID = @ADBranchID
			OR BPB_R.ADBranchID = @ADBranchID
			OR BPB_R.ADCode = @ADBranchID
			OR BPB_R.BranchCode = @ADBranchID
		)
		AND (
			@CurrencyCode IS NULL 
			OR @CurrencyCode = '' 
			OR @CurrencyCode = 'All' 
			OR R.CurrencyCode = @CurrencyCode
		)
END
GO