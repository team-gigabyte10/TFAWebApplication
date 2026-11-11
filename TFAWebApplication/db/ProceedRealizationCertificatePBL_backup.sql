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

	select m.MasterDocID, m.LCNo, format(m.IssueDate, 'dd-MMM-yyyy') IssueDate, g.CustomerID, c.CustomerName, c.CustomerAddress, bond.Number BondNumber, format(bond.ValidDate, 'dd/MM/yyyy') BondExpiryDate, bin.Number BinNumber, format(bin.ValidDate, 'dd/MM/yyyy') BinExpiryDate, cd.AccountCode AccountNo, isnull(p.RealizedAmount, 0)/@USDRate RealizedAmount, isnull(Bill.ExportBillAmount, 0)/@USDRate ExportBillAmount
	from MasterDoc m with(nolock)
		inner join GroupLC g with(nolock) on g.GroupSysID = m.GroupSysID
		left join SystemManager..CustomerProfileMaster c with(nolock) on c.CustomerID = g.CustomerID
		left join SystemManager..CustomerRelatedRegistrationOrCertificate bond with(nolock) on bond.CustomerID = g.CustomerID and bond.CategoryID = 'EFV/22/8' and bond.IsDeleted = 0
		left join SystemManager..CustomerRelatedRegistrationOrCertificate bin with(nolock) on bin.CustomerID = g.CustomerID and bin.CategoryID = 'EFV/20/75' and bin.IsDeleted = 0
		left join (
			select Customer, MasterDocID, sum(C_Amount * CLR.ConvertFactor) RealizedAmount
			from PRSCreationMaster p with(nolock)
				left join SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = p.ProceedsCurrency AND CLR.RateFor = 'BC SELLING'
			where p.IsDeleted = 0 and p.IsCheck = 1
			group by p.Customer, p.MasterDocID
		) p on p.Customer = g.CustomerID and p.MasterDocID = m.MasterDocID
		left join (
			select a.CustomerID, a.AccountCode, a.AdditionalFilter, e.DisplayCode 
			from SystemManager..CustomerProfileAccounts a with(nolock)
				left join SystemManager..EntityFixedVariables e with(nolock) on e.EntityID = a.AccountTypeID
			where a.IsDeleted = 0 and e.DisplayCode = 'CD'
		) cd on cd.CustomerID = g.CustomerID
		left join (
			select Bill.CustomerCode, Bill.MasterDocID, sum(Bill.ExportBillAmount * CLR.ConvertFactor)  ExportBillAmount
			from (
				select CustomerCode, MasterDocID, CURRENCY_CODE, ExportBillAmount from ExportBillInitiationMaster where IsDeleted = 0 and isnull(IsCancelled, 0) = 0 and ExportBillNo is not null
				union
				select CustomerCode, MasterDocID, CURRENCY_CODE, ExportLocalBillAmount from LocalExportBillInitiationMaster where IsDeleted = 0 and isnull(IsCancelled, 0) = 0 and ExportLocalBillNo is not null
			) Bill
			left join SystemManager..CurrencyLatestRate CLR with(nolock) ON CLR.CurrencyCode = Bill.CURRENCY_CODE AND CLR.RateFor = 'BC SELLING'
			group by Bill.CustomerCode, Bill.MasterDocID
		) bill on bill.CustomerCode = g.CustomerID and bill.MasterDocID = m.MasterDocID
	where m.IsDeleted = 0 and m.IsCancelled = 0 and g.CustomerID = @CustomerID
END

