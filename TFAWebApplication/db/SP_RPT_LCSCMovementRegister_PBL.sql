USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_LCSCMovementRegister_PBL]    Script Date: 11/23/2026 10:14:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_LCSCMovementRegister_PBL]
@FromDate DATETIME,
@ToDate DATETIME
AS
BEGIN

SELECT DISTINCT
	M.Dateadded AS TransactionDate,
	MD.Dateadded AS DateAdded,
	CPM.CustomerName AS ClientsName,
	COALESCE(
		NULLIF(ADbpb.BranchName, ''), 
		CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, 
		''
	) AS ADBranchName,
	SOURC.GroupRefNo AS FromGroup,
	DESTINATION.GroupRefNo AS ToGroup,
	CASE WHEN MD.IsSC = 1 THEN 'SC' ELSE 'LC' END AS InstrumentTypeLCSC,
	MD.LCno AS InstrumentLCSCNumber,
	MD.Currency AS Curr,
	MD.LCAmount AS InstrumentValue,
	COALESCE(
		NULLIF(MD.ReplacedAmount, 0),
		NULLIF(CR_LC.TotalReplacedAmt, 0),
		NULLIF(CR_SC.TotalReplacedAmt, 0),
		0
	) AS RelatedReplacedLCValue,
	ISNULL((SELECT SUM(ExportBillAmount) FROM ExportBillInitiationMaster E WITH(NOLOCK) WHERE E.MasterDocID = MD.MasterDocID AND E.IsDeleted = 0 AND E.IsCancelled = 0), 0) AS RelatedFDBCValue,
	@FromDate AS TransactionFromDate,
	@ToDate AS TransactionToDate,
	COALESCE(
		NULLIF(ADbpb.BranchID, ''), 
		CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END, 
		''
	) AS ADBranchID,
	MD.MasterDocID AS MasterDocID,
	CASE 
		WHEN NonADbpb.BranchName IS NOT NULL 
			 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
		THEN ISNULL(NonADbpb.BranchID, '')
		WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
			 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
		THEN ISNULL(BPB.BranchID, '')
		ELSE ''
	END AS NonADBranchID,
	CPM.CustomerID AS CustomerID,
	MD.LCno AS LCNumber
FROM MasterLCMovementBetweenGroups M WITH(NOLOCK)
	LEFT JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = M.MasterDocID
	LEFT JOIN GroupLC DESTINATION WITH(NOLOCK) ON M.SGGroupSysID = DESTINATION.GroupSysID
	LEFT JOIN GroupLC SOURC WITH(NOLOCK) ON M.FGGroupSysID = SOURC.GroupSysID
	LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = MD.CustomerID
	LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON 
		BPB.BranchID = COALESCE(NULLIF(MD.BranchID, ''), NULLIF(SOURC.BankBranchID, ''), NULLIF(DESTINATION.BankBranchID, ''))
		OR BPB.BranchID = REPLACE(COALESCE(NULLIF(MD.BranchID, ''), NULLIF(SOURC.BankBranchID, ''), NULLIF(DESTINATION.BankBranchID, '')), 'BPB/22/', 'OBPB/25/')
		OR BPB.BranchID = REPLACE(COALESCE(NULLIF(MD.BranchID, ''), NULLIF(SOURC.BankBranchID, ''), NULLIF(DESTINATION.BankBranchID, '')), 'OBPB/25/', 'BPB/22/')
	LEFT JOIN SystemManager..BankProfileBranch ADbpb WITH(NOLOCK) ON 
		ADbpb.IsADCode = 1 AND (
			ADbpb.BranchID = COALESCE(
				NULLIF(MD.ADBranchID, ''), 
				NULLIF(SOURC.ADBranchID, ''), 
				NULLIF(DESTINATION.ADBranchID, ''), 
				CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END
			)
			OR ADbpb.BranchID = REPLACE(COALESCE(
				NULLIF(MD.ADBranchID, ''), 
				NULLIF(SOURC.ADBranchID, ''), 
				NULLIF(DESTINATION.ADBranchID, ''), 
				CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END
			), 'BPB/22/', 'OBPB/25/')
			OR ADbpb.BranchID = REPLACE(COALESCE(
				NULLIF(MD.ADBranchID, ''), 
				NULLIF(SOURC.ADBranchID, ''), 
				NULLIF(DESTINATION.ADBranchID, ''), 
				CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END
			), 'OBPB/25/', 'BPB/22/')
		)
	LEFT JOIN SystemManager..BankProfileBranch NonADbpb WITH(NOLOCK) ON 
		(
			NonADbpb.BranchID = COALESCE(NULLIF(MD.BranchID, ''), NULLIF(SOURC.BankBranchID, ''), NULLIF(DESTINATION.BankBranchID, ''))
			OR NonADbpb.BranchID = REPLACE(COALESCE(NULLIF(MD.BranchID, ''), NULLIF(SOURC.BankBranchID, ''), NULLIF(DESTINATION.BankBranchID, '')), 'BPB/22/', 'OBPB/25/')
			OR NonADbpb.BranchID = REPLACE(COALESCE(NULLIF(MD.BranchID, ''), NULLIF(SOURC.BankBranchID, ''), NULLIF(DESTINATION.BankBranchID, '')), 'OBPB/25/', 'BPB/22/')
		)
		AND NonADbpb.IsADCode = 0
	LEFT JOIN (
		SELECT 
			CRBLCD.MasterLCID,
			SUM(CRBLCD.ReplacementAmt) AS TotalReplacedAmt
		FROM ContractReplacementByLCDetails CRBLCD WITH(NOLOCK)
		INNER JOIN ContractReplacementByLC CRBLC WITH(NOLOCK) 
			ON CRBLC.CRBLCID = CRBLCD.CRBLCID AND CRBLC.IsDeleted = 0
		WHERE CRBLCD.IsDeleted = 0
		GROUP BY CRBLCD.MasterLCID
	) CR_LC ON CR_LC.MasterLCID = MD.MasterDocID
	LEFT JOIN (
		SELECT 
			CRBLCD.SCID,
			SUM(CRBLCD.ReplacementAmt) AS TotalReplacedAmt
		FROM ContractReplacementByLCDetails CRBLCD WITH(NOLOCK)
		INNER JOIN ContractReplacementByLC CRBLC WITH(NOLOCK) 
			ON CRBLC.CRBLCID = CRBLCD.CRBLCID AND CRBLC.IsDeleted = 0
		WHERE CRBLCD.IsDeleted = 0
		GROUP BY CRBLCD.SCID
	) CR_SC ON CR_SC.SCID = MD.MasterDocID
	LEFT JOIN SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.CODE = MD.Applicant
WHERE M.IsDeleted = 0  
	AND MD.IsCancelled = 0 
	AND (
		(@FromDate IS NULL AND @ToDate IS NULL)
		OR (CONVERT(DATE, M.Dateadded) BETWEEN @FromDate AND @ToDate)
		OR (CONVERT(DATE, MD.DateAdded) BETWEEN @FromDate AND @ToDate)
	)
ORDER BY M.Dateadded ASC

END
