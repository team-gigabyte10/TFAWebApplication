USE EFA
GO

-- Set the branch of ONE export bill and its LC, so the Statement of Overdue Accepted Bills shows it.
-- The bill can be a LOCAL export bill (LDBC, table LocalExportBillInitiationMaster)
-- or a FOREIGN export bill (FDBC, table ExportBillInitiationMaster). The script checks both.
-- The Statement takes the branch from ISNULL(LC ADBranchID, bill BranchID),
-- where the LC is MasterDoc (LCNo) or LCAdvisingRegister (LCNumber).
-- The branch name comes from SystemManager..BankProfileBranch.
-- The script stops with an error if the bill or the branch is not found.
-- It ends with ROLLBACK. Change it to COMMIT only after you check the output.

Declare @LCNo       Varchar(100) = 'TESTLC18-NOV-24-1'
Declare @BillNo     Varchar(100) = '1234LDBC240007'
Declare @CustomerID Varchar(50)  = 'CPM/23/3'
Declare @BranchID   Varchar(50)  = 'OBPB/25/14'

Declare @EBIID Varchar(50), @MasterDocID Varchar(50), @IsLocal Bit

-- Step 1: find the export bill. Local bills first, then foreign bills.
-- The bill holds the LC id, so the LC text does not need to match.
select Top 1 @EBIID = EBIID, @MasterDocID = MasterDocID, @IsLocal = 1
from EFA..LocalExportBillInitiationMaster WITH(NOLOCK)
where CustomerCode = @CustomerID and IsDeleted = 0
  and LTRIM(RTRIM(ExportLocalBillNo)) = @BillNo

If @EBIID Is Null
	select Top 1 @EBIID = EBIID, @MasterDocID = MasterDocID, @IsLocal = 0
	from EFA..ExportBillInitiationMaster WITH(NOLOCK)
	where CustomerCode = @CustomerID and IsDeleted = 0
	  and LTRIM(RTRIM(ExportBillNo)) = @BillNo

If @EBIID Is Null
Begin
	-- Help: show close matches in both tables
	select 'Local export bill like' Info, EBIID, ExportLocalBillNo BillNo, CustomerCode, MasterDocID, BranchID, IsDeleted
	from EFA..LocalExportBillInitiationMaster WITH(NOLOCK)
	where ExportLocalBillNo like '%' + @BillNo + '%'

	select 'Foreign export bill like' Info, EBIID, ExportBillNo BillNo, CustomerCode, MasterDocID, BranchID, IsDeleted
	from EFA..ExportBillInitiationMaster WITH(NOLOCK)
	where ExportBillNo like '%' + @BillNo + '%';

	Throw 50002, 'Export bill not found for this customer. See the help result sets above.', 1
End

select 'Bill found' Info, CASE WHEN @IsLocal = 1 THEN 'Local export (LDBC)' ELSE 'Foreign export (FDBC)' END BillType, @EBIID EBIID, @MasterDocID MasterDocID

-- Step 2: show the LC of the bill. It is in MasterDoc, or in LCAdvisingRegister.
select 'LC in MasterDoc' Info, MasterDocID, LCNo, LCReceiveID, ADBranchID, BranchID, IsDeleted
from EFA..MasterDoc WITH(NOLOCK) where MasterDocID = @MasterDocID

select 'LC in LCAdvisingRegister' Info, LCReceiveID, LCNumber, ADBranchID, BranchID, IsDeleted
from EFA..LCAdvisingRegister WITH(NOLOCK)
where LCReceiveID = @MasterDocID
   or LCReceiveID = (select LCReceiveID from EFA..MasterDoc WITH(NOLOCK) where MasterDocID = @MasterDocID);

If Not Exists (select 1 from EFA..MasterDoc WITH(NOLOCK) where MasterDocID = @MasterDocID)
   And Not Exists (select 1 from EFA..LCAdvisingRegister WITH(NOLOCK) where LCReceiveID = @MasterDocID)
	Throw 50001, 'The bill has no LC in MasterDoc or LCAdvisingRegister.', 1

-- Step 3: check the branch
If Not Exists (select 1 from SystemManager..BankProfileBranch WITH(NOLOCK) where BranchID = @BranchID)
Begin
	select 'Branches (help)' Info, BranchID, BranchName from SystemManager..BankProfileBranch WITH(NOLOCK) where IsDeleted = 0 order by BranchName;
	Throw 50003, 'Branch ID not found in BankProfileBranch. See the help result set above.', 1
End

select 'Branch used' Info, BranchID, BranchName from SystemManager..BankProfileBranch WITH(NOLOCK) where BranchID = @BranchID;

-- Step 4: show how many other export bills use the same LC
select 'Other bills on the same LC' Info,
	(select COUNT(*) from EFA..LocalExportBillInitiationMaster WITH(NOLOCK) where MasterDocID = @MasterDocID and EBIID <> @EBIID and IsDeleted = 0)
  + (select COUNT(*) from EFA..ExportBillInitiationMaster WITH(NOLOCK)      where MasterDocID = @MasterDocID and EBIID <> @EBIID and IsDeleted = 0) OtherBills

-- Step 5: update
Begin Transaction

	If @IsLocal = 1
	Begin
		update EFA..LocalExportBillInitiationMaster
		set BranchID = @BranchID, ADBranchID = @BranchID
		where EBIID = @EBIID and (ISNULL(BranchID, '') <> @BranchID or ISNULL(ADBranchID, '') <> @BranchID)

		Print 'LocalExportBillInitiationMaster rows updated: ' + CAST(@@ROWCOUNT As Varchar(20))
	End
	Else
	Begin
		update EFA..ExportBillInitiationMaster
		set BranchID = @BranchID
		where EBIID = @EBIID and ISNULL(BranchID, '') <> @BranchID

		Print 'ExportBillInitiationMaster rows updated: ' + CAST(@@ROWCOUNT As Varchar(20))
	End

	-- LC level (the Statement reads this first). It also changes the other bills on the same LC.
	update EFA..MasterDoc
	set ADBranchID = @BranchID
	where MasterDocID = @MasterDocID and ISNULL(ADBranchID, '') <> @BranchID

	Print 'MasterDoc rows updated: ' + CAST(@@ROWCOUNT As Varchar(20))

	update EFA..LCAdvisingRegister
	set ADBranchID = @BranchID
	where (LCReceiveID = @MasterDocID
	       or LCReceiveID = (select LCReceiveID from EFA..MasterDoc WITH(NOLOCK) where MasterDocID = @MasterDocID))
	  and ISNULL(ADBranchID, '') <> @BranchID

	Print 'LCAdvisingRegister rows updated: ' + CAST(@@ROWCOUNT As Varchar(20))

	-- Step 6: check the branch and name the Statement will show for this bill
	select B.BillNo,
		ISNULL(ISNULL(MD.ADBranchID, ADR.ADBranchID), B.BranchID) BranchID,
		BPB.BranchName
	from
	(
		select EBIID, ExportLocalBillNo BillNo, MasterDocID, BranchID from EFA..LocalExportBillInitiationMaster WITH(NOLOCK) where EBIID = @EBIID
		Union All
		select EBIID, ExportBillNo, MasterDocID, BranchID from EFA..ExportBillInitiationMaster WITH(NOLOCK) where EBIID = @EBIID
	) B
		Left Join EFA..MasterDoc MD WITH(NOLOCK) ON MD.MasterDocID = B.MasterDocID
		Left Join EFA..LCAdvisingRegister ADR WITH(NOLOCK) ON ADR.LCReceiveID = ISNULL(MD.LCReceiveID, B.MasterDocID)
		Left Join SystemManager..BankProfileBranch BPB WITH(NOLOCK) ON BPB.BranchID = ISNULL(ISNULL(MD.ADBranchID, ADR.ADBranchID), B.BranchID)

Rollback Transaction   -- change to: Commit Transaction
GO
