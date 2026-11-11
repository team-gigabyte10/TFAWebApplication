USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spProceedRealizationCertificatePBL]    Script Date: 11/10/2026 5:02:22 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[spProceedRealizationCertificatePBL] 
	@CustomerID varchar(50)
AS
	-- spProceedRealizationCertificatePBL 'CPM/22/4'
BEGIN  
	DECLARE @USDRate DECIMAL(18,4)
	SELECT  @USDRate = ConvertFactor FROM SystemManager..CurrencyLatestRate WITH(NOLOCK) WHERE RateFor = 'BC SELLING' AND CurrencyCode='USD'

	SELECT 
		m.MasterDocID, 
		m.LCNo, 
		FORMAT(COALESCE(m.IssueDate, Advi.IssueDate), 'dd-MMM-yyyy') AS IssueDate, 
		FORMAT(COALESCE(m.IssueDate, Advi.IssueDate), 'dd-MMM-yyyy') AS ContractDate,
		COALESCE(NULLIF(Applicant.Name, ''), NULLIF(m.Applicant, ''), NULLIF(Advi.Applicant, ''), '') AS BuyerName,
		COALESCE(NULLIF(m.Currency, ''), NULLIF(Advi.Currency, ''), '') AS Currency,
		ISNULL(NULLIF(m.LCAmount, 0), ISNULL(Advi.LCAmount, 0)) AS LCAmount,
		CAST(
			CASE 
				WHEN UPPER(COALESCE(NULLIF(m.Currency, ''), NULLIF(Advi.Currency, ''), 'USD')) = 'USD' 
					THEN ISNULL(NULLIF(m.LCAmount, 0), ISNULL(Advi.LCAmount, 0))
				WHEN @USDRate > 0 
					THEN (ISNULL(NULLIF(m.LCAmount, 0), ISNULL(Advi.LCAmount, 0)) * ISNULL(CLR_LC.ConvertFactor, 1.0)) / @USDRate
				ELSE ISNULL(NULLIF(m.LCAmount, 0), ISNULL(Advi.LCAmount, 0))
			END 
		AS DECIMAL(18, 2)) AS USDEquivalentAmount,
		g.CustomerID, 
		c.CustomerName, 
		c.CustomerAddress, 
		bond.Number AS BondNumber, 
		FORMAT(bond.ValidDate, 'dd/MM/yyyy') AS BondExpiryDate, 
		bin.Number AS BinNumber, 
		FORMAT(bin.ValidDate, 'dd/MM/yyyy') AS BinExpiryDate, 
		cd.AccountCode AS AccountNo, 
		ISNULL(p.RealizedAmount, 0)/@USDRate AS RealizedAmount, 
		ISNULL(Bill.ExportBillAmount, 0)/@USDRate AS ExportBillAmount
	FROM MasterDoc m WITH(NOLOCK)
		INNER JOIN GroupLC g WITH(NOLOCK) ON g.GroupSysID = m.GroupSysID
		LEFT JOIN LCAdvisingRegister Advi WITH(NOLOCK) ON Advi.LCReceiveID = m.LCReceiveID
		LEFT JOIN SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = ISNULL(NULLIF(m.Applicant, ''), Advi.Applicant)
		LEFT JOIN SystemManager..CurrencyLatestRate CLR_LC WITH(NOLOCK) 
			ON CLR_LC.CurrencyCode = COALESCE(NULLIF(m.Currency, ''), NULLIF(Advi.Currency, '')) 
			AND CLR_LC.RateFor = 'BC SELLING'
		LEFT JOIN SystemManager..CustomerProfileMaster c WITH(NOLOCK) ON c.CustomerID = g.CustomerID
		LEFT JOIN SystemManager..CustomerRelatedRegistrationOrCertificate bond WITH(NOLOCK) ON bond.CustomerID = g.CustomerID AND bond.CategoryID = 'EFV/22/8' AND bond.IsDeleted = 0
		LEFT JOIN SystemManager..CustomerRelatedRegistrationOrCertificate bin WITH(NOLOCK) ON bin.CustomerID = g.CustomerID AND bin.CategoryID = 'EFV/20/75' AND bin.IsDeleted = 0
		LEFT JOIN (
			SELECT Customer, MasterDocID, SUM(C_Amount * CLR.ConvertFactor) AS RealizedAmount
			FROM PRSCreationMaster p WITH(NOLOCK)
				LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = p.ProceedsCurrency AND CLR.RateFor = 'BC SELLING'
			WHERE p.IsDeleted = 0 AND p.IsCheck = 1
			GROUP BY p.Customer, p.MasterDocID
		) p ON p.Customer = g.CustomerID AND p.MasterDocID = m.MasterDocID
		LEFT JOIN (
			SELECT a.CustomerID, a.AccountCode, a.AdditionalFilter, e.DisplayCode 
			FROM SystemManager..CustomerProfileAccounts a WITH(NOLOCK)
				LEFT JOIN SystemManager..EntityFixedVariables e WITH(NOLOCK) ON e.EntityID = a.AccountTypeID
			WHERE a.IsDeleted = 0 AND e.DisplayCode = 'CD'
		) cd ON cd.CustomerID = g.CustomerID
		LEFT JOIN (
			SELECT Bill.CustomerCode, Bill.MasterDocID, SUM(Bill.ExportBillAmount * CLR.ConvertFactor) AS ExportBillAmount
			FROM (
				SELECT CustomerCode, MasterDocID, CURRENCY_CODE, ExportBillAmount FROM ExportBillInitiationMaster WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportBillNo IS NOT NULL
				UNION
				SELECT CustomerCode, MasterDocID, CURRENCY_CODE, ExportLocalBillAmount FROM LocalExportBillInitiationMaster WHERE IsDeleted = 0 AND ISNULL(IsCancelled, 0) = 0 AND ExportLocalBillNo IS NOT NULL
			) Bill
			LEFT JOIN SystemManager..CurrencyLatestRate CLR WITH(NOLOCK) ON CLR.CurrencyCode = Bill.CURRENCY_CODE AND CLR.RateFor = 'BC SELLING'
			GROUP BY Bill.CustomerCode, Bill.MasterDocID
		) bill ON bill.CustomerCode = g.CustomerID AND bill.MasterDocID = m.MasterDocID
	WHERE m.IsDeleted = 0 AND m.IsCancelled = 0 AND g.CustomerID = @CustomerID
END
GO
