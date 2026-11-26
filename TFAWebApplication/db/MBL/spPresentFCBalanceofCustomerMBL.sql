USE [EFA]
GO

/****** Object:  StoredProcedure [dbo].[spPresentFCBalanceofCustomerMBL]    Script Date: 11/26/2026 1:34:57 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[spPresentFCBalanceofCustomerMBL]  
@ToDate Datetime,@CustomerID varchar(50)
AS
	-- spPresentFCBalanceofCustomerMBL '2026-03-29','OCPM/26/623'
BEGIN 
Declare @USDRATE numeric(18,4)
Select @USDRATE=ConvertFactor from [SystemManager]..CurrencyLatestRate cr where cr.CurrencyCode='USD' and cr.RateFor='TT CLEAN'

	SELECT distinct
	g.GroupSysID,
	g.CustomerID,
	g.GroupRefNo,
	g.BankBranchID,
	c.CustomerName,
	b.BranchName,
	LCNumbers = STUFF(
    (
        SELECT ',' + m.LCNo
        FROM MasterDoc m
        WHERE m.GroupSysId = g.GroupSysId
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)')
    ,1,1,''),
	FCAccountNo=g.MarginAccount,
	FCBalance=(FCHeld.WORKING_BALANCE*cr.ConvertFactor)/@USDRATE,
	FCBalanceBDTinCr=(FCHeld.WORKING_BALANCE*cr.ConvertFactor)/10000000,
	g.MarginAccount

	FROM 
	
	GroupLC g  with(nolock)	
	Inner join [SystemManager]..CustomerProfileMaster c   with(nolock) on c.CustomerID=g.CustomerID
	Inner join [SystemManager]..BankProfileBranch  b   with(nolock) on b.BranchID=g.BankBranchID
	inner join [EFA_API_Exchange]..tblLoanListingFCHeldAPIExchange FCHeld   with(nolock) on FCHeld.RECID=g.MarginAccount
	left join [SystemManager]..CurrencyLatestRate cr   with(nolock) on cr.CurrencyCode=FCHeld.CURRENCY and cr.RateFor='TT CLEAN'
	WHERE  Cast(FCHeld.ImportDate as date) = @ToDate and g.CustomerID=@CustomerID
END

GO


