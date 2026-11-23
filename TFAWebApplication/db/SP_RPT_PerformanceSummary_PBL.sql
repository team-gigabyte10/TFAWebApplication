USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[SP_RPT_PerformanceSummary_PBL]    Script Date: 11/23/2026 12:46:09 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[SP_RPT_PerformanceSummary_PBL]
@FromDate DATETIME,
@ToDate DATETIME
AS			
--    SP_RPT_PerformanceSummary_PBL '2023-10-04' , '2023-10-06'
BEGIN

DECLARE @USDRate NUMERIC(18,4)
SELECT @USDRate = ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) 
WHERE RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK)) AND CurrencyCode = 'USD'

IF ISNULL(@USDRate, 0) = 0
    SET @USDRate = 1

---- 1. Acceptance Information 
SELECT 
    x.GroupSysID,
    AcceptanceBillAmountFCYUSD = SUM(x.AcceptanceBillAmountFCYUSD),
    OutstandingAcceptanceAmountFCY = SUM(x.OutstandingAcceptanceAmountFCY),
    OverdueAmount = SUM(x.OverdueAmount)
INTO #AcceptenceInfoSubReport 
FROM (
    SELECT
        B.GroupSysID,
        AcceptanceBillAmountFCYUSD = CASE 
            WHEN ISNULL(F.Currency, 'USD') = 'USD' THEN ISNULL(F.BillAmount, 0)
            ELSE (ISNULL(F.BillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
        END,
        OutstandingAcceptanceAmountFCY = CASE 
            WHEN (ISNULL(F.BillAmount, 0) - ISNULL(Payments.PaidAmountFCY, 0)) > 0 THEN
                CASE 
                    WHEN ISNULL(F.Currency, 'USD') = 'USD' THEN (ISNULL(F.BillAmount, 0) - ISNULL(Payments.PaidAmountFCY, 0))
                    ELSE ((ISNULL(F.BillAmount, 0) - ISNULL(Payments.PaidAmountFCY, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
                END
            ELSE 0 
        END,
        OverdueAmount = CASE 			
            WHEN CAST(F.MATURITY_DATE AS DATE) < CAST(GETDATE() AS DATE) AND (ISNULL(F.BillAmount, 0) - ISNULL(Payments.PaidAmountFCY, 0)) > 0 THEN 
                CASE 
                    WHEN ISNULL(F.Currency, 'USD') = 'USD' THEN (ISNULL(F.BillAmount, 0) - ISNULL(Payments.PaidAmountFCY, 0))
                    ELSE ((ISNULL(F.BillAmount, 0) - ISNULL(Payments.PaidAmountFCY, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
                END
            ELSE 0 
        END
    FROM ForeignDocumentAcceptanceMaster F WITH(NOLOCK)
    INNER JOIN BBLCMaster B WITH(NOLOCK) ON B.BBLCID = F.BBLCID AND B.IsDeleted = 0 AND B.IsCancelled = 0
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = F.Currency AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
    LEFT JOIN (
        SELECT 
            FDAID,
            SUM(ISNULL(PaymentAmount, 0)) AS PaidAmountFCY
        FROM ForeignDocumentPaymentMaster WITH(NOLOCK)
        WHERE IsDeleted = 0
        GROUP BY FDAID
    ) Payments ON Payments.FDAID = F.FDAID
    WHERE F.IsDeleted = 0 AND F.IsCancelled = 0
) x
GROUP BY x.GroupSysID

---- 2. Export LC Details
SELECT 
    GroupSysID,
    TotalAmountFOBINSFREFCUSD = SUM(((CASE WHEN ReplacedLCSC = 1 THEN NULL ELSE FobValue + Insurance + Freight + ForeignCommision END) * ConvertFactor) / @USDRate),
    ReplacedbyLCUSD = SUM((ISNULL(ReplacedbyLC, 0) * ConvertFactor) / @USDRate),
    FobValueUSD = SUM((ISNULL(CASE WHEN ReplacedLCSC = 1 THEN NULL ELSE FobValue END, 0) * ConvertFactor) / @USDRate)
INTO #ExportLCDetails
FROM (
    SELECT
        MD.ReplacedLCSC,
        MD.LCNo AS ExportLCSCNo,
        MD.Incoterm,
        MD.Currency,
        FobValue = CASE
            WHEN IsLienToGroup = 1 THEN
                CASE
                    WHEN ReplacedLCSC = 1 THEN 
                        CASE
                            WHEN Commission.FOBChargesTypeID = 'Percent'
                            THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - (MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100)
                            ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
                        END
                    ELSE                              
                        CASE WHEN IsSC = 0 THEN
                            CASE
                                WHEN Commission.FOBChargesTypeID = 'Percent'
                                THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100
                                ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0)
                            END
                        ELSE
                            CASE
                                WHEN ISNULL(MD.ReplacedAmount, 0) > MD.LCAmount THEN 0
                                ELSE
                                    CASE
                                        WHEN Commission.FOBChargesTypeID = 'Percent'
                                        THEN MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 - ISNULL(MD.ReplacedAmount, 0)
                                        ELSE MD.LCAmount - ISNULL(Freight.FOBChargesValue, 0) - ISNULL(Commission.FOBChargesValue, 0) - ISNULL(Insurance.FOBChargesValue, 0) - ISNULL(MD.ReplacedAmount, 0)
                                    END
                            END
                        END
                END
            ELSE 0
        END,
        MD.AmountToGroup,
        CASE WHEN MD.ReplacedLCSC = 1 AND MD.LCAmount > 0 THEN MD.TolerancePercent ELSE '' END AS ReplacingTolerancePercent,
        ISNULL(CLR.ConvertFactor, 1) AS ConvertFactor,
        MD.LCAmount,
        ISNULL(Insurance.FOBChargesValue, 0) AS Insurance,
        ISNULL(Freight.FOBChargesValue, 0) AS Freight,
        CASE WHEN Commission.FOBChargesTypeID = 'Percent'
            THEN MD.LCAmount * ISNULL(Commission.FOBChargesValue, 0) / 100 
            ELSE ISNULL(Commission.FOBChargesValue, 0) 
        END AS ForeignCommision,
        MD.TolerancePercent AS Tolerance,
        ReplacedbyLC = COALESCE(
            NULLIF(MD.ReplacedAmount, 0),
            NULLIF(CR_SC.TotalReplacedAmt, 0),
            NULLIF(CR_LC.TotalReplacedAmt, 0),
            CASE WHEN MD.ReplacedLCSC = 1 THEN MD.LCAmount ELSE 0 END,
            0
        ),
        MD.CustomerID,
        GLC.GroupSysID,
        GLC.GroupRefNo,
        CPM.CustomerName
    FROM MasterDoc MD WITH(NOLOCK)
    INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD.GroupSysID AND GLC.IsDeleted = 0
    LEFT JOIN (
        SELECT CRBLCD.SCID, SUM(CRBLCD.ReplacementAmt) AS TotalReplacedAmt
        FROM ContractReplacementByLCDetails CRBLCD WITH(NOLOCK)
        INNER JOIN ContractReplacementByLC CRBLC WITH(NOLOCK) ON CRBLC.CRBLCID = CRBLCD.CRBLCID AND CRBLC.IsDeleted = 0
        WHERE CRBLCD.IsDeleted = 0
        GROUP BY CRBLCD.SCID
    ) CR_SC ON CR_SC.SCID = MD.MasterDocID
    LEFT JOIN (
        SELECT CRBLCD.MasterLCID, SUM(CRBLCD.ReplacementAmt) AS TotalReplacedAmt
        FROM ContractReplacementByLCDetails CRBLCD WITH(NOLOCK)
        INNER JOIN ContractReplacementByLC CRBLC WITH(NOLOCK) ON CRBLC.CRBLCID = CRBLCD.CRBLCID AND CRBLC.IsDeleted = 0
        WHERE CRBLCD.IsDeleted = 0
        GROUP BY CRBLCD.MasterLCID
    ) CR_LC ON CR_LC.MasterLCID = MD.MasterDocID
    LEFT JOIN ChargesAgainstLCValueFOBCalculation Commission WITH(NOLOCK) 
        ON Commission.MasterDocID = MD.MasterDocID AND Commission.TemplateID = 'ForeignCommission'
    LEFT JOIN ChargesAgainstLCValueFOBCalculation Freight WITH(NOLOCK) 
        ON Freight.MasterDocID = MD.MasterDocID AND Freight.TemplateID = 'Freight'
    LEFT JOIN ChargesAgainstLCValueFOBCalculation Insurance WITH(NOLOCK) 
        ON Insurance.MasterDocID = MD.MasterDocID AND Insurance.TemplateID = 'Insurance'
    LEFT JOIN SystemManager..SystemSettings SSG WITH(NOLOCK) ON '' = ''
    LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = MD.CustomerID
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = MD.Currency AND CLR.RateFor = SSG.ConvertRateForExportLCAmount
    WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0
) x 
GROUP BY x.GroupSysID

---- 3. ExportBill FDBC Information / ExportMade
SELECT 
    x.GroupSysID,
    ExportMade = SUM(x.BillAmountUSD),
    RealizedAmount = SUM(x.RealizedAmountFCYUSD),
    UnrealizedAmount = SUM(x.UnrealizedAmountFCYUSD)
INTO #ExportBillFDBCInformation 
FROM (
    -- Foreign Bills
    SELECT 
        MD.GroupSysID,
        (ISNULL(EBIM.ExportBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS BillAmountUSD,
        (ISNULL(Realized.RealizedAmt, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS RealizedAmountFCYUSD,
        ((ISNULL(EBIM.ExportBillAmount, 0) - ISNULL(Realized.RealizedAmt, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS UnrealizedAmountFCYUSD
    FROM ExportBillInitiationMaster EBIM WITH(NOLOCK)
    INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = EBIM.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = EBIM.CURRENCY_CODE AND CLR.RateFor = (SELECT TOP 1 ConvertRateForExportRealizedAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
    LEFT JOIN (
        SELECT 
            EBIID,
            SUM(ISNULL(ProceedsRecvd, 0)) AS RealizedAmt
        FROM (
            SELECT EBIID, C_Amount AS ProceedsRecvd FROM PRSCreationMaster WITH(NOLOCK) WHERE IsDeleted = 0
            UNION ALL
            SELECT BillRefNo AS EBIID, ProceedsRecvd FROM PRSCreationDistributionDetails WITH(NOLOCK) WHERE IsDeleted = 0 AND BillRefNo IS NOT NULL
        ) PR
        GROUP BY EBIID
    ) Realized ON Realized.EBIID = EBIM.EBIID
    WHERE EBIM.IsDeleted = 0 AND ISNULL(EBIM.IsCancelled, 0) = 0 AND EBIM.ExportBillNo IS NOT NULL

    UNION ALL

    -- Local Bills
    SELECT 
        MD.GroupSysID,
        (ISNULL(LEBIM.ExportLocalBillAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS BillAmountUSD,
        (ISNULL(Realized.RealizedAmt, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS RealizedAmountFCYUSD,
        ((ISNULL(LEBIM.ExportLocalBillAmount, 0) - ISNULL(Realized.RealizedAmt, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate AS UnrealizedAmountFCYUSD
    FROM LocalExportBillInitiationMaster LEBIM WITH(NOLOCK)
    INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = LEBIM.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = LEBIM.CURRENCY_CODE AND CLR.RateFor = (SELECT TOP 1 ConvertRateForExportRealizedAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
    LEFT JOIN (
        SELECT 
            EBIID,
            SUM(ISNULL(ProceedsRecvd, 0)) AS RealizedAmt
        FROM (
            SELECT EBIID, C_Amount AS ProceedsRecvd FROM PRSCreationMaster WITH(NOLOCK) WHERE IsDeleted = 0
            UNION ALL
            SELECT BillRefNo AS EBIID, ProceedsRecvd FROM PRSCreationDistributionDetails WITH(NOLOCK) WHERE IsDeleted = 0 AND BillRefNo IS NOT NULL
        ) PR
        GROUP BY EBIID
    ) Realized ON Realized.EBIID = LEBIM.EBIID
    WHERE LEBIM.IsDeleted = 0 AND ISNULL(LEBIM.IsCancelled, 0) = 0 AND LEBIM.ExportLocalBillNo IS NOT NULL
) x
GROUP BY x.GroupSysID

---- 4. Margin Information
SELECT 
    x.GroupSysID,
    MarginCredit = SUM(x.CalCreditAmount),
    MarginDebit = SUM(x.CalDebitAmount),
    MarginBalance = SUM(x.CalCreditAmount) - SUM(x.CalDebitAmount) 
INTO #MarginInformation 
FROM (
    -- From MarginEncashmentChild and Master
    SELECT 
        GLC.GroupSysID,
        CalCreditAmount = CASE WHEN D.DebitCredit = 'Credit' THEN (ISNULL(D.NetMarginPosition, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate ELSE 0 END,
        CalDebitAmount = CASE WHEN D.DebitCredit = 'Debit' THEN (ISNULL(D.NetMarginPosition, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate ELSE 0 END
    FROM MarginEncashmentChild D WITH(NOLOCK)
    INNER JOIN MarginEncashmentMaster MD WITH(NOLOCK) ON MD.MAEMID = D.MAEMID AND MD.IsDeleted = 0
    INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = D.GroupSysID AND GLC.IsDeleted = 0
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = GLC.CurrencyCode AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
    WHERE D.IsDeleted = 0

    UNION ALL

    -- From PRSCreationDistributionDetails (Margin credited during PRS distribution)
    SELECT 
        GLC.GroupSysID,
        CalCreditAmount = CASE 
            WHEN D.DRCR_IND = 'C' THEN 
                CASE WHEN D.DistributedCCY = 'USD' THEN ISNULL(D.DistributedValue, 0) 
                     ELSE (ISNULL(D.DistributedValue, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate END
            ELSE 0 
        END,
        CalDebitAmount = CASE 
            WHEN D.DRCR_IND = 'D' THEN 
                CASE WHEN D.DistributedCCY = 'USD' THEN ISNULL(D.DistributedValue, 0) 
                     ELSE (ISNULL(D.DistributedValue, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate END
            ELSE 0 
        END
    FROM PRSCreationDistributionDetails D WITH(NOLOCK)
    INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = D.MasterDocID AND MD.IsDeleted = 0
    INNER JOIN GroupLC GLC WITH(NOLOCK) ON GLC.GroupSysID = MD.GroupSysID AND GLC.IsDeleted = 0
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = D.DistributedCCY AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
    WHERE D.IsDeleted = 0 
      AND (
          D.ProductCode LIKE '%MARGIN%' 
          OR D.AC_NO IN (
              SELECT CA.AccountCode FROM SystemManager..CustomerProfileAccounts CA WITH(NOLOCK)
              INNER JOIN SystemManager..EntityFixedVariables EN WITH(NOLOCK) ON EN.EntityID = CA.AccountTypeID
              WHERE CA.IsDeleted = 0 AND (EN.ExternalID = 'MARGIN' OR EN.DisplayCode LIKE '%Margin%')
          )
      )
) x
GROUP BY x.GroupSysID

---- 5. Force Loan
SELECT
    G.GroupSysID,
    ForceLoanAmountBDT = SUM((ISNULL(L.LoanAmount, ISNULL(L.BillAmount, 0)) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate),
    OutstandingAmountBDT = SUM(
        CASE 
            WHEN ISNULL(L.Currency, 'BDT') = 'USD' THEN COALESCE(NULLIF(L.TOT_OS, 0), NULLIF(L.PRINCIPAL_OS, 0), L.LoanAmount, 0)
            ELSE (COALESCE(NULLIF(L.TOT_OS, 0), NULLIF(L.PRINCIPAL_OS, 0), (L.LoanAmount - ISNULL(LPay.LCY_AMOUNT, 0)), 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate
        END
    )
INTO #ForceLoan
FROM LoanCreation L WITH(NOLOCK)
LEFT JOIN BBLCMaster B WITH(NOLOCK) ON B.BBLCID = L.BBLCID AND B.IsDeleted = 0
LEFT JOIN MasterDoc MD_L WITH(NOLOCK) ON MD_L.MasterDocID = L.MasterDocID AND MD_L.IsDeleted = 0
INNER JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = COALESCE(NULLIF(B.GroupSysID, ''), NULLIF(MD_L.GroupSysID, '')) AND G.IsDeleted = 0
LEFT JOIN (
    SELECT RELATED_ACCOUNT, SUM(LCY_AMOUNT) AS LCY_AMOUNT, SUM(FCY_AMOUNT) AS FCY_AMOUNT
    FROM LoanPayment WITH(NOLOCK) 
    WHERE IsDeleted = 0 AND DRCR_IND = 'C' 
    GROUP BY RELATED_ACCOUNT
) LPay ON LPay.RELATED_ACCOUNT = L.ACCOUNT_NUMBER 
LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
    ON CLR.CurrencyCode = L.Currency AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
WHERE L.IsDeleted = 0 
  AND (
      L.BBLCID IS NOT NULL 
      OR L.Product LIKE '%Forced%' 
      OR L.LoanType LIKE '%Forced%' 
      OR L.ExternalID LIKE '%FL%' 
      OR L.ExternalID LIKE '%PAD%' 
      OR L.LoanAgainst IN ('BBLC', 'Import', 'Bill')
  )
GROUP BY G.GroupSysID

---- 6. PC TimeLoan Information
SELECT
    x.GroupSysID,
    PCTimeLoanAmountFCYUSD = SUM(x.PCTimeLoanAmountFCYUSD),
    OutstandingAmountFCYUSD = SUM(x.OutstandingAmountFCYUSD),
    OverdueAmountUSD = SUM(x.OverdueAmountUSD)
INTO #PCTimeLoanInformation
FROM (
    SELECT
        G.GroupSysID,
        PCTimeLoanAmountFCYUSD = (ISNULL(PC.PCAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate,
        OutstandingAmountFCYUSD = (COALESCE(NULLIF(PC.TOT_OS, 0), NULLIF(PC.PRINCIPAL_OS, 0), PC.PCAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate,
        OverdueAmountUSD = CASE 
            WHEN PC.MATURITY_DATE < GETDATE() 
            THEN (COALESCE(NULLIF(PC.TOT_OS, 0), NULLIF(PC.PRINCIPAL_OS, 0), PC.PCAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate 
            ELSE 0 
        END
    FROM PCDisbursementMaster PC WITH(NOLOCK)
    LEFT JOIN MasterDoc MD_PC WITH(NOLOCK) ON MD_PC.MasterDocID = PC.MasterDocID AND MD_PC.IsDeleted = 0
    INNER JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = COALESCE(NULLIF(PC.GroupRefID, ''), NULLIF(MD_PC.GroupSysID, '')) AND G.IsDeleted = 0
    LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
        ON CLR.CurrencyCode = PC.Currency AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
    WHERE PC.IsDeleted = 0
) x
GROUP BY x.GroupSysID

---- 7. FDBP Disbursed & Outstanding
SELECT 
    GroupSysID = COALESCE(NULLIF(fd.GroupSysID, ''), NULLIF(MD.GroupSysID, ''), NULLIF(EBIM_MD.GroupSysID, ''), NULLIF(LEBIM_MD.GroupSysID, '')),
    DisbursedAmount = SUM((ISNULL(fd.DisbursedAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate)
INTO #FDBCDisburded 
FROM PurchaseDiscountForeignDocumentMaster fd WITH(NOLOCK)
LEFT JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = fd.MasterDocID AND MD.IsDeleted = 0
LEFT JOIN ExportBillInitiationMaster EBIM WITH(NOLOCK) ON EBIM.EBIID = fd.EBIID AND EBIM.IsDeleted = 0
LEFT JOIN MasterDoc EBIM_MD WITH(NOLOCK) ON EBIM_MD.MasterDocID = EBIM.MasterDocID AND EBIM_MD.IsDeleted = 0
LEFT JOIN LocalExportBillInitiationMaster LEBIM WITH(NOLOCK) ON LEBIM.EBIID = fd.EBIID AND LEBIM.IsDeleted = 0
LEFT JOIN MasterDoc LEBIM_MD WITH(NOLOCK) ON LEBIM_MD.MasterDocID = LEBIM.MasterDocID AND LEBIM_MD.IsDeleted = 0
LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
    ON CLR.CurrencyCode = fd.CURRENCY AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
WHERE fd.IsCancelled = 0 AND fd.IsDeleted = 0
GROUP BY COALESCE(NULLIF(fd.GroupSysID, ''), NULLIF(MD.GroupSysID, ''), NULLIF(EBIM_MD.GroupSysID, ''), NULLIF(LEBIM_MD.GroupSysID, ''))
HAVING COALESCE(NULLIF(fd.GroupSysID, ''), NULLIF(MD.GroupSysID, ''), NULLIF(EBIM_MD.GroupSysID, ''), NULLIF(LEBIM_MD.GroupSysID, '')) IS NOT NULL

SELECT 
    GroupSysID = COALESCE(NULLIF(fd.GroupSysID, ''), NULLIF(MD.GroupSysID, ''), NULLIF(EBIM_MD.GroupSysID, ''), NULLIF(LEBIM_MD.GroupSysID, '')),
    OutstandingAmount = SUM((COALESCE(NULLIF(fd.TOT_OS, 0), NULLIF(fd.PRINCIPAL_OS, 0), fd.DisbursedAmount, 0) * ISNULL(CLR.ConvertFactor, 1)) / @USDRate)
INTO #FDBCOutstanding 
FROM PurchaseDiscountForeignDocumentMaster fd WITH(NOLOCK)
LEFT JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = fd.MasterDocID AND MD.IsDeleted = 0
LEFT JOIN ExportBillInitiationMaster EBIM WITH(NOLOCK) ON EBIM.EBIID = fd.EBIID AND EBIM.IsDeleted = 0
LEFT JOIN MasterDoc EBIM_MD WITH(NOLOCK) ON EBIM_MD.MasterDocID = EBIM.MasterDocID AND EBIM_MD.IsDeleted = 0
LEFT JOIN LocalExportBillInitiationMaster LEBIM WITH(NOLOCK) ON LEBIM.EBIID = fd.EBIID AND LEBIM.IsDeleted = 0
LEFT JOIN MasterDoc LEBIM_MD WITH(NOLOCK) ON LEBIM_MD.MasterDocID = LEBIM.MasterDocID AND LEBIM_MD.IsDeleted = 0
LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
    ON CLR.CurrencyCode = fd.CURRENCY AND CLR.RateFor = (SELECT TOP 1 ConvertRateForGroupAmount FROM SystemManager..SystemSettings WITH(NOLOCK))
WHERE fd.IsCancelled = 0 AND fd.IsDeleted = 0
GROUP BY COALESCE(NULLIF(fd.GroupSysID, ''), NULLIF(MD.GroupSysID, ''), NULLIF(EBIM_MD.GroupSysID, ''), NULLIF(LEBIM_MD.GroupSysID, ''))
HAVING COALESCE(NULLIF(fd.GroupSysID, ''), NULLIF(MD.GroupSysID, ''), NULLIF(EBIM_MD.GroupSysID, ''), NULLIF(LEBIM_MD.GroupSysID, '')) IS NOT NULL

---- 8. Main Result Set
SELECT
	COALESCE(NULLIF(BPB.BranchName, ''), NULLIF(ADbpb.BranchName, ''), '') AS BranchName,
	GLC.GroupRefNo AS GroupRefNo,
	GLC.DateAdded AS GroupCreationDate,
	CPM.CustomerName AS ClientName,
	COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '') AS ADBranch,
	CASE 
		WHEN NonADbpb.BranchName IS NOT NULL 
			 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
		THEN NonADbpb.BranchName
		WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
			 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
		THEN BPB.BranchName
		ELSE ''
	END AS NonADBranch,
	MD.ShipmentDate AS LastShipmentDate,
	MD.ExpiryDate AS LastExpiryDate,
	GLC.CurrencyCode AS GroupCur,
	GLC.GroupAmount AS TotalGroupValue,
	ISNULL(ToatlBTB.BBLCOpened, 0) AS BacktoBackLC,
	AcceptanceValue = ISNULL(AcceptenceInfoSubReport.AcceptanceBillAmountFCYUSD, 0),
	UnpaidAcceptance = ISNULL(AcceptenceInfoSubReport.OutstandingAcceptanceAmountFCY, 0),
	ReplacedLCValue = ISNULL(ExportLCDetails.ReplacedbyLCUSD, 0),
 	LCnotyetReplaced = ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExportLCDetails.ReplacedbyLCUSD, 0),
	ExportMade = ISNULL(ExportBillFDBCInformation.ExportMade, 0),		
	ExportNotMade = ISNULL(ExportLCDetails.TotalAmountFOBINSFREFCUSD, 0) - ISNULL(ExportBillFDBCInformation.ExportMade, 0),
	RealizedAmount = ISNULL(ExportBillFDBCInformation.RealizedAmount, 0),
	MarginRetained = ISNULL(MarginInformation.MarginCredit, 0),
	MarginUtilized = ISNULL(MarginInformation.MarginDebit, 0),
	MarginUnutilized = ISNULL(MarginInformation.MarginBalance, 0),
	ForcedLoan = ISNULL(ForceLoan.ForceLoanAmountBDT, 0),
	OutstandingForceLoan = ISNULL(ForceLoan.OutstandingAmountBDT, 0),
	PCTimeLoanDisbursed = ISNULL(PCTimeLoanInformation.PCTimeLoanAmountFCYUSD, 0),
	OutstandingPCTimeLoan = ISNULL(PCTimeLoanInformation.OutstandingAmountFCYUSD, 0),
	FDBPDisbursed = ISNULL(FDBCDisburded.DisbursedAmount, 0),
	FDBPOutstanding = ISNULL(FDBCOutstanding.OutstandingAmount, 0),
	MD.ApplicantName AS Buyer,
	GLC.CustomerID AS CustomerID,
	COALESCE(NULLIF(ADbpb.BranchID, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END, '') AS ADBranchID,
	CASE 
		WHEN NonADbpb.BranchName IS NOT NULL 
			 AND RTRIM(LTRIM(NonADbpb.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchName ELSE '' END, '')))
		THEN ISNULL(NonADbpb.BranchID, '')
		WHEN BPB.IsADCode = 0 AND BPB.BranchName IS NOT NULL
			 AND RTRIM(LTRIM(BPB.BranchName)) != RTRIM(LTRIM(COALESCE(NULLIF(ADbpb.BranchName, ''), '')))
		THEN ISNULL(BPB.BranchID, '')
		ELSE ''
	END AS NonADBranchID,
	GLC.CurrencyCode AS Currency,
	MD.Applicant AS Applicant	
FROM (SELECT * FROM GroupLC WITH(NOLOCK) WHERE IsDeleted = 0) GLC	
LEFT JOIN #AcceptenceInfoSubReport AcceptenceInfoSubReport ON AcceptenceInfoSubReport.GroupSysID = GLC.GroupSysID
LEFT JOIN #ExportLCDetails ExportLCDetails ON ExportLCDetails.GroupSysID = GLC.GroupSysID
LEFT JOIN #ExportBillFDBCInformation ExportBillFDBCInformation ON ExportBillFDBCInformation.GroupSysID = GLC.GroupSysID
LEFT JOIN #MarginInformation MarginInformation ON MarginInformation.GroupSysID = GLC.GroupSysID
LEFT JOIN #ForceLoan ForceLoan ON ForceLoan.GroupSysID = GLC.GroupSysID
LEFT JOIN #PCTimeLoanInformation PCTimeLoanInformation ON PCTimeLoanInformation.GroupSysID = GLC.GroupSysID
LEFT JOIN #FDBCDisburded FDBCDisburded ON FDBCDisburded.GroupSysID = GLC.GroupSysID
LEFT JOIN #FDBCOutstanding FDBCOutstanding ON FDBCOutstanding.GroupSysID = GLC.GroupSysID
LEFT JOIN (
    SELECT 
        GroupSysID,
        MAX(ShipmentDate) AS ShipmentDate,
        MAX(ExpiryDate) AS ExpiryDate,
        MAX(Applicant) AS Applicant,
        STUFF((
            SELECT ', ' + CombinedE.Name 
            FROM (
                SELECT APP.Name, GroupSysID 
                FROM MasterDoc MD WITH(NOLOCK)
                LEFT JOIN SystemManager..Contacts APP WITH(NOLOCK) ON APP.Code = MD.Applicant
                WHERE MD.IsDeleted = 0 AND MD.IsCancelled = 0
            ) CombinedE 
            WHERE CombinedE.GroupSysID = E.GroupSysID
            FOR XML PATH('')
        ), 1, 1, '') AS ApplicantName
    FROM MasterDoc E WITH(NOLOCK) 
    WHERE IsDeleted = 0 AND IsCancelled = 0 
    GROUP BY GroupSysID
) MD ON MD.GroupSysID = GLC.GroupSysID

LEFT JOIN (
    SELECT 
        ISNULL(ISNULL(Util.AmtUtilizedSQ, 0) / GRPCLR.ConvertFactor, 0) AS BBLCOpened,
        GLC.GroupSysID
    FROM GroupLC GLC WITH(NOLOCK)
    LEFT JOIN (
        SELECT ISNULL(SUM(BBLCAmount * CLR.ConvertFactor), 0) AS AmtUtilizedSQ, GroupSysID
        FROM BBLCMaster BBLCM WITH(NOLOCK)
        LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) 
            ON CLR.CurrencyCode = BBLCM.Currency AND CLR.RateFor = 'BC SELLING'
        WHERE BBLCM.IsDeleted = 0 AND BBLCM.IsCancelled = 0 
        GROUP BY GroupSysID
    ) Util ON GLC.GroupSysID = Util.GroupSysID
    LEFT JOIN SystemManager..CurrencyLatestRate GRPCLR WITH(NOLOCK) 
        ON GRPCLR.CurrencyCode = GLC.CurrencyCode AND GRPCLR.RateFor = 'BC SELLING'
    GROUP BY GLC.GroupSysID, GRPCLR.ConvertFactor, Util.AmtUtilizedSQ
) ToatlBTB ON ToatlBTB.GroupSysID = GLC.GroupSysID

LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = GLC.CustomerID
LEFT JOIN SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON 
    BPB.BranchID = GLC.BankBranchID
    OR BPB.BranchID = REPLACE(GLC.BankBranchID, 'BPB/22/', 'OBPB/25/')
    OR BPB.BranchID = REPLACE(GLC.BankBranchID, 'OBPB/25/', 'BPB/22/')
LEFT JOIN SystemManager..BankProfileBranch ADbpb WITH(NOLOCK) ON 
    ADbpb.IsADCode = 1 AND (
        ADbpb.BranchID = COALESCE(NULLIF(GLC.ADBranchID, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END)
        OR ADbpb.BranchID = REPLACE(COALESCE(NULLIF(GLC.ADBranchID, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END), 'BPB/22/', 'OBPB/25/')
        OR ADbpb.BranchID = REPLACE(COALESCE(NULLIF(GLC.ADBranchID, ''), CASE WHEN BPB.IsADCode = 1 THEN BPB.BranchID ELSE BPB.ADBranchID END), 'OBPB/25/', 'BPB/22/')
    )
LEFT JOIN SystemManager..BankProfileBranch NonADbpb WITH(NOLOCK) ON 
    (
        NonADbpb.BranchID = GLC.BankBranchID
        OR NonADbpb.BranchID = REPLACE(GLC.BankBranchID, 'BPB/22/', 'OBPB/25/')
        OR NonADbpb.BranchID = REPLACE(GLC.BankBranchID, 'OBPB/25/', 'BPB/22/')
    )
    AND NonADbpb.IsADCode = 0
WHERE CONVERT(DATE, GLC.DateAdded) BETWEEN @FromDate AND @ToDate
ORDER BY GLC.GroupRefNo ASC
 
END
