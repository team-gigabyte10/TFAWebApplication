USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spCustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL]    Script Date: 11/26/2026 1:30:02 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[spCustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL]
    @AsOnDate DATE
AS
	-- spCustomerWiseBTBLCAcceptedBillsEDFLoanOutstandingMBL '2026-08-01'
BEGIN
    SELECT
        B.BBLCNo AS BTBLcNumber,
        B.ExternalID AS LcTfNumber,
        B.IssueDate AS LcOpeningDate,
        B.BBLCAmount AS LcAmount,
        '' AS LcOutstandingAmount,
        F.ReferenceNo AS BillsTfNumber,
        F.AcceptanceDate AS AcceptanceDate,
        F.BillAmount AS BillsAmount,
        F.MATURITY_DATE AS BillsMaturityDate,
        L.LoanNo AS EdfLoanNumber,
        L.LoanCreationDate AS EdfLoanOpeningDate,
        L.LoanAmount AS EdfLoanAmount,
        '' AS EdfLoanOutstanding,
        L.MATURITY_DATE AS EdfLoanMaturityDate,
		C.CustomerName,
		Br.BranchName
    FROM BBLCMaster B
		LEFT JOIN GroupLC G ON G.GroupSysID = B.GroupSysID
		LEFT JOIN ForeignDocumentAcceptanceMaster F ON F.BBLCID = B.BBLCID
		LEFT JOIN LoanCreation L ON L.BBLCID = B.BBLCID
		LEFT JOIN SystemManager..CustomerProfileMaster C ON C.CustomerID = G.CustomerID
		LEFT JOIN SystemManager..BankProfileBranch Br ON Br.BranchID = G.BankBranchID
    WHERE B.IsDeleted = 0 AND B.IsCancelled = 0 AND CAST(B.IssueDate AS DATE) <= @AsOnDate
END
GO


