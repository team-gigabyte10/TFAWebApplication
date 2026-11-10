USE EFA
GO

CREATE OR ALTER PROC [dbo].[spRPT_PCRegisterPBL]
	@FromDate DATE,
	@ToDate DATE
AS
	-- spRPT_PCRegisterPBL '2024-01-01', '2026-10-27'
BEGIN
	SET NOCOUNT ON;

	DECLARE @USDRate DECIMAL(18,4);
	SELECT @USDRate = ConvertFactor 
	FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) 
	WHERE RateFor = 'BC SELLING' AND CurrencyCode = 'USD';

	IF @USDRate IS NULL OR @USDRate = 0
		SET @USDRate = 1;

	SELECT
		BPB.BranchName																AS BranchName,
		CPM.CustomerName															AS CustomerName,
		CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) AS DATE)				AS DisburseDate,
		PCM.AdditionalFilter														AS PCNumber,
		GLC.GroupRefNo																AS GroupRefNo,
		'BDT'																		AS LoanCurrency,
		PCM.InterestRate															AS InterestRate,
		PCM.ExchangeRate															AS ExchangeRate,
		PCM.MasterDocID																AS PCCondition,
		PCM.DrawdownPercentage														AS PctOfPCDisbursement,
		PCM.PCAmountTK																AS LoanAmount,
		CAST(
			COALESCE(
				NULLIF(PCM.PCAmount, 0),
				CASE 
					WHEN ISNULL(PCM.ExchangeRate, 0) > 0 THEN PCM.PCAmountTK / PCM.ExchangeRate
					WHEN @USDRate > 0 THEN PCM.PCAmountTK / @USDRate
					ELSE 0 
				END
			) AS DECIMAL(18, 2)
		)																			AS USDEquivalent,
		CAST(
			COALESCE(
				PCM.MATURITY_DATE,
				PCD_ADJ.MaturityDate,
				PCM.ExpiryDate,
				PCM.InterestDueDate,
				LC.MATURITY_DATE,
				LC.LoanExpiry,
				CASE 
					WHEN ISNULL(PCM.TenorDays, 0) > 0 
						THEN DATEADD(DAY, PCM.TenorDays, ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate))
					WHEN ISNULL(PCD_ADJ.Tenor, 0) > 0 
						THEN DATEADD(DAY, PCD_ADJ.Tenor, ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate))
					WHEN TRY_CAST(LC.Tenor AS INT) > 0 
						THEN DATEADD(DAY, TRY_CAST(LC.Tenor AS INT), ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate))
					WHEN TRY_CAST(LEFT(LTRIM(PCM.TenorDescription), 3) AS INT) > 0 
						THEN DATEADD(DAY, TRY_CAST(LEFT(LTRIM(PCM.TenorDescription), 3) AS INT), ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate))
				END,
				MD.ExpiryDate,
				MD_GRP.MaxLCExpiryDate,
				MD.ShipmentDate,
				MD_GRP.MaxLCShipmentDate,
				DATEADD(DAY, 90, ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate))
			) AS DATE
		)																			AS MaturityDate,
		ISNULL(NULLIF(PCM.PRINCIPAL_OS, 0), PCM.PCAmountTK)							AS LoanOutAmt,
		COALESCE(
			NULLIF(LAIC.AdjustmentAmount, 0),
			NULLIF(PCD_ADJ.AdjustmentAmount, 0),
			CASE 
				WHEN ISNULL(PCM.PRINCIPAL_OS, PCM.PCAmountTK) < PCM.PCAmountTK 
					THEN (PCM.PCAmountTK - PCM.PRINCIPAL_OS)
				WHEN PCM.ClosedDate IS NOT NULL 
					THEN PCM.PCAmountTK
				ELSE 0 
			END,
			0
		)																			AS AdjustedAmount,
		CAST(
			COALESCE(
				LAIC.AdjustedDate,
				PCD_ADJ.AdjustedDate,
				CASE 
					WHEN ISNULL(PCM.PRINCIPAL_OS, PCM.PCAmountTK) < PCM.PCAmountTK OR PCM.ClosedDate IS NOT NULL 
						THEN COALESCE(PCM.ClosedDate, PCM.DateUpdated, PCM.PCApplyDate)
				END
			) AS DATE
		)																			AS AdjustedDate,
		ISNULL(PCM.UpdatedBy, PCM.AddedBy)											AS LastModifiedBy,
		ISNULL(GLC.BankBranchID, PCM.BranchID)										AS BranchID,
		PCM.CustomerID																AS CustomerID
	FROM PCDisbursementMaster PCM WITH(NOLOCK)
		LEFT JOIN
		(
			SELECT
				PCD_Key,
				MAX(MATURITY_DATE)															AS MaturityDate,
				MAX(TENOR)																	AS Tenor,
				SUM(AdjustmentAmount)														AS AdjustmentAmount,
				MAX(COALESCE(DateUpdated, DateAdded, BOOK_DATE, PCGenerationDate))			AS AdjustedDate
			FROM (
				SELECT 
					COALESCE(NULLIF(PCDMID, ''), NULLIF(PCNumber, ''), ExternalID) AS PCD_Key,
					MATURITY_DATE,
					TENOR,
					AdjustmentAmount,
					DateUpdated,
					DateAdded,
					BOOK_DATE,
					PCGenerationDate
				FROM PCDisbursement WITH(NOLOCK)
				WHERE IsDeleted = 0
			) P
			WHERE PCD_Key IS NOT NULL
			GROUP BY PCD_Key
		) PCD_ADJ ON PCD_ADJ.PCD_Key = PCM.PCDMID 
				  OR PCD_ADJ.PCD_Key = PCM.AdditionalFilter 
				  OR PCD_ADJ.PCD_Key = PCM.ExternalID
		LEFT JOIN
		(
			SELECT
				OAPKey,
				SUM(AdjAmt)																	AS AdjustmentAmount,
				MAX(AdjDate)																AS AdjustedDate
			FROM (
				SELECT 
					COALESCE(NULLIF(OAPNumber, ''), NULLIF(LoanReferenceNumber, ''), ExternalID) AS OAPKey,
					COALESCE(NULLIF(AdjustmentAmount, 0), FCY_AMOUNT, 0) AS AdjAmt,
					COALESCE(TRN_DT, VALUE_DT, OAPDate, DateUpdated, DateAdded) AS AdjDate
				FROM LoanAdjustmentInvoiceChild WITH(NOLOCK)
				WHERE IsDeleted = 0
			) L
			WHERE OAPKey IS NOT NULL
			GROUP BY OAPKey
		) LAIC ON LAIC.OAPKey = PCM.AdditionalFilter 
			   OR LAIC.OAPKey = PCM.PCDMID 
			   OR LAIC.OAPKey = PCM.ExternalID
		LEFT JOIN (
			SELECT 
				LoanKey,
				MAX(MATURITY_DATE) AS MATURITY_DATE,
				MAX(LoanExpiry) AS LoanExpiry,
				MAX(Tenor) AS Tenor
			FROM (
				SELECT 
					COALESCE(NULLIF(LoanNo, ''), NULLIF(AdditionalFilter, ''), NULLIF(ExternalID, ''), ACCOUNT_NUMBER) AS LoanKey,
					MATURITY_DATE,
					LoanExpiry,
					Tenor
				FROM LoanCreation WITH(NOLOCK)
				WHERE IsDeleted = 0
			) LC_INNER
			WHERE LoanKey IS NOT NULL
			GROUP BY LoanKey
		) LC ON LC.LoanKey = PCM.AdditionalFilter 
			 OR LC.LoanKey = PCM.PCDMID 
			 OR LC.LoanKey = PCM.ExternalID
		LEFT JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = PCM.MasterDocID AND MD.IsDeleted = 0
		LEFT JOIN (
			SELECT 
				GroupSysID,
				MAX(ExpiryDate) AS MaxLCExpiryDate,
				MAX(ShipmentDate) AS MaxLCShipmentDate
			FROM MasterDoc WITH(NOLOCK)
			WHERE IsDeleted = 0 AND IsCancelled = 0
			GROUP BY GroupSysID
		) MD_GRP ON MD_GRP.GroupSysID = PCM.GroupRefID
		LEFT JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = PCM.GroupRefID
		LEFT JOIN SystemManager.dbo.CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = PCM.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(GLC.BankBranchID, PCM.BranchID)
	WHERE PCM.IsDeleted = 0
		AND PCM.IsCheck = 1
		AND CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) AS DATE) >= @FromDate
		AND CAST(ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate) AS DATE) <= @ToDate
	ORDER BY BPB.BranchName, CPM.CustomerName, ISNULL(PCM.PCDisburseDate, PCM.PCCreationDate), PCM.AdditionalFilter;
END
GO
