USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_ExportComparisonDestinationCountryWisePBL]    Script Date: 11/5/2026 4:32:08 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[SP_RPT_ExportComparisonDestinationCountryWisePBL]
	@FromDate DATETIME,	@ToDate DATETIME,
	@FromDate2 DATETIME, @ToDate2 DATETIME
 
AS
	-- SP_RPT_ExportComparisonDestinationCountryWisePBL '2024-01-01' , '2024-04-01','2024-06-30' , '2024-03-30'
BEGIN
	DECLARE @USDRate NUMERIC(18,4);
	SELECT @USDRate = ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) WHERE RateFor = 'MID RATE' AND CurrencyCode = 'USD'

	select distinct
		CountryName,
		CountryCode,
		Currency,
		isnull(sum(ExportAmountFromDateToDate), 0) ExportAmountFromDateToDate, 
		isnull(sum(ExportAmountFromDateToDate2), 0) ExportAmountFromDateToDate2, 
		IncreaseDecrease = isnull(isnull(sum(ExportAmountFromDateToDate), 0) - isnull(sum(ExportAmountFromDateToDate2), 0),0),
		PofIncreaseDecrease = isnull(isnull(isnull(sum(ExportAmountFromDateToDate), 0) - isnull(sum(ExportAmountFromDateToDate2), 0),0) / nullif(isnull(sum(ExportAmountFromDateToDate2), 0),0)*100, 100)
	from (
		SELECT distinct
			CountryName = COALESCE(EXPCountry.CountryName, NULLIF(EXPRC.Country, ''), CAST(EXPRC.CountryCode AS VARCHAR(50))),
			CountryCode = COALESCE(EXPCountry.CountryCode, CAST(EXPRC.CountryCode AS VARCHAR(50)), EXPRC.CountryID),
			Currency = EXPRC.CurrIso,
			(isnull(EXPRC.AmountInv, 0) * CLR.ConvertFactor)/@USDRate ExportAmountFromDateToDate,
			0 ExportAmountFromDateToDate2
		from EXPRegisterChild EXPRC with(nolock)
			LEFT JOIN MasterDoc MD with(nolock) ON MD.MasterDocID = EXPRC.MasterDocID
			LEFT JOIN LCAdvisingRegister LCAR ON LCAR.LCReceiveID =isnull(MD.LCReceiveID, EXPRC.MasterDocID)
			LEFT JOIN GROUPLC GLC with(nolock) on GLC.GroupSysID = MD.GroupSysID
			LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = EXPRC.CustomerID
			LEFT JOIN SystemManager..BankProfileBranch NonADbranch on NonADbranch.BranchID=GLC.BankBranchID
			LEFT JOIN SystemManager..BankProfileBranch ADbranch on ADbranch.BranchID=isnull(GLC.ADBranchID,EXPRC.BranchName)
			OUTER APPLY (
				SELECT TOP 1 C.CountryName, C.CountryCode, C.CountryID
				FROM SystemManager..Country C WITH(NOLOCK)
				WHERE C.IsDeleted = 0
				  AND (
					  (EXPRC.CountryCode IS NOT NULL AND C.CountryCode = CAST(EXPRC.CountryCode AS VARCHAR(50)))
					  OR (EXPRC.CountryID IS NOT NULL AND C.CountryID = EXPRC.CountryID)
					  OR (EXPRC.Country IS NOT NULL AND (C.CountryName = EXPRC.Country OR C.CountryCode = EXPRC.Country OR C.CountryID = EXPRC.Country))
					  OR (EXPRC.CountryCode IS NOT NULL AND C.SequenceNo = EXPRC.CountryCode)
				  )
				ORDER BY 
					CASE 
						WHEN EXPRC.CountryCode IS NOT NULL AND C.CountryCode = CAST(EXPRC.CountryCode AS VARCHAR(50)) THEN 1
						WHEN EXPRC.CountryID IS NOT NULL AND C.CountryID = EXPRC.CountryID THEN 2
						WHEN EXPRC.Country IS NOT NULL AND C.CountryName = EXPRC.Country THEN 3
						ELSE 4 
					END
			) EXPCountry
			left join SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = EXPRC.CurrIso AND CLR.RateFor = 'MID RATE'
		where cast(EXPRC.EntDate as date) between @FromDate and @ToDate
			and EXPRC.ExpSerial is not null and EXPRC.IsDeleted = 0

		union all

		SELECT distinct
			CountryName = COALESCE(EXPCountry.CountryName, NULLIF(EXPRC.Country, ''), CAST(EXPRC.CountryCode AS VARCHAR(50))),
			CountryCode = COALESCE(EXPCountry.CountryCode, CAST(EXPRC.CountryCode AS VARCHAR(50)), EXPRC.CountryID),
			Currency = EXPRC.CurrIso,
			0 ExportAmountFromDateToDate,
			(isnull(EXPRC.AmountInv, 0) * CLR.ConvertFactor)/@USDRate ExportAmountFromDateToDate2
		from EXPRegisterChild EXPRC with(nolock)
			LEFT JOIN MasterDoc MD with(nolock) ON MD.MasterDocID = EXPRC.MasterDocID
			LEFT JOIN LCAdvisingRegister LCAR ON LCAR.LCReceiveID =isnull(MD.LCReceiveID, EXPRC.MasterDocID)
			LEFT JOIN GROUPLC GLC with(nolock) on GLC.GroupSysID = MD.GroupSysID
			LEFT JOIN SystemManager..CustomerProfileMaster CPM ON CPM.CustomerID = EXPRC.CustomerID
			LEFT JOIN SystemManager..BankProfileBranch NonADbranch on NonADbranch.BranchID=GLC.BankBranchID
			LEFT JOIN SystemManager..BankProfileBranch ADbranch on ADbranch.BranchID=isnull(GLC.ADBranchID,EXPRC.BranchName)
			OUTER APPLY (
				SELECT TOP 1 C.CountryName, C.CountryCode, C.CountryID
				FROM SystemManager..Country C WITH(NOLOCK)
				WHERE C.IsDeleted = 0
				  AND (
					  (EXPRC.CountryCode IS NOT NULL AND C.CountryCode = CAST(EXPRC.CountryCode AS VARCHAR(50)))
					  OR (EXPRC.CountryID IS NOT NULL AND C.CountryID = EXPRC.CountryID)
					  OR (EXPRC.Country IS NOT NULL AND (C.CountryName = EXPRC.Country OR C.CountryCode = EXPRC.Country OR C.CountryID = EXPRC.Country))
					  OR (EXPRC.CountryCode IS NOT NULL AND C.SequenceNo = EXPRC.CountryCode)
				  )
				ORDER BY 
					CASE 
						WHEN EXPRC.CountryCode IS NOT NULL AND C.CountryCode = CAST(EXPRC.CountryCode AS VARCHAR(50)) THEN 1
						WHEN EXPRC.CountryID IS NOT NULL AND C.CountryID = EXPRC.CountryID THEN 2
						WHEN EXPRC.Country IS NOT NULL AND C.CountryName = EXPRC.Country THEN 3
						ELSE 4 
					END
			) EXPCountry
			left join SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = EXPRC.CurrIso AND CLR.RateFor = 'MID RATE'
		where cast(EXPRC.EntDate as date) between @FromDate2 and @ToDate2
			and EXPRC.ExpSerial is not null and EXPRC.IsDeleted = 0
	) A
	group by CountryName, CountryCode, Currency
END