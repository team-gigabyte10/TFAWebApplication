USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_ARVA2O2ReportPBL]    Script Date: 11/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_ARVA2O2ReportPBL]
	@FromDate DATETIME, 
	@ToDate DATETIME, 
	@ADBranchID VARCHAR(50) = NULL, 
	@CurrencyCode VARCHAR(10) = NULL
AS	
	-- SP_RPT_ARVA2O2ReportPBL '2024-01-01', '2024-06-30', 'BPB/22/6', 'USD'
BEGIN
	SET NOCOUNT ON;

	DECLARE @CleanBranchID VARCHAR(100) = LTRIM(RTRIM(ISNULL(@ADBranchID, '')));
	DECLARE @CleanCurrency VARCHAR(50) = LTRIM(RTRIM(ISNULL(@CurrencyCode, '')));
	DECLARE @BranchSuffix VARCHAR(50) = CASE 
		WHEN CHARINDEX('/', @CleanBranchID) > 0 THEN RIGHT(@CleanBranchID, CHARINDEX('/', REVERSE(@CleanBranchID)) - 1)
		ELSE @CleanBranchID
	END;

	SELECT
		CAST(ISNULL(CPM.CustomerName, '') AS VARCHAR(250)) AS NameofExporter,
		CAST(DATENAME(month, @ToDate) AS VARCHAR(50)) AS [Period],
		CAST(
			'Prime Bank PLC' + CASE 
				WHEN NULLIF(LTRIM(RTRIM(COALESCE(ADbpb.BranchName, BPB_R.BranchName, ''))), '') IS NOT NULL 
					THEN ', ' + LTRIM(RTRIM(COALESCE(ADbpb.BranchName, BPB_R.BranchName)))
				ELSE ''
			END AS VARCHAR(300)
		) AS NameofAuthorizedDealer,
		CAST(R.CurrencyCode AS VARCHAR(10)) AS CCY,
		CAST(ISNULL(R.Quantity, 0) AS DECIMAL(18, 2)) AS Quantity,
		CAST(ISNULL(U.UnitShortCode, '') AS VARCHAR(50)) AS Unit,
		CAST(ISNULL(U.UnitDesc, '') AS VARCHAR(50)) AS UnitCode,
		CAST(ISNULL(R.Quantity, 0) AS DECIMAL(18, 2)) AS Volume,
		CAST(ISNULL(R.TotalRMTAmount, 0) AS DECIMAL(18, 2)) AS Amount,
		CAST(NULL AS INT) AS CodeNumber,
		CAST(ISNULL(ExpCC.SequenceNo, C.SequenceNo) AS DECIMAL(18, 2)) AS CountryofDestination,
		CAST(ISNULL(ExpCC.HSCODE, CO.HSCode) AS VARCHAR(100)) AS Commodity,
		CAST(EOMONTH(@ToDate) AS DATETIME) AS finaldate,
		CAST(COALESCE(ADbpb.ADBranchID, BPB_R.ADBranchID, MD.ADBranchID, R.BranchID, '') AS VARCHAR(50)) AS ADBranchID,
		CAST(R.CurrencyCode AS VARCHAR(10)) AS CurrencyCode,
		CAST(
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
			END AS VARCHAR(10)
		) AS PeriodCode,
		CAST(COALESCE(NULLIF(ADbpb.ADCode, ''), NULLIF(BPB_R.ADCode, ''), '') AS VARCHAR(50)) AS ADCode,
		CAST(ISNULL(CLR.CurrencyCodeNumeric, '') AS VARCHAR(20)) AS CurrencyNumericCode
	FROM RMTCreationMaster R
		LEFT JOIN MasterDoc MD ON MD.MasterDocID = R.MasterDocOrEBIID
		LEFT JOIN SystemManager..Currency CLR ON CLR.CurrencyCode = R.CurrencyCode
		LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = R.CustomerID
		LEFT JOIN SystemManager..Unit U ON R.UOM = U.UnitCode
		LEFT JOIN SystemManager..Contacts Applicant ON Applicant.Code = MD.Applicant	
		LEFT JOIN SystemManager..CommodityMaster CO WITH(NOLOCK) ON CO.CommodityMasterID = MD.Commodity
		LEFT JOIN SystemManager..Country C ON C.CountryID = Applicant.CountryID
		LEFT JOIN SystemManager..BankProfileBranch ADbpb ON 
			ADbpb.BranchID = MD.ADBranchID 
			OR ADbpb.BranchID = REPLACE(MD.ADBranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', MD.ADBranchID) > 0 
				AND CHARINDEX('/', ADbpb.BranchID) > 0
				AND RIGHT(MD.ADBranchID, CHARINDEX('/', REVERSE(MD.ADBranchID) + '/') - 1) = RIGHT(ADbpb.BranchID, CHARINDEX('/', REVERSE(ADbpb.BranchID) + '/') - 1)
			)
		LEFT JOIN SystemManager..BankProfileBranch BPB_R ON 
			BPB_R.BranchID = R.BranchID 
			OR BPB_R.BranchID = REPLACE(R.BranchID, 'BPB/22/', 'OBPB/25/')
			OR (
				CHARINDEX('/', R.BranchID) > 0 
				AND CHARINDEX('/', BPB_R.BranchID) > 0
				AND RIGHT(R.BranchID, CHARINDEX('/', REVERSE(R.BranchID) + '/') - 1) = RIGHT(BPB_R.BranchID, CHARINDEX('/', REVERSE(BPB_R.BranchID) + '/') - 1)
			)
		LEFT JOIN (
			SELECT A.RMTCMID, MAX(CN.SequenceNo) AS SequenceNo, MAX(C.HSCODE) AS HSCODE
			FROM ARVexpInvoiceDetails A
				INNER JOIN EXPRegisterChild C ON C.EXPRMCID = A.ExpID
				LEFT JOIN SystemManager..Country CN ON CN.CountryID = C.CountryID
			WHERE A.IsDeleted = 0
			GROUP BY A.RMTCMID
		) ExpCC ON ExpCC.RMTCMID = R.RMTCMID
	WHERE R.IsCancelled = 0 
		AND R.IsDeleted = 0 
		AND (
			(R.RMTDate IS NOT NULL AND CONVERT(DATE, R.RMTDate) >= CONVERT(DATE, @FromDate) AND CONVERT(DATE, R.RMTDate) <= CONVERT(DATE, @ToDate))
			OR (R.BBARVGenerationDate IS NOT NULL AND CONVERT(DATE, R.BBARVGenerationDate) >= CONVERT(DATE, @FromDate) AND CONVERT(DATE, R.BBARVGenerationDate) <= CONVERT(DATE, @ToDate))
			OR (R.RMTDate IS NULL AND R.BBARVGenerationDate IS NULL AND CONVERT(DATE, R.DateAdded) >= CONVERT(DATE, @FromDate) AND CONVERT(DATE, R.DateAdded) <= CONVERT(DATE, @ToDate))
		)
		AND (
			@CleanBranchID = '' 
			OR @CleanBranchID = 'All' 
			OR R.BranchID = @CleanBranchID
			OR MD.ADBranchID = @CleanBranchID
			OR ADbpb.BranchID = @CleanBranchID
			OR ADbpb.ADBranchID = @CleanBranchID
			OR ADbpb.ADCode = @CleanBranchID
			OR ADbpb.BranchCode = @CleanBranchID
			OR ADbpb.BranchName = @CleanBranchID
			OR ADbpb.BranchName LIKE '%' + @CleanBranchID + '%'
			OR BPB_R.BranchID = @CleanBranchID
			OR BPB_R.ADBranchID = @CleanBranchID
			OR BPB_R.ADCode = @CleanBranchID
			OR BPB_R.BranchCode = @CleanBranchID
			OR BPB_R.BranchName = @CleanBranchID
			OR BPB_R.BranchName LIKE '%' + @CleanBranchID + '%'
			OR (
				@BranchSuffix <> '' 
				AND (
					RIGHT(R.BranchID, CHARINDEX('/', REVERSE(R.BranchID) + '/') - 1) = @BranchSuffix
					OR RIGHT(ISNULL(MD.ADBranchID, ''), CHARINDEX('/', REVERSE(ISNULL(MD.ADBranchID, '')) + '/') - 1) = @BranchSuffix
				)
			)
		)
		AND (
			@CleanCurrency = '' 
			OR @CleanCurrency = 'All' 
			OR R.CurrencyCode = @CleanCurrency
			OR CLR.CurrencyCode = @CleanCurrency
		)
END
GO
