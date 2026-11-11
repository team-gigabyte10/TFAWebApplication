USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spRPT_PCCalculationPBL]    Script Date: 11/11/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[spRPT_PCCalculationPBL]
	@FromDate DATE,
	@ToDate DATE
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @RateForGroup VARCHAR(50);
	SELECT TOP 1
		@RateForGroup = ISNULL(NULLIF(ConvertRateForGroupAmount, ''), 'BC SELLING')
	FROM SystemManager..SystemSettings WITH (NOLOCK)
	WHERE ISNULL(IsDeleted, 0) = 0;

	IF ISNULL(@RateForGroup, '') = ''
		SET @RateForGroup = 'BC SELLING';

	DECLARE @USDRate DECIMAL(18, 8);
	SELECT TOP 1
		@USDRate = ISNULL(CLR.ConvertFactor, 0)
	FROM SystemManager..CurrencyLatestRate CLR WITH (NOLOCK)
	WHERE CLR.IsDeleted = 0
	  AND CLR.CurrencyCode = 'USD'
	  AND CLR.RateFor = @RateForGroup;

	IF ISNULL(@USDRate, 0) = 0
	BEGIN
		SELECT TOP 1
			@USDRate = ISNULL(CLR.ConvertFactor, 0)
		FROM SystemManager..CurrencyLatestRate CLR WITH (NOLOCK)
		WHERE CLR.IsDeleted = 0
		  AND CLR.CurrencyCode = 'USD';
	END;

	IF ISNULL(@USDRate, 0) = 0
		SET @USDRate = 0;

	;WITH CurrencyRates AS (
		SELECT
			CLR.CurrencyCode,
			MAX(CASE WHEN CLR.RateFor = @RateForGroup THEN CLR.ConvertFactor END) AS GroupRate,
			MAX(CLR.ConvertFactor) AS FallbackRate
		FROM SystemManager..CurrencyLatestRate CLR WITH (NOLOCK)
		WHERE CLR.IsDeleted = 0
		GROUP BY CLR.CurrencyCode
	),
	MasterDocValues AS (
		SELECT
			MD.MasterDocID,
			MD.GroupSysID,
			MD.LCNo,
			MD.IssueDate,
			MD.ShipmentDate,
			MD.ExpiryDate,
			COALESCE(NULLIF(Applicant.Name, ''), NULLIF(MD.Applicant, ''), NULLIF(Advi.Applicant, ''), '') AS Applicant,
			ISNULL(MD.PCMDLEntitlementPercent, 0) AS PCMDLEntitlementPercent,
			CASE
				WHEN ISNULL(NULLIF(MD.Currency, ''), GLC.CurrencyCode) = 'USD' THEN
					CASE
						WHEN ISNULL(MD.AmountToGroup, 0) > 0 THEN MD.AmountToGroup
						WHEN ISNULL(MD.LCAmount, 0) - ISNULL(MD.Commission, 0) - ISNULL(MD.Freight, 0) - ISNULL(MD.ReplacedAmount, 0) > 0
							THEN ISNULL(MD.LCAmount, 0) - ISNULL(MD.Commission, 0) - ISNULL(MD.Freight, 0) - ISNULL(MD.ReplacedAmount, 0)
						ELSE 0
					END
				WHEN ISNULL(@USDRate, 0) > 0 THEN
					(
						CASE
							WHEN ISNULL(MD.AmountToGroup, 0) > 0 THEN MD.AmountToGroup
							WHEN ISNULL(MD.LCAmount, 0) - ISNULL(MD.Commission, 0) - ISNULL(MD.Freight, 0) - ISNULL(MD.ReplacedAmount, 0) > 0
								THEN ISNULL(MD.LCAmount, 0) - ISNULL(MD.Commission, 0) - ISNULL(MD.Freight, 0) - ISNULL(MD.ReplacedAmount, 0)
							ELSE 0
						END
						* COALESCE(NULLIF(CR.GroupRate, 0), NULLIF(CR.FallbackRate, 0), 0)
					) / @USDRate
				ELSE 0
			END AS DocValueUSD
		FROM MasterDoc MD WITH (NOLOCK)
		INNER JOIN GroupLC GLC WITH (NOLOCK)
			ON GLC.GroupSysID = MD.GroupSysID
		LEFT JOIN LCAdvisingRegister Advi WITH (NOLOCK)
			ON Advi.LCReceiveID = MD.LCReceiveID
		LEFT JOIN SystemManager..Contacts Applicant WITH (NOLOCK)
			ON Applicant.Code = ISNULL(NULLIF(MD.Applicant, ''), Advi.Applicant)
		LEFT JOIN CurrencyRates CR
			ON CR.CurrencyCode = ISNULL(NULLIF(MD.Currency, ''), GLC.CurrencyCode)
		WHERE MD.IsDeleted = 0
		  AND ISNULL(MD.IsCancelled, 0) = 0
		  AND ISNULL(MD.GroupSysID, '') <> ''
		  AND GLC.IsDeleted = 0
	),
	ExportLC AS (
		SELECT
			MDV.GroupSysID,
			STUFF((
				SELECT DISTINCT ', ' + LTRIM(RTRIM(M2.LCNo))
				FROM MasterDocValues M2
				WHERE M2.GroupSysID = MDV.GroupSysID
				  AND ISNULL(LTRIM(RTRIM(M2.LCNo)), '') <> ''
				FOR XML PATH(''), TYPE
			).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS ExportLCNo,
			MIN(MDV.IssueDate) AS MinIssueDate,
			MAX(MDV.ShipmentDate) AS ShipmentDate,
			MAX(MDV.ExpiryDate) AS ExpiryDate,
			STUFF((
				SELECT DISTINCT ', ' + LTRIM(RTRIM(M2.Applicant))
				FROM MasterDocValues M2
				WHERE M2.GroupSysID = MDV.GroupSysID
				  AND ISNULL(LTRIM(RTRIM(M2.Applicant)), '') <> ''
				FOR XML PATH(''), TYPE
			).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS BuyerName,
			MAX(MDV.PCMDLEntitlementPercent) AS MaxMDPCEntitlementPercent,
			SUM(MDV.DocValueUSD) AS TotalMasterValueUSD
		FROM MasterDocValues MDV
		GROUP BY MDV.GroupSysID
	),
	BTBUtilized AS (
		SELECT
			B.GroupSysID,
			SUM(
				CASE
					WHEN ISNULL(NULLIF(B.Currency, ''), 'USD') = 'USD' THEN ISNULL(B.BBLCAmount, 0)
					WHEN ISNULL(@USDRate, 0) > 0 THEN
						(ISNULL(B.BBLCAmount, 0) * COALESCE(NULLIF(CR.GroupRate, 0), NULLIF(CR.FallbackRate, 0), 0)) / @USDRate
					ELSE 0
				END
			) AS BTBAmountUSD
		FROM BBLCMaster B WITH (NOLOCK)
		LEFT JOIN CurrencyRates CR
			ON CR.CurrencyCode = B.Currency
		WHERE B.IsDeleted = 0
		  AND ISNULL(B.IsCancelled, 0) = 0
		  AND ISNULL(B.GroupSysID, '') <> ''
		GROUP BY B.GroupSysID
	),
	ExportBills AS (
		SELECT
			MD.GroupSysID,
			CASE
				WHEN ISNULL(NULLIF(EBI.BILL_CCY, ''), 'USD') = 'USD' THEN ISNULL(EBI.ExportBillAmount, 0)
				WHEN ISNULL(@USDRate, 0) > 0 THEN
					(ISNULL(EBI.ExportBillAmount, 0) * COALESCE(NULLIF(CR.GroupRate, 0), NULLIF(CR.FallbackRate, 0), 0)) / @USDRate
				ELSE 0
			END AS BillAmountUSD
		FROM ExportBillInitiationMaster EBI WITH (NOLOCK)
		INNER JOIN MasterDoc MD WITH (NOLOCK)
			ON MD.MasterDocID = EBI.MasterDocID
		LEFT JOIN CurrencyRates CR
			ON CR.CurrencyCode = EBI.BILL_CCY
		WHERE EBI.IsDeleted = 0
		  AND MD.IsDeleted = 0
		  AND ISNULL(MD.IsCancelled, 0) = 0
		  AND ISNULL(MD.GroupSysID, '') <> ''

		UNION ALL

		SELECT
			MD.GroupSysID,
			CASE
				WHEN ISNULL(NULLIF(LEBI.BILL_CCY, ''), 'USD') = 'USD' THEN ISNULL(LEBI.ExportLocalBillAmount, 0)
				WHEN ISNULL(@USDRate, 0) > 0 THEN
					(ISNULL(LEBI.ExportLocalBillAmount, 0) * COALESCE(NULLIF(CR.GroupRate, 0), NULLIF(CR.FallbackRate, 0), 0)) / @USDRate
				ELSE 0
			END AS BillAmountUSD
		FROM LocalExportBillInitiationMaster LEBI WITH (NOLOCK)
		INNER JOIN MasterDoc MD WITH (NOLOCK)
			ON MD.MasterDocID = LEBI.MasterDocID
		LEFT JOIN CurrencyRates CR
			ON CR.CurrencyCode = LEBI.BILL_CCY
		WHERE LEBI.IsDeleted = 0
		  AND MD.IsDeleted = 0
		  AND ISNULL(MD.IsCancelled, 0) = 0
		  AND ISNULL(MD.GroupSysID, '') <> ''
	),
	ExportMade AS (
		SELECT
			EB.GroupSysID,
			SUM(EB.BillAmountUSD) AS ExportMadeUSD
		FROM ExportBills EB
		GROUP BY EB.GroupSysID
	),
	PCLimit AS (
		SELECT
			LAT.MasterID AS GroupSysID,
			SUM(ISNULL(LAT.Percentage, 0)) AS PCLimitPercent
		FROM LimitApprovalTransaction LAT WITH (NOLOCK)
		WHERE LAT.IsDeleted = 0
		  AND LAT.LimitType = 'PC'
		  AND ISNULL(LAT.MasterID, '') <> ''
		GROUP BY LAT.MasterID
	),
	PCAdjustments AS (
		SELECT
			LAIC.LoanCreationID,
			SUM(
				CASE
					WHEN ISNULL(LAIC.AC_CCY, 'BDT') = 'BDT' OR ISNULL(LAIC.EXCH_RATE, 0) = 0 THEN ISNULL(LAIC.AdjustmentAmount, 0)
					WHEN ISNULL(LAIC.AdjustmentAmount, 0) > 0 THEN ISNULL(LAIC.AdjustmentAmount, 0)
					ELSE ISNULL(LAIC.FCY_AMOUNT, 0) * ISNULL(LAIC.EXCH_RATE, 0)
				END
			) AS AdjustedAmountBDT
		FROM LoanAdjustmentInvoiceChild LAIC WITH (NOLOCK)
		WHERE LAIC.IsDeleted = 0
		  AND ISNULL(LAIC.LoanCreationID, '') <> ''
		GROUP BY LAIC.LoanCreationID
	),
	LoanOSByNumber AS (
		SELECT
			LO.LoanNumber,
			MAX(ISNULL(LO.PRINCIPAL_OS, 0)) AS PRINCIPAL_OS,
			MAX(ISNULL(LO.TOT_OS, 0)) AS TOT_OS
		FROM LoanOutstanding LO WITH (NOLOCK)
		WHERE ISNULL(LO.LoanNumber, '') <> ''
		GROUP BY LO.LoanNumber
	),
	LoanOSByAccount AS (
		SELECT
			LO.AccountNumber,
			MAX(ISNULL(LO.PRINCIPAL_OS, 0)) AS PRINCIPAL_OS,
			MAX(ISNULL(LO.TOT_OS, 0)) AS TOT_OS
		FROM LoanOutstanding LO WITH (NOLOCK)
		WHERE ISNULL(LO.AccountNumber, '') <> ''
		GROUP BY LO.AccountNumber
	),
	PCDisb AS (
		SELECT
			COALESCE(NULLIF(PCM.GroupRefID, ''), MD_PCM.GroupSysID, '') AS GroupSysID,
			MAX(NULLIF(PCM.BranchID, '')) AS BranchID,
			SUM(
				CASE
					WHEN (
						PCM.PCDisburseDate IS NOT NULL
						OR ISNULL(PCM.IsCheck, 0) = 1
						OR ISNULL(PCM.UBSSyncProcessID, 0) > 0
						OR ISNULL(PCM.IsPCNumberGenerated, 0) = 1
						OR ISNULL(PCM.AdditionalFilter, '') <> ''
					)
					AND CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) AS DATE) BETWEEN @FromDate AND @ToDate
						THEN 1
					ELSE 0
				END
			) AS DisbCountInRange,
			SUM(
				CASE
					WHEN (
						PCM.PCDisburseDate IS NOT NULL
						OR ISNULL(PCM.IsCheck, 0) = 1
						OR ISNULL(PCM.UBSSyncProcessID, 0) > 0
						OR ISNULL(PCM.IsPCNumberGenerated, 0) = 1
						OR ISNULL(PCM.AdditionalFilter, '') <> ''
					)
					AND CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) AS DATE) BETWEEN @FromDate AND @ToDate
						THEN COALESCE(
							NULLIF(PCM.PCAmountTK, 0),
							ISNULL(PCM.PCAmount, 0) * COALESCE(NULLIF(PCM.ExchangeRate, 0), @USDRate, 0),
							0
						)
					ELSE 0
				END
			) AS TotalPCDisbursed,
			SUM(
				CASE
					WHEN (
						PCM.PCDisburseDate IS NOT NULL
						OR ISNULL(PCM.IsCheck, 0) = 1
						OR ISNULL(PCM.UBSSyncProcessID, 0) > 0
						OR ISNULL(PCM.IsPCNumberGenerated, 0) = 1
						OR ISNULL(PCM.AdditionalFilter, '') <> ''
					)
					AND PCM.ClosedDate IS NULL
					AND CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) AS DATE) <= @ToDate
						THEN CASE
							WHEN ISNULL(PCM.UBSSyncProcessID, 0) > 0 THEN
								CASE
									WHEN ISNULL(PCM.PRINCIPAL_OS, 0) > 0 THEN PCM.PRINCIPAL_OS
									ELSE ISNULL(PCM.TOT_OS, 0)
								END
							WHEN COALESCE(NULLIF(LO_NUM.PRINCIPAL_OS, 0), NULLIF(LO_ACC.PRINCIPAL_OS, 0), 0) > 0
								THEN COALESCE(NULLIF(LO_NUM.PRINCIPAL_OS, 0), NULLIF(LO_ACC.PRINCIPAL_OS, 0), 0)
							WHEN COALESCE(NULLIF(LO_NUM.TOT_OS, 0), NULLIF(LO_ACC.TOT_OS, 0), 0) > 0
								THEN COALESCE(NULLIF(LO_NUM.TOT_OS, 0), NULLIF(LO_ACC.TOT_OS, 0), 0)
							ELSE
								CASE
									WHEN COALESCE(NULLIF(PCM.PCAmountTK, 0), ISNULL(PCM.PCAmount, 0) * COALESCE(NULLIF(PCM.ExchangeRate, 0), @USDRate, 0), 0) - ISNULL(ADJ.AdjustedAmountBDT, 0) > 0
										THEN COALESCE(NULLIF(PCM.PCAmountTK, 0), ISNULL(PCM.PCAmount, 0) * COALESCE(NULLIF(PCM.ExchangeRate, 0), @USDRate, 0), 0) - ISNULL(ADJ.AdjustedAmountBDT, 0)
									ELSE 0
								END
						END
					ELSE 0
				END
			) AS PCOutstandingBDT,
			SUM(
				CASE
					WHEN PCM.PCDisburseDate IS NULL
					 AND ISNULL(PCM.IsCheck, 0) = 0
					 AND ISNULL(PCM.UBSSyncProcessID, 0) = 0
					 AND ISNULL(PCM.IsPCNumberGenerated, 0) = 0
					 AND ISNULL(PCM.AdditionalFilter, '') = ''
					 AND PCM.ClosedDate IS NULL
					 AND CAST(PCM.PCCreationDate AS DATE) <= @ToDate
						THEN COALESCE(
							NULLIF(PCM.PCAmountTK, 0),
							ISNULL(PCM.PCAmount, 0) * COALESCE(NULLIF(PCM.ExchangeRate, 0), @USDRate, 0),
							0
						)
					ELSE 0
				END
			) AS IntendedDisbBDT
		FROM PCDisbursementMaster PCM WITH (NOLOCK)
		LEFT JOIN MasterDoc MD_PCM WITH (NOLOCK)
			ON MD_PCM.MasterDocID = PCM.MasterDocID
		   AND MD_PCM.IsDeleted = 0
		LEFT JOIN PCAdjustments ADJ
			ON ADJ.LoanCreationID = PCM.PCDMID
		LEFT JOIN LoanOSByNumber LO_NUM
			ON LO_NUM.LoanNumber = PCM.AdditionalFilter
		LEFT JOIN LoanOSByAccount LO_ACC
			ON LO_ACC.AccountNumber = PCM.ExternalID
		WHERE PCM.IsDeleted = 0
		  AND COALESCE(NULLIF(PCM.GroupRefID, ''), MD_PCM.GroupSysID, '') <> ''
		GROUP BY COALESCE(NULLIF(PCM.GroupRefID, ''), MD_PCM.GroupSysID, '')
	),
	BaseCalc AS (
		SELECT
			GLC.GroupSysID,
			ISNULL(ELC.ExportLCNo, '') AS ExportLCNo,
			ISNULL(GLC.GroupRefNo, '') AS JobNo,
			CAST(
				CASE
					WHEN ISNULL(GLC.GroupAmount, 0) > 0 THEN
						CASE
							WHEN ISNULL(NULLIF(GLC.CurrencyCode, ''), 'USD') = 'USD' THEN GLC.GroupAmount
							WHEN ISNULL(@USDRate, 0) > 0 THEN
								(GLC.GroupAmount * COALESCE(NULLIF(CR_G.GroupRate, 0), NULLIF(CR_G.FallbackRate, 0), 0)) / @USDRate
							ELSE 0
						END
					ELSE ISNULL(ELC.TotalMasterValueUSD, 0)
				END AS DECIMAL(18, 2)
			) AS TotalExportLCValueUSD,
			CASE
				WHEN BTB.GroupSysID IS NOT NULL THEN ISNULL(BTB.BTBAmountUSD, 0)
				WHEN ISNULL(NULLIF(GLC.CurrencyCode, ''), 'USD') = 'USD' THEN ISNULL(GLC.AmtUtilized, 0)
				WHEN ISNULL(@USDRate, 0) > 0 THEN
					(ISNULL(GLC.AmtUtilized, 0) * COALESCE(NULLIF(CR_G.GroupRate, 0), NULLIF(CR_G.FallbackRate, 0), 0)) / @USDRate
				ELSE 0
			END AS BTBAmountUSD,
			CAST(ISNULL(PC.TotalPCDisbursed, 0) AS DECIMAL(18, 2)) AS TotalPCDisbursed,
			ELC.ShipmentDate,
			ELC.ExpiryDate,
			ISNULL(ELC.BuyerName, '') AS BuyerName,
			ISNULL(EM.ExportMadeUSD, 0) AS ExportMadeUSD,
			CAST(ISNULL(PC.PCOutstandingBDT, 0) AS DECIMAL(18, 2)) AS PCOutstandingBDT,
			CAST(ISNULL(PC.IntendedDisbBDT, 0) AS DECIMAL(18, 2)) AS IntendedDisbBDT,
			CAST(
				COALESCE(
					NULLIF(PL.PCLimitPercent, 0),
					NULLIF(GLC.GroupPCMDLEntitlementPercent, 0),
					NULLIF(ELC.MaxMDPCEntitlementPercent, 0),
					NULLIF(CPM.MaxPerPCMDLEntitlement, 0),
					0
				) AS DECIMAL(18, 4)
			) AS PCEntitlementPct,
			COALESCE(NULLIF(GLC.BankBranchID, ''), NULLIF(GLC.ADBranchID, ''), NULLIF(PC.BranchID, ''), '') AS BranchID,
			ISNULL(BPB.BranchName, '') AS BranchName,
			ISNULL(GLC.CustomerID, '') AS CustomerID,
			ISNULL(CPM.CustomerName, '') AS CustomerName,
			ISNULL(PC.DisbCountInRange, 0) AS DisbCountInRange
		FROM GroupLC GLC WITH (NOLOCK)
		LEFT JOIN PCDisb PC
			ON PC.GroupSysID = GLC.GroupSysID
		LEFT JOIN ExportLC ELC
			ON ELC.GroupSysID = GLC.GroupSysID
		LEFT JOIN BTBUtilized BTB
			ON BTB.GroupSysID = GLC.GroupSysID
		LEFT JOIN ExportMade EM
			ON EM.GroupSysID = GLC.GroupSysID
		LEFT JOIN PCLimit PL
			ON PL.GroupSysID = GLC.GroupSysID
		LEFT JOIN CurrencyRates CR_G
			ON CR_G.CurrencyCode = GLC.CurrencyCode
		LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH (NOLOCK)
			ON CPM.CustomerID = GLC.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BPB WITH (NOLOCK)
			ON BPB.BranchID = COALESCE(NULLIF(GLC.BankBranchID, ''), NULLIF(GLC.ADBranchID, ''), NULLIF(PC.BranchID, ''))
		WHERE GLC.IsDeleted = 0
		  AND ISNULL(GLC.IsMigrated, 0) = 0
		  AND ISNULL(GLC.IsClosedGroup, 0) = 0
		  AND (
			  ISNULL(PC.DisbCountInRange, 0) > 0
			  OR CAST(COALESCE(ELC.MinIssueDate, GLC.DateAdded) AS DATE) BETWEEN @FromDate AND @ToDate
		  )
	),
	FinalCalc AS (
		SELECT
			BC.GroupSysID,
			BC.ExportLCNo,
			BC.JobNo,
			BC.TotalExportLCValueUSD AS TotalExportLCValue,
			CAST(
				CASE
					WHEN BC.TotalExportLCValueUSD > 0 THEN (BC.BTBAmountUSD / BC.TotalExportLCValueUSD) * 100.0
					ELSE 0
				END AS DECIMAL(18, 4)
			) AS BTBUtilizedPct,
			BC.TotalPCDisbursed,
			CAST(
				(BC.TotalExportLCValueUSD * @USDRate * (BC.PCEntitlementPct / 100.0)) - BC.TotalPCDisbursed
				AS DECIMAL(18, 2)
			) AS RoomForNewPC,
			BC.ShipmentDate,
			BC.ExpiryDate,
			BC.BuyerName,
			CAST(
				CASE
					WHEN BC.TotalExportLCValueUSD - BC.ExportMadeUSD > 0
						THEN BC.TotalExportLCValueUSD - BC.ExportMadeUSD
					ELSE 0
				END AS DECIMAL(18, 2)
			) AS ExportToBeMade,
			BC.PCOutstandingBDT,
			CAST(BC.PCOutstandingBDT + BC.IntendedDisbBDT AS DECIMAL(18, 2)) AS OutPlusIntendedDisb,
			CAST(
				(
					CASE
						WHEN BC.TotalExportLCValueUSD - BC.ExportMadeUSD > 0
							THEN BC.TotalExportLCValueUSD - BC.ExportMadeUSD
						ELSE 0
					END
				) * @USDRate * (BC.PCEntitlementPct / 100.0)
				AS DECIMAL(18, 2)
			) AS CanBeAdjustBDT,
			BC.PCEntitlementPct,
			CAST(@USDRate AS DECIMAL(18, 4)) AS USDRate,
			BC.IntendedDisbBDT,
			BC.BranchID,
			BC.BranchName,
			BC.CustomerID,
			BC.CustomerName
		FROM BaseCalc BC
		WHERE BC.TotalExportLCValueUSD > 0
		   OR BC.TotalPCDisbursed > 0
		   OR BC.PCOutstandingBDT > 0
		   OR BC.IntendedDisbBDT > 0
	)
	SELECT
		ROW_NUMBER() OVER (ORDER BY FC.CustomerName, FC.JobNo) AS SlNo,
		FC.ExportLCNo,
		FC.JobNo,
		FC.TotalExportLCValue,
		FC.BTBUtilizedPct,
		FC.TotalPCDisbursed,
		FC.RoomForNewPC,
		FC.ShipmentDate,
		FC.ExpiryDate,
		FC.BuyerName,
		FC.ExportToBeMade,
		FC.PCOutstandingBDT,
		FC.OutPlusIntendedDisb,
		FC.CanBeAdjustBDT,
		CAST(FC.CanBeAdjustBDT - FC.OutPlusIntendedDisb AS DECIMAL(18, 2)) AS Difference,
		FC.PCEntitlementPct,
		FC.USDRate,
		FC.IntendedDisbBDT,
		FC.BranchID,
		FC.BranchName,
		FC.CustomerID,
		FC.CustomerName,
		FC.GroupSysID
	FROM FinalCalc FC
	ORDER BY FC.CustomerName, FC.JobNo;
END
GO

