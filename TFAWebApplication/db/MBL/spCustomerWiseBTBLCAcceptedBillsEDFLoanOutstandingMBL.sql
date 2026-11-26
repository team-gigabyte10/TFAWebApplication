USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spCustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL]    Script Date: 11/26/2026 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[spCustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL]
    @AsOnDate DATE,
    @CustomerID VARCHAR(50) = NULL,
    @BranchID VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize optional parameters
    IF @CustomerID = '' OR @CustomerID = 'ALL' SET @CustomerID = NULL;
    IF @BranchID = '' OR @BranchID = 'ALL' SET @BranchID = NULL;

    --------------------------------------------------------------------------------------
    -- 1. Base BBLC Records within @AsOnDate and matching Customer / Branch filters
    --------------------------------------------------------------------------------------
    ;WITH BBLC_Base AS (
        SELECT 
            B.BBLCID,
            B.BBLCNo AS BTBLcNumber,
            B.ExternalID AS LcTfNumber,
            B.IssueDate AS LcOpeningDate,
            ISNULL(B.BBLCAmount, 0) AS LcAmount,
            G.CustomerID,
            G.BankBranchID AS BranchID,
            C.CustomerName,
            Br.BranchName
        FROM BBLCMaster B WITH(NOLOCK)
        INNER JOIN GroupLC G WITH(NOLOCK) ON G.GroupSysID = B.GroupSysID AND G.IsDeleted = 0
        LEFT JOIN SystemManager..CustomerProfileMaster C WITH(NOLOCK) ON C.CustomerID = G.CustomerID
        LEFT JOIN SystemManager..BankProfileBranch Br WITH(NOLOCK) ON Br.BranchID = G.BankBranchID
        WHERE B.IsDeleted = 0 
          AND B.IsCancelled = 0 
          AND CAST(B.IssueDate AS DATE) <= @AsOnDate
          AND (@CustomerID IS NULL OR G.CustomerID = @CustomerID)
          AND (@BranchID IS NULL OR G.BankBranchID = @BranchID)
    ),

    --------------------------------------------------------------------------------------
    -- 2. Total Accepted Bills under each BBLC (to determine unutilized LC Liability)
    --------------------------------------------------------------------------------------
    BBLC_AcceptedTotal AS (
        SELECT 
            F.BBLCID,
            SUM(ISNULL(F.BillAmount, 0)) AS TotalAcceptedBillAmount
        FROM ForeignDocumentAcceptanceMaster F WITH(NOLOCK)
        WHERE F.IsDeleted = 0 
          AND F.IsCancelled = 0
          AND CAST(ISNULL(F.AcceptanceDate, F.BillGenerationDate) AS DATE) <= @AsOnDate
        GROUP BY F.BBLCID
    ),

    --------------------------------------------------------------------------------------
    -- 3. Bill Payments up to @AsOnDate
    --------------------------------------------------------------------------------------
    BillPayments AS (
        SELECT 
            FDPM.FDAID,
            SUM(ISNULL(FDPM.PaymentAmount, 0)) AS TotalPaymentAmount
        FROM ForeignDocumentPaymentMaster FDPM WITH(NOLOCK)
        WHERE FDPM.IsDeleted = 0
          AND CAST(FDPM.PaymentDate AS DATE) <= @AsOnDate
        GROUP BY FDPM.FDAID
    ),

    --------------------------------------------------------------------------------------
    -- 4. Accepted Bills with Outstanding Liability
    --------------------------------------------------------------------------------------
    AcceptedBills AS (
        SELECT 
            F.FDAID,
            F.BBLCID,
            F.BillNo,
            ISNULL(NULLIF(F.ReferenceNo, ''), F.BillNo) AS BillsTfNumber,
            F.AcceptanceDate,
            (ISNULL(F.BillAmount, 0) - ISNULL(BP.TotalPaymentAmount, 0)) AS BillsAmount,
            F.MATURITY_DATE AS BillsMaturityDate
        FROM ForeignDocumentAcceptanceMaster F WITH(NOLOCK)
        INNER JOIN BBLC_Base B ON B.BBLCID = F.BBLCID
        LEFT JOIN BillPayments BP ON BP.FDAID = F.FDAID
        WHERE F.IsDeleted = 0 
          AND F.IsCancelled = 0
          AND CAST(ISNULL(F.AcceptanceDate, F.BillGenerationDate) AS DATE) <= @AsOnDate
          AND (ISNULL(F.BillAmount, 0) - ISNULL(BP.TotalPaymentAmount, 0)) > 0
    ),

    --------------------------------------------------------------------------------------
    -- 5. EDF Loans with Outstanding Balance
    --------------------------------------------------------------------------------------
    EDFLoans_Raw AS (
        SELECT 
            L.LoanCreationID,
            L.LoanNo AS EdfLoanNumber,
            L.LoanCreationDate AS EdfLoanOpeningDate,
            ISNULL(L.LoanAmount, 0) AS EdfLoanAmount,
            CASE 
                WHEN L.OutstandingAmount IS NOT NULL THEN L.OutstandingAmount
                WHEN L.TOT_OS IS NOT NULL THEN L.TOT_OS
                WHEN L.PRINCIPAL_OS IS NOT NULL THEN L.PRINCIPAL_OS
                ELSE CASE WHEN (ISNULL(L.LoanAmount, 0) - ISNULL(L.AdjustmentAmount, 0)) > 0 
                          THEN (ISNULL(L.LoanAmount, 0) - ISNULL(L.AdjustmentAmount, 0)) ELSE 0 END
            END AS EdfLoanOutstanding,
            L.MATURITY_DATE AS EdfLoanMaturityDate,
            COALESCE(
                NULLIF(L.BBLCID, ''), 
                F_Match.BBLCID,
                LCIC.BBLCID
            ) AS BBLCID,
            COALESCE(
                NULLIF(L.BillNumber, ''),
                NULLIF(L.AdditionalFilter, ''),
                F_Match.BillNo
            ) AS BillNo
        FROM LoanCreation L WITH(NOLOCK)
        LEFT JOIN ForeignDocumentAcceptanceMaster F_Match WITH(NOLOCK) 
            ON (F_Match.BillNo = L.AdditionalFilter OR F_Match.BillNo = L.BillNumber OR F_Match.BillNo = L.ExternalID OR F_Match.ReferenceNo = L.AdditionalFilter)
            AND F_Match.IsDeleted = 0
        LEFT JOIN (
            SELECT DISTINCT C.LoanCreationID, FD.BBLCID
            FROM LoanCreationInvoiceChild C WITH(NOLOCK)
            INNER JOIN ForeignDocumentAcceptanceMaster FD WITH(NOLOCK) ON FD.BillNo = C.BillNo AND FD.IsDeleted = 0
            WHERE C.IsDeleted = 0
        ) LCIC ON LCIC.LoanCreationID = L.LoanCreationID
        WHERE L.IsDeleted = 0 
          AND (
              L.Product IN ('LEDF', 'EDF')
              OR L.LoanAgainst LIKE '%LEDF%' 
              OR L.LoanAgainst LIKE '%EDF%'
              OR L.LoanType LIKE '%EDF%'
          )
          AND CAST(L.LoanCreationDate AS DATE) <= @AsOnDate
    ),
    EDFLoans AS (
        SELECT 
            E.LoanCreationID,
            E.EdfLoanNumber,
            E.EdfLoanOpeningDate,
            E.EdfLoanAmount,
            E.EdfLoanOutstanding,
            E.EdfLoanMaturityDate,
            E.BBLCID,
            E.BillNo
        FROM EDFLoans_Raw E
        INNER JOIN BBLC_Base B ON B.BBLCID = E.BBLCID
        WHERE E.EdfLoanOutstanding > 0
    ),

    --------------------------------------------------------------------------------------
    -- 6. Combine Bills and EDF Loans per BBLC without Cartesian multiplication
    --------------------------------------------------------------------------------------
    -- 6a. Direct match where EDF Loan explicitly references the Bill Number
    MatchedDetails AS (
        SELECT 
            AB.BBLCID,
            AB.BillsTfNumber,
            AB.AcceptanceDate,
            AB.BillsAmount,
            AB.BillsMaturityDate,
            EL.EdfLoanNumber,
            EL.EdfLoanOpeningDate,
            EL.EdfLoanAmount,
            EL.EdfLoanOutstanding,
            EL.EdfLoanMaturityDate,
            AB.FDAID,
            EL.LoanCreationID
        FROM AcceptedBills AB
        INNER JOIN EDFLoans EL 
            ON EL.BBLCID = AB.BBLCID 
           AND EL.BillNo IS NOT NULL 
           AND EL.BillNo <> '' 
           AND (EL.BillNo = AB.BillNo OR EL.BillNo = AB.BillsTfNumber)
    ),
    -- 6b. Remaining unlinked bills
    UnmatchedBills AS (
        SELECT 
            AB.*,
            ROW_NUMBER() OVER (PARTITION BY AB.BBLCID ORDER BY AB.AcceptanceDate, AB.BillNo) AS URowNum
        FROM AcceptedBills AB
        WHERE AB.FDAID NOT IN (SELECT FDAID FROM MatchedDetails WHERE FDAID IS NOT NULL)
    ),
    -- 6c. Remaining unlinked loans
    UnmatchedLoans AS (
        SELECT 
            EL.*,
            ROW_NUMBER() OVER (PARTITION BY EL.BBLCID ORDER BY EL.EdfLoanOpeningDate, EL.EdfLoanNumber) AS URowNum
        FROM EDFLoans EL
        WHERE EL.LoanCreationID NOT IN (SELECT LoanCreationID FROM MatchedDetails WHERE LoanCreationID IS NOT NULL)
    ),
    -- 6d. Align remaining unlinked bills and loans side-by-side
    CombinedRemaining AS (
        SELECT 
            COALESCE(UB.BBLCID, UL.BBLCID) AS BBLCID,
            UB.BillsTfNumber,
            UB.AcceptanceDate,
            UB.BillsAmount,
            UB.BillsMaturityDate,
            UL.EdfLoanNumber,
            UL.EdfLoanOpeningDate,
            UL.EdfLoanAmount,
            UL.EdfLoanOutstanding,
            UL.EdfLoanMaturityDate
        FROM UnmatchedBills UB
        FULL OUTER JOIN UnmatchedLoans UL 
            ON UL.BBLCID = UB.BBLCID AND UL.URowNum = UB.URowNum
    ),
    -- 6e. All details combined
    AllDetails AS (
        SELECT 
            BBLCID, BillsTfNumber, AcceptanceDate, BillsAmount, BillsMaturityDate,
            EdfLoanNumber, EdfLoanOpeningDate, EdfLoanAmount, EdfLoanOutstanding, EdfLoanMaturityDate
        FROM MatchedDetails
        UNION ALL
        SELECT 
            BBLCID, BillsTfNumber, AcceptanceDate, BillsAmount, BillsMaturityDate,
            EdfLoanNumber, EdfLoanOpeningDate, EdfLoanAmount, EdfLoanOutstanding, EdfLoanMaturityDate
        FROM CombinedRemaining
    ),
    AllDetailsWithRank AS (
        SELECT 
            AD.*,
            ROW_NUMBER() OVER (PARTITION BY AD.BBLCID ORDER BY AD.AcceptanceDate, AD.EdfLoanOpeningDate) AS RowRank
        FROM AllDetails AD
    ),

    --------------------------------------------------------------------------------------
    -- 7. Final Presentation: Join BBLC with Details & Filter Active Liabilities
    --------------------------------------------------------------------------------------
    FinalData AS (
        SELECT 
            B.BranchName,
            B.CustomerName,
            B.BTBLcNumber,
            B.LcTfNumber,
            B.LcOpeningDate,
            B.LcAmount,
            -- LC Outstanding Amount: Unutilized LC Liability
            CASE 
                WHEN (B.LcAmount - ISNULL(BAT.TotalAcceptedBillAmount, 0)) > 0 
                THEN (B.LcAmount - ISNULL(BAT.TotalAcceptedBillAmount, 0))
                ELSE 0 
            END AS LcOutstandingAmount,
            AD.BillsTfNumber,
            AD.AcceptanceDate,
            AD.BillsAmount,
            AD.BillsMaturityDate,
            AD.EdfLoanNumber,
            AD.EdfLoanOpeningDate,
            AD.EdfLoanAmount,
            AD.EdfLoanOutstanding,
            AD.EdfLoanMaturityDate,
            -- Liability trackers to ensure only active records are displayed
            CASE 
                WHEN (B.LcAmount - ISNULL(BAT.TotalAcceptedBillAmount, 0)) > 0 
                THEN (B.LcAmount - ISNULL(BAT.TotalAcceptedBillAmount, 0))
                ELSE 0 
            END AS TotalLcOS,
            ISNULL(AD.BillsAmount, 0) AS CurrentBillOS,
            ISNULL(AD.EdfLoanOutstanding, 0) AS CurrentLoanOS,
            ISNULL(AD.RowRank, 1) AS RowRank
        FROM BBLC_Base B
        LEFT JOIN BBLC_AcceptedTotal BAT ON BAT.BBLCID = B.BBLCID
        LEFT JOIN AllDetailsWithRank AD ON AD.BBLCID = B.BBLCID
    )
    SELECT 
        BTBLcNumber,
        LcTfNumber,
        LcOpeningDate,
        LcAmount,
        LcOutstandingAmount,
        BillsTfNumber,
        AcceptanceDate,
        BillsAmount,
        BillsMaturityDate,
        EdfLoanNumber,
        EdfLoanOpeningDate,
        EdfLoanAmount,
        EdfLoanOutstanding,
        EdfLoanMaturityDate,
        CustomerName,
        BranchName
    FROM FinalData
    WHERE (TotalLcOS > 0 OR CurrentBillOS > 0 OR CurrentLoanOS > 0)
    ORDER BY BranchName, CustomerName, BTBLcNumber, RowRank;
END
GO
