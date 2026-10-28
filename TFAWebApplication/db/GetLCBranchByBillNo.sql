USE EFA
GO

-- LC branch of a bill, found by Bill No.
-- It searches local export bills, foreign export bills and import acceptances.
-- "BranchUsedByStatement" is the branch the Statement of Overdue Accepted Bills shows (before the customer default branch).

Declare @BillNo Varchar(100) = '1234LDBC240007'

-- Local export bills (LDBC)
select 'Local export' BillType, LEB.ExportLocalBillNo BillNo, LC.LCNo,
	LC.ADBranchID  LCBranchID,  LCB.BranchName  LCBranchName,
	LEB.BranchID   BillBranchID, BB.BranchName  BillBranchName,
	ISNULL(LC.ADBranchID, LEB.BranchID) BranchUsedByStatement,
	ISNULL(UB.BranchName, '') BranchUsedName
from EFA..LocalExportBillInitiationMaster LEB WITH(NOLOCK)
	Left Join
	(
		select MasterDocID LCID, LCNo, ADBranchID from EFA..MasterDoc WITH(NOLOCK)
		Union All
		select LCReceiveID, LCNumber, ADBranchID from EFA..LCAdvisingRegister WITH(NOLOCK)
	) LC ON LC.LCID = LEB.MasterDocID
	Left Join SystemManager..BankProfileBranch LCB WITH(NOLOCK) ON LCB.BranchID = LC.ADBranchID
	Left Join SystemManager..BankProfileBranch BB  WITH(NOLOCK) ON BB.BranchID  = LEB.BranchID
	Left Join SystemManager..BankProfileBranch UB  WITH(NOLOCK) ON UB.BranchID  = ISNULL(LC.ADBranchID, LEB.BranchID)
where LEB.ExportLocalBillNo = @BillNo and LEB.IsDeleted = 0

Union All

-- Foreign export bills (FDBC)
select 'Foreign export', EB.ExportBillNo, LC.LCNo,
	LC.ADBranchID, LCB.BranchName,
	EB.BranchID, BB.BranchName,
	ISNULL(LC.ADBranchID, EB.BranchID),
	ISNULL(UB.BranchName, '')
from EFA..ExportBillInitiationMaster EB WITH(NOLOCK)
	Left Join
	(
		select MasterDocID LCID, LCNo, ADBranchID from EFA..MasterDoc WITH(NOLOCK)
		Union All
		select LCReceiveID, LCNumber, ADBranchID from EFA..LCAdvisingRegister WITH(NOLOCK)
	) LC ON LC.LCID = EB.MasterDocID
	Left Join SystemManager..BankProfileBranch LCB WITH(NOLOCK) ON LCB.BranchID = LC.ADBranchID
	Left Join SystemManager..BankProfileBranch BB  WITH(NOLOCK) ON BB.BranchID  = EB.BranchID
	Left Join SystemManager..BankProfileBranch UB  WITH(NOLOCK) ON UB.BranchID  = ISNULL(LC.ADBranchID, EB.BranchID)
where EB.ExportBillNo = @BillNo and EB.IsDeleted = 0

Union All

-- Import acceptances
select 'Import', ISNULL(NULLIF(FDAM.NegoBankBillRef, ''), FDAM.BillNo), LC.LCNo,
	ISNULL(GL.ADBranchID, RM.ADBranchID), LCB.BranchName,
	FDAM.BranchID, BB.BranchName,
	ISNULL(ISNULL(GL.ADBranchID, RM.ADBranchID), FDAM.BranchID),
	ISNULL(UB.BranchName, '')
from EFA..ForeignDocumentAcceptanceMaster FDAM WITH(NOLOCK)
	Left Join
	(
		select BBLCID LCID, BBLCNo LCNo, GroupSysID from EFA..BBLCMaster WITH(NOLOCK)
		Union All
		select ImportLCID, ImportLCNo, NULL from EFA..ImportLCMaster WITH(NOLOCK)
	) LC ON LC.LCID = FDAM.BBLCID
	Left Join EFA..GroupLC GL WITH(NOLOCK) ON GL.GroupSysID = LC.GroupSysID
	Left Join EFA..BBLCRequestMaster RM WITH(NOLOCK) ON RM.BBLCID = LC.LCID
	Left Join SystemManager..BankProfileBranch LCB WITH(NOLOCK) ON LCB.BranchID = ISNULL(GL.ADBranchID, RM.ADBranchID)
	Left Join SystemManager..BankProfileBranch BB  WITH(NOLOCK) ON BB.BranchID  = FDAM.BranchID
	Left Join SystemManager..BankProfileBranch UB  WITH(NOLOCK) ON UB.BranchID  = ISNULL(ISNULL(GL.ADBranchID, RM.ADBranchID), FDAM.BranchID)
where (FDAM.BillNo = @BillNo or FDAM.NegoBankBillRef = @BillNo) and FDAM.IsDeleted = 0
GO
