USE EFA
GO

CREATE OR ALTER PROC [dbo].[SpCustomerProfilePBL]
	-- All three are optional: NULL, '' or 'All' = no filter
	@BranchID     NVARCHAR(50)  = NULL,   -- single branch
	@CustomerID   NVARCHAR(MAX) = NULL,   -- comma separated CustomerIDs
	@CustomerType NVARCHAR(10)  = NULL    -- 'EPZ' or 'Non-EPZ'
AS

-- EXEC SpCustomerProfilePBL
-- EXEC SpCustomerProfilePBL @BranchID = 'B01', @CustomerID = 'C001,C002', @CustomerType = 'EPZ'

-- How this works:
--   Some tables have many rows per customer (certificates, accounts, contacts...).
--   Joining them directly would repeat the customer row.
--   So we first build small helper tables with ONE row per customer
--   (many values are joined into one text using ', '), then join them normally.

BEGIN
	SET NOCOUNT ON;

	--------------------------------------------------------------------------------------
	-- STEP 1: Latest certificate per customer (ERC, BIN, IRC, BOND, TIN)
	--------------------------------------------------------------------------------------
	SELECT CustomerID, CertType, Number, ValidDate
	INTO #Cert
	FROM
	(
		SELECT
			RC.CustomerID,
			CertType = UPPER(LTRIM(RTRIM(EV.DisplayCode))),
			RC.Number,
			RC.ValidDate,
			-- RowNum = 1 means the newest certificate of that type
			RowNum = ROW_NUMBER() OVER (
				PARTITION BY RC.CustomerID, UPPER(LTRIM(RTRIM(EV.DisplayCode)))
				ORDER BY RC.DateAdded DESC, RC.CRROCID DESC
			)
		FROM SystemManager..CustomerRelatedRegistrationOrCertificate RC WITH(NOLOCK)
			INNER JOIN SystemManager..EntityFixedVariables EV WITH(NOLOCK) ON EV.EntityID = RC.CategoryID
		WHERE RC.IsDeleted = 0
		  AND UPPER(LTRIM(RTRIM(EV.DisplayCode))) IN ('ERC', 'BIN', 'IRC', 'BOND', 'TIN')
	) C
	WHERE C.RowNum = 1;


	--------------------------------------------------------------------------------------
	-- STEP 2: Account codes per customer, one column per account type
	--------------------------------------------------------------------------------------
	-- 2a. Give every account a short type name
	SELECT
		AC.CustomerID,
		AC.AccountCode,
		AccType = CASE
			WHEN EV.DisplayCode LIKE '%CD Current Diposit%'     OR EV.DisplayCode LIKE '%CD Current Deposit%'     OR EV.Description LIKE '%CD Current Diposit%'     OR EV.Description LIKE '%CD Current Deposit%'     THEN 'CD'
			WHEN EV.DisplayCode LIKE '%Special Notice Diposit%' OR EV.DisplayCode LIKE '%Special Notice Deposit%' OR EV.Description LIKE '%Special Notice Diposit%' OR EV.Description LIKE '%Special Notice Deposit%' THEN 'SND'
			WHEN EV.DisplayCode LIKE '%Over Draft%'             OR EV.Description LIKE '%Over Draft%'             THEN 'OD'
			WHEN EV.DisplayCode LIKE '%FC Held%'                OR EV.Description LIKE '%FC Held%'                THEN 'FCHeld'
			WHEN EV.DisplayCode LIKE '%ERQ FC Retention%'       OR EV.Description LIKE '%ERQ FC Retention%'       THEN 'ERQ'
			WHEN EV.DisplayCode LIKE '%ORQ 360 Account FC%'     OR EV.Description LIKE '%ORQ 360 Account FC%'     THEN 'ORQ'
			ELSE 'OTHER'
		END
	INTO #AccType
	FROM SystemManager..CustomerProfileAccounts AC WITH(NOLOCK)
		INNER JOIN SystemManager..EntityFixedVariables EV WITH(NOLOCK) ON EV.EntityID = AC.AccountTypeID
	WHERE AC.IsDeleted = 0;

	-- 2b. One row per customer; each column lists that type's accounts like "1001, 1002"
	SELECT
		CustomerID,
		CD     = STRING_AGG(CASE WHEN AccType = 'CD'     THEN AccountCode END, ', ') WITHIN GROUP (ORDER BY AccountCode),
		SND    = STRING_AGG(CASE WHEN AccType = 'SND'    THEN AccountCode END, ', ') WITHIN GROUP (ORDER BY AccountCode),
		OD     = STRING_AGG(CASE WHEN AccType = 'OD'     THEN AccountCode END, ', ') WITHIN GROUP (ORDER BY AccountCode),
		FCHeld = STRING_AGG(CASE WHEN AccType = 'FCHeld' THEN AccountCode END, ', ') WITHIN GROUP (ORDER BY AccountCode),
		ERQ    = STRING_AGG(CASE WHEN AccType = 'ERQ'    THEN AccountCode END, ', ') WITHIN GROUP (ORDER BY AccountCode),
		ORQ    = STRING_AGG(CASE WHEN AccType = 'ORQ'    THEN AccountCode END, ', ') WITHIN GROUP (ORDER BY AccountCode)
	INTO #Acc
	FROM #AccType
	WHERE AccType <> 'OTHER'
	GROUP BY CustomerID;


	--------------------------------------------------------------------------------------
	-- STEP 3: Registrations & certificates, one row per customer (values joined by ', ')
	--------------------------------------------------------------------------------------
	SELECT
		R.CustomerID,
		IssuingAuthority          = STRING_AGG(CAST(ISNULL(REPLACE(R.AuthorityIssuer, 'amp;', ''), '') AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY R.CRROCID),
		RegistrationCertificateNo = STRING_AGG(CAST(ISNULL(R.Number, '')  AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY R.CRROCID),
		AttachmentStatus          = STRING_AGG(CAST(ISNULL(F.FileName, '') AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY R.CRROCID),
		RefeNameDescription       = STRING_AGG(CAST(ISNULL(R.RefName, '') AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY R.CRROCID)
	INTO #Reg
	FROM SystemManager..CustomerRelatedRegistrationOrCertificate R WITH(NOLOCK)
		OUTER APPLY
		(
			-- first attached file of this registration (if any)
			SELECT TOP 1 FU.FileName
			FROM SystemManager..FileUploadInfo FU WITH(NOLOCK)
			WHERE FU.ReferenceID = R.CRROCID AND FU.IsDeleted = 0
		) F
	WHERE R.IsDeleted = 0
	GROUP BY R.CustomerID;


	--------------------------------------------------------------------------------------
	-- STEP 4: Other lien bank names & remarks, one row per customer
	--------------------------------------------------------------------------------------
	SELECT
		CPB.CustomerID,
		NameofOtherLienBank = STRING_AGG(CAST(CASE WHEN CPB.CategoryID = 'OtherBank' THEN ISNULL(CON.Name, '') END AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY CPB.CPBankID),
		Remarks             = STRING_AGG(CAST(NULLIF(CPB.Remarks, '') AS NVARCHAR(MAX)), ', ')                                                 WITHIN GROUP (ORDER BY CPB.CPBankID)
	INTO #Bank
	FROM SystemManager..CustomerProfileBanks CPB WITH(NOLOCK)
		LEFT JOIN SystemManager..Contacts CON WITH(NOLOCK) ON CON.Code = CPB.BankID
	WHERE CPB.IsDeleted = 0
	GROUP BY CPB.CustomerID;


	--------------------------------------------------------------------------------------
	-- STEP 5: Contact persons, one row per customer
	--------------------------------------------------------------------------------------
	SELECT
		P.CustomerID,
		ContactName = STRING_AGG(CAST(ISNULL(P.Name, '')        AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY P.CPCPID),
		Designation = STRING_AGG(CAST(ISNULL(P.Designation, '') AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY P.CPCPID),
		Email       = STRING_AGG(CAST(ISNULL(P.Email, '')       AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY P.CPCPID),
		PhoneNo     = STRING_AGG(CAST(ISNULL(P.PhoneNo, '')     AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY P.CPCPID)
	INTO #Contact
	FROM SystemManager..CustomerProfileContactPerson P WITH(NOLOCK)
	WHERE P.IsDeleted = 0
	GROUP BY P.CustomerID;


	--------------------------------------------------------------------------------------
	-- STEP 6: Final report - plain joins, one row per customer
	--------------------------------------------------------------------------------------
	SELECT
		SlNo = ROW_NUMBER() OVER (ORDER BY CP.CustomerName ASC, CP.CustomerID),

		-- Customer & branch
		CP.CustomerID,
		CP.CIF,
		CP.CustomerName,
		BPB.BranchID,
		BPB.BranchName,
		CP.FactoryAddress,

		-- ERC
		ERCNo           = ERC.Number,
		ERCExpiryDate   = ERC.ValidDate,
		ERCExpiryStatus = CASE WHEN ERC.CustomerID IS NULL THEN NULL
							   WHEN CAST(ERC.ValidDate AS DATE) < CAST(GETDATE() AS DATE) THEN 'Expired'
							   ELSE 'Lived' END,

		-- BIN
		BINNo           = BIN.Number,
		BINExpiryDate   = BIN.ValidDate,
		BINExpiryStatus = CASE WHEN BIN.CustomerID IS NULL THEN NULL
							   WHEN CAST(BIN.ValidDate AS DATE) < CAST(GETDATE() AS DATE) THEN 'Expired'
							   ELSE 'Lived' END,

		-- IRC
		IRCNo           = IRC.Number,
		IRCExpiryDate   = IRC.ValidDate,
		IRCExpiryStatus = CASE WHEN IRC.CustomerID IS NULL THEN NULL
							   WHEN CAST(IRC.ValidDate AS DATE) < CAST(GETDATE() AS DATE) THEN 'Expired'
							   ELSE 'Lived' END,

		-- BOND
		BONDNo           = BOND.Number,
		BONDExpiryDate   = BOND.ValidDate,
		BONDExpiryStatus = CASE WHEN BOND.CustomerID IS NULL THEN NULL
								WHEN CAST(BOND.ValidDate AS DATE) < CAST(GETDATE() AS DATE) THEN 'Expired'
								ELSE 'Lived' END,

		-- TIN
		TINNo = TIN.Number,

		-- Accounts (comma separated)
		ACC.CD,
		ACC.SND,
		ACC.OD,
		ACC.FCHeld,
		ACC.ERQ,
		ACC.ORQ,

		-- Registrations & certificates (comma separated)
		REG.IssuingAuthority,
		REG.RegistrationCertificateNo,
		REG.AttachmentStatus,
		REG.RefeNameDescription,

		-- Other lien bank & remarks (comma separated)
		BNK.NameofOtherLienBank,
		BNK.Remarks,

		-- Contact persons (comma separated)
		CT.ContactName,
		CT.Designation,
		CT.Email,
		CT.PhoneNo,

		-- Customer type & margin pool
		MarginType   = CASE WHEN ISNULL(CP.IsDeemed, 0) = 0 THEN 'No Pool' ELSE 'Single Pool' END,
		CustomerType = CASE WHEN ISNULL(CP.IsUsed, 0)   = 0 THEN 'Non-EPZ' ELSE 'EPZ' END

	FROM SystemManager..CustomerProfileMaster CP WITH(NOLOCK)
		-- Default branch (OUTER APPLY TOP 1 keeps it to one branch per customer)
		OUTER APPLY
		(
			SELECT TOP 1 B.BranchID, B.BranchName
			FROM SystemManager..CustomerBranchMap BM WITH(NOLOCK)
				INNER JOIN SystemManager..BankProfileBranch B WITH(NOLOCK) ON B.BranchID = BM.BranchID
			WHERE BM.CustomerID = CP.CustomerID AND BM.IsDefault = 1
			ORDER BY B.BranchName
		) BPB
		LEFT JOIN #Cert    ERC  ON ERC.CustomerID  = CP.CustomerID AND ERC.CertType  = 'ERC'
		LEFT JOIN #Cert    BIN  ON BIN.CustomerID  = CP.CustomerID AND BIN.CertType  = 'BIN'
		LEFT JOIN #Cert    IRC  ON IRC.CustomerID  = CP.CustomerID AND IRC.CertType  = 'IRC'
		LEFT JOIN #Cert    BOND ON BOND.CustomerID = CP.CustomerID AND BOND.CertType = 'BOND'
		LEFT JOIN #Cert    TIN  ON TIN.CustomerID  = CP.CustomerID AND TIN.CertType  = 'TIN'
		LEFT JOIN #Acc     ACC  ON ACC.CustomerID  = CP.CustomerID
		LEFT JOIN #Reg     REG  ON REG.CustomerID  = CP.CustomerID
		LEFT JOIN #Bank    BNK  ON BNK.CustomerID  = CP.CustomerID
		LEFT JOIN #Contact CT   ON CT.CustomerID   = CP.CustomerID
	WHERE CP.IsDeleted = 0
	  AND (ISNULL(@BranchID, 'All') IN ('', 'All') OR BPB.BranchID = @BranchID)
	  AND (ISNULL(@CustomerID, 'All') = '' OR CHARINDEX(',All,', ',' + ISNULL(@CustomerID, 'All') + ',') > 0
	       -- CHARINDEX instead of STRING_SPLIT: works on any database compatibility level
	       OR CHARINDEX(',' + CP.CustomerID + ',', ',' + @CustomerID + ',') > 0)
	  AND (ISNULL(@CustomerType, 'All') IN ('', 'All')
	       OR @CustomerType = CASE WHEN ISNULL(CP.IsUsed, 0) = 0 THEN 'Non-EPZ' ELSE 'EPZ' END)
	ORDER BY CP.CustomerName ASC, CP.CustomerID;

	-- Clean up temp tables
	DROP TABLE #Cert;
	DROP TABLE #AccType;
	DROP TABLE #Acc;
	DROP TABLE #Reg;
	DROP TABLE #Bank;
	DROP TABLE #Contact;
END
GO
