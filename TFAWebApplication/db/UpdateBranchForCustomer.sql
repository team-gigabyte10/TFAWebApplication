USE EFA
GO

-- Set the LC issuing branch (ADBranchID) to OBPB/25/5 for customer CPM/23/3.
-- The Statement of Overdue Accepted Bills report takes the branch from
--   ISNULL(GroupLC.ADBranchID, BBLCRequestMaster.ADBranchID),
-- so both tables are updated for this customer.
-- Run step 1 first and check the rows. Step 2 runs in a transaction: it ends with ROLLBACK.
-- Change ROLLBACK to COMMIT only after you check the counts.

Declare @CustomerID Varchar(50) = 'CPM/23/3'
Declare @BranchID   Varchar(50) = 'OBPB/25/5'

-- Step 1: check that the branch exists, and see the rows that will change
select BranchID, BranchName from SystemManager..BankProfileBranch WITH(NOLOCK) where BranchID = @BranchID

select 'GroupLC' TableName, GroupSysID Id, ADBranchID OldBranchID
from EFA..GroupLC WITH(NOLOCK)
where CustomerID = @CustomerID and ISNULL(ADBranchID, '') <> @BranchID

select 'BBLCRequestMaster' TableName, BBLCID Id, ADBranchID OldBranchID
from EFA..BBLCRequestMaster WITH(NOLOCK)
where CustomerID = @CustomerID and ISNULL(ADBranchID, '') <> @BranchID

-- Step 2: update
Begin Transaction

	update EFA..GroupLC
	set ADBranchID = @BranchID
	where CustomerID = @CustomerID and ISNULL(ADBranchID, '') <> @BranchID

	Print 'GroupLC rows updated: ' + CAST(@@ROWCOUNT As Varchar(20))

	update EFA..BBLCRequestMaster
	set ADBranchID = @BranchID
	where CustomerID = @CustomerID and ISNULL(ADBranchID, '') <> @BranchID

	Print 'BBLCRequestMaster rows updated: ' + CAST(@@ROWCOUNT As Varchar(20))

Rollback Transaction   -- change to: Commit Transaction
GO
