USE EFA
GO

Create Or Alter Proc spRPT_LCAdvisingReport
	@FromDate Date,
	@ToDate Date
As

 -- spRPT_LCAdvisingReport '2024-01-01', '2026-01-01'

Begin
	select 
		LC.LCNumber,
		LC.Currency,
		LC.LCAmount,
		LC.IsCustomerLC,
		CP.CustomerName Customer,
		BPB.BranchName Branch,
		SC.AdviceNo,
		SC.AdviceDate
	from EFA..LCAdvisingRegister LC  WITH(NOLOCK)
		Left Join EFA..LCScrutiny SC  WITH(NOLOCK)  ON LC.LCReceiveID = SC.LCReceiveID AND SC.IsDeleted = 0
		Left Join SystemManager..BankProfileBranch BPB  WITH(NOLOCK)  ON LC.BranchID = BPB.BranchID AND BPB.IsDeleted = 0
		Left Join SystemManager..CustomerProfileMaster CP WITH(NOLOCK) ON LC.Customer = CP.CustomerID AND CP.IsDeleted = 0
	where LC.IsDeleted = 0 and LC.IsCancelled = 0 and SC.AdviceDate between @FromDate and @ToDate
End

