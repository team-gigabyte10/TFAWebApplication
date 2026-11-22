USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[BTBAcceptedLiabilityCoveragePBL] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[BTBAcceptedLiabilityCoveragePBL]
    @FromDate DATE,
    @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Exec BTBAcceptedLiabilityCoveragePBL '2024-01-01', '2025-10-01'
    DECLARE @USDRate NUMERIC(18,4)
    SELECT @USDRate = ConvertFactor 
    FROM [SystemManager]..CurrencyLatestRate WITH(NOLOCK) 
    WHERE CurrencyCode = 'USD' AND RateFor = 'BC SELLING'
    IF ISNULL(@USDRate, 0) = 0 SET @USDRate = 120.00;

    -- 1. All relevant GroupLC records that have activity in range or were active
    WITH GroupBase AS (
        SELECT DISTINCT
            g.GroupSysID,
            g.GroupRefNo,
            g.CustomerID,
            g.CurrencyCode,
            ISNULL(g.GroupAmount, 0) AS GroupAmount,
            CONVERT(DATE, g.DateAdded) AS JobDate
        FROM GroupLC g WITH(NOLOCK)
        WHERE g.IsDeleted = 0
          AND (
              CONVERT(DATE, g.DateAdded) BETWEEN @FromDate AND @ToDate
              OR EXISTS (
                  SELECT 1 FROM BBLCMaster bb WITH(NOLOCK) 
                  WHERE bb.GroupSysID = g.GroupSysID AND bb.IsDeleted = 0 AND bb.IsCancelled = 0
                    AND CONVERT(DATE, bb.IssueDate) BETWEEN @FromDate AND @ToDate
              )
              OR EXISTS (
                  SELECT 1 FROM BBLCRequestMaster b WITH(NOLOCK)
                  WHERE b.GroupSysID = g.GroupSysID AND b.IsDeleted = 0 AND b.IsCancelled = 0
                    AND CONVERT(DATE, b.RequestDate) BETWEEN @FromDate AND @ToDate
              )
          )
    ),
    -- 2. BTB Accepted Liability per Group
    BTBAccepted AS (
        SELECT 
            bb.GroupSysID,
            SUM(
                CASE 
                    WHEN ISNULL(fd.Currency, 'USD') = 'USD' THEN ISNULL(fd.BillAmount, 0)
                    ELSE (ISNULL(fd.BillAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                END
            ) AS BTBAcceptedliability
        FROM ForeignDocumentAcceptanceMaster fd WITH(NOLOCK)
        INNER JOIN BBLCMaster bb WITH(NOLOCK) ON bb.BBLCID = fd.BBLCID
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = fd.Currency AND clr.RateFor = 'BC SELLING'
        WHERE fd.IsDeleted = 0 
          AND fd.IsCancelled = 0
          AND bb.IsDeleted = 0
          AND bb.IsCancelled = 0
        GROUP BY bb.GroupSysID
    ),
    -- 3. TT and CAD Issued per Group
    TTCAD AS (
        SELECT 
            b.GroupSysID,
            SUM(CASE WHEN b.ReqPaymentMethod LIKE '%TT%' THEN 
                    CASE WHEN ISNULL(b.Currency, 'USD') = 'USD' THEN ISNULL(b.ProposedAmount, 0)
                         ELSE (ISNULL(b.ProposedAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate END
                ELSE 0 END) AS TTIssued,
            SUM(CASE WHEN b.ReqPaymentMethod LIKE '%CAD%' THEN 
                    CASE WHEN ISNULL(b.Currency, 'USD') = 'USD' THEN ISNULL(b.ProposedAmount, 0)
                         ELSE (ISNULL(b.ProposedAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate END
                ELSE 0 END) AS CADIssued
        FROM BBLCRequestMaster b WITH(NOLOCK)
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = b.Currency AND clr.RateFor = 'BC SELLING'
        WHERE b.IsDeleted = 0 AND b.IsCancelled = 0
        GROUP BY b.GroupSysID
    ),
    -- 4. BTB Bills Paid Already per Group
    BTBPaid AS (
        SELECT 
            bb.GroupSysID,
            SUM(
                CASE 
                    WHEN ISNULL(pm.Currency, 'USD') = 'USD' THEN ISNULL(pm.PaymentAmount, 0)
                    ELSE (ISNULL(pm.PaymentAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                END
            ) AS BTBBillsPaidAlready
        FROM ForeignDocumentPaymentMaster pm WITH(NOLOCK)
        INNER JOIN ForeignDocumentAcceptanceMaster fd WITH(NOLOCK) ON fd.FDAID = pm.FDAID
        INNER JOIN BBLCMaster bb WITH(NOLOCK) ON bb.BBLCID = fd.BBLCID
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = pm.Currency AND clr.RateFor = 'BC SELLING'
        WHERE pm.IsDeleted = 0 AND fd.IsDeleted = 0 AND fd.IsCancelled = 0
        GROUP BY bb.GroupSysID
    ),
    -- 5. Export Bills / Receivables (Unrealized Export Bills) per Group
    ExportBills AS (
        SELECT 
            MD.GroupSysID,
            SUM(
                CASE 
                    WHEN ISNULL(EBI.CURRENCY_CODE, 'USD') = 'USD' THEN ISNULL(EBI.ExportBillAmount, 0)
                    ELSE (ISNULL(EBI.ExportBillAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                END
            ) AS TotalBillAmountUSD,
            SUM(
                CASE 
                    WHEN (ISNULL(EBI.ExportBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) > 0 THEN
                        CASE 
                            WHEN ISNULL(EBI.CURRENCY_CODE, 'USD') = 'USD' THEN (ISNULL(EBI.ExportBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0))
                            ELSE ((ISNULL(EBI.ExportBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                        END
                    ELSE 0 
                END
            ) AS ReceivablesUSD
        FROM ExportBillInitiationMaster EBI WITH(NOLOCK)
        INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = EBI.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = EBI.CURRENCY_CODE AND clr.RateFor = 'BC SELLING'
        LEFT JOIN (
            SELECT BillRefNo, SUM(ISNULL(ProceedsRecvd, 0)) AS ProceedsRecvd
            FROM PRSCreationDistributionDetails WITH(NOLOCK)
            WHERE IsDeleted = 0
            GROUP BY BillRefNo
        ) Realized ON Realized.BillRefNo = EBI.EBIID
        WHERE EBI.IsDeleted = 0 AND ISNULL(EBI.IsCancelled, 0) = 0 AND EBI.ExportBillNo IS NOT NULL
        GROUP BY MD.GroupSysID

        UNION ALL

        SELECT 
            MD.GroupSysID,
            SUM(
                CASE 
                    WHEN ISNULL(LEBI.CURRENCY_CODE, 'USD') = 'USD' THEN ISNULL(LEBI.ExportLocalBillAmount, 0)
                    ELSE (ISNULL(LEBI.ExportLocalBillAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                END
            ) AS TotalBillAmountUSD,
            SUM(
                CASE 
                    WHEN (ISNULL(LEBI.ExportLocalBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) > 0 THEN
                        CASE 
                            WHEN ISNULL(LEBI.CURRENCY_CODE, 'USD') = 'USD' THEN (ISNULL(LEBI.ExportLocalBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0))
                            ELSE ((ISNULL(LEBI.ExportLocalBillAmount, 0) - ISNULL(Realized.ProceedsRecvd, 0)) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                        END
                    ELSE 0 
                END
            ) AS ReceivablesUSD
        FROM LocalExportBillInitiationMaster LEBI WITH(NOLOCK)
        INNER JOIN MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = LEBI.MasterDocID AND MD.IsDeleted = 0 AND MD.IsCancelled = 0
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = LEBI.CURRENCY_CODE AND clr.RateFor = 'BC SELLING'
        LEFT JOIN (
            SELECT BillRefNo, SUM(ISNULL(ProceedsRecvd, 0)) AS ProceedsRecvd
            FROM PRSCreationDistributionDetails WITH(NOLOCK)
            WHERE IsDeleted = 0
            GROUP BY BillRefNo
        ) Realized ON Realized.BillRefNo = LEBI.EBIID
        WHERE LEBI.IsDeleted = 0 AND ISNULL(LEBI.IsCancelled, 0) = 0 AND LEBI.ExportLocalBillNo IS NOT NULL
        GROUP BY MD.GroupSysID
    ),
    ExportBillSummary AS (
        SELECT 
            GroupSysID,
            SUM(TotalBillAmountUSD) AS TotalBillAmountUSD,
            SUM(ReceivablesUSD) AS ReceivablesUSD
        FROM ExportBills
        GROUP BY GroupSysID
    ),
    -- 6. Stock In Hand per Group
    StockSummary AS (
        SELECT 
            spu.GroupSysID,
            SUM(
                CASE 
                    WHEN ISNULL(spu.Currency, 'USD') = 'USD' 
                        THEN (ISNULL(spu.Fabrics_Raw_Marerials, 0) + ISNULL(spu.Accessories, 0) + ISNULL(spu.Work_In_Process, 0) + ISNULL(spu.Finished_Goods, 0))
                    ELSE ((ISNULL(spu.Fabrics_Raw_Marerials, 0) + ISNULL(spu.Accessories, 0) + ISNULL(spu.Work_In_Process, 0) + ISNULL(spu.Finished_Goods, 0)) * ISNULL(clr.ConvertFactor, 1)) / @USDRate
                END
            ) AS StockInhand
        FROM StockPositionUpload spu WITH(NOLOCK)
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = spu.Currency AND clr.RateFor = 'BC SELLING'
        WHERE spu.IsDeleted = 0
        GROUP BY spu.GroupSysID
    ),
    -- 7. BBLC Contracts summary
    BBLCSummary AS (
        SELECT 
            bb.GroupSysID,
            STRING_AGG(CAST(bb.BBLCNo AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY bb.BBLCNo) AS SalesContractNo,
            SUM(
                CASE 
                    WHEN ISNULL(bb.Currency, 'USD') = 'USD' THEN ISNULL(bb.BBLCAmount, 0)
                    ELSE (ISNULL(bb.BBLCAmount, 0) * ISNULL(clr.ConvertFactor, 1)) / @USDRate 
                END
            ) AS TotalSalesContractvalue
        FROM BBLCMaster bb WITH(NOLOCK)
        LEFT JOIN SystemManager..CurrencyLatestRate clr WITH(NOLOCK) 
            ON clr.CurrencyCode = bb.Currency AND clr.RateFor = 'BC SELLING'
        WHERE bb.IsDeleted = 0 AND bb.IsCancelled = 0
        GROUP BY bb.GroupSysID
    )
    SELECT 
        JobRefNo                 = gb.GroupRefNo,
        ExportersName            = cus.CustomerName,
        oDate                    = gb.JobDate,
        BTBAcceptedliability     = ISNULL(ba.BTBAcceptedliability, 0),
        TTIssued                 = ISNULL(tc.TTIssued, 0),
        CADIssued                = ISNULL(tc.CADIssued, 0),
        TotalLiability           = ISNULL(ba.BTBAcceptedliability, 0) + ISNULL(tc.TTIssued, 0) + ISNULL(tc.CADIssued, 0),
        BTBBillsPaidAlready      = ISNULL(bp.BTBBillsPaidAlready, 0),
        JobValue                 = gb.GroupAmount,
        SalesContractNo          = bblc.SalesContractNo,
        TotalSalesContractvalue  = ISNULL(bblc.TotalSalesContractvalue, 0),
        ExportToBeMade           = CASE 
                                     WHEN (gb.GroupAmount - ISNULL(ebs.TotalBillAmountUSD, 0)) > 0 
                                         THEN (gb.GroupAmount - ISNULL(ebs.TotalBillAmountUSD, 0)) 
                                     ELSE 0 
                                   END,
        Receivables              = ISNULL(ebs.ReceivablesUSD, 0),
        StockInhand              = ISNULL(stk.StockInhand, 0),
        gb.CustomerID
    FROM GroupBase gb
    LEFT JOIN [SystemManager]..CustomerProfileMaster cus WITH(NOLOCK) ON cus.CustomerID = gb.CustomerID
    LEFT JOIN BTBAccepted ba ON ba.GroupSysID = gb.GroupSysID
    LEFT JOIN TTCAD tc ON tc.GroupSysID = gb.GroupSysID
    LEFT JOIN BTBPaid bp ON bp.GroupSysID = gb.GroupSysID
    LEFT JOIN ExportBillSummary ebs ON ebs.GroupSysID = gb.GroupSysID
    LEFT JOIN StockSummary stk ON stk.GroupSysID = gb.GroupSysID
    LEFT JOIN BBLCSummary bblc ON bblc.GroupSysID = gb.GroupSysID
    ORDER BY gb.GroupRefNo ASC
END
GO
