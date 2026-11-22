USE EFA
GO

/****** Object:  StoredProcedure [dbo].[LCAdvisingRegisterPBL] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[LCAdvisingRegisterPBL]
    @FromDate DATE,
    @ToDate DATE
AS
BEGIN
    -- Exec LCAdvisingRegisterPBL '2025-01-01','2025-10-01'
    DECLARE @USDRate NUMERIC(18,4)
    SELECT @USDRate = ConvertFactor 
    FROM [SystemManager]..CurrencyLatestRate WITH(NOLOCK) 
    WHERE CurrencyCode = 'USD' AND RateFor = 'BC SELLING'

    SELECT DISTINCT  
        ADbpb.BranchName AS ADBranchName,
        NonADbpb.BranchName AS NonADBranchName,
        scu.AdviceNo AS AdvisingNumber,
        scu.AdviceDate AS AdvisingDate,
        TransactionRef = LCAR.ExternalId,
        ExportLCNo = LCAR.LCNumber,
        LCAR.BBLCSCNumber,
        LCTYPE.DisplayCode AS LCType,
        LCSubType = SubLC.DisplayCode,
        LCSubTypeDescription = SubLC.Description,
        TenorType = TenorType.DisplayCode,
        Tenor = CASE 
                    WHEN ISNULL(MD.Tenor,0) > 0 AND ISNULL(MD.TenorType,'') <> '' THEN CAST(MD.Tenor AS VARCHAR(100)) + ' Days'
                    WHEN ISNULL(MD.TenorType,'') = '' AND ISNULL(MD.Tenor,0) = 0 THEN ''  
                    ELSE 'At Sight' 
                END,
        TenorDescription = ISNULL(TenorDes.Description, TenorDes.DisplayCode),
        IssueDate = lcar.IssueDate,
        Currency = lcar.Currency,
        Amount = lcar.LCAmount,
        EquivalentinUSD = (lcar.LCAmount * clr.ConvertFactor) / @USDRate,
        ExchangeRate = clr.ConvertFactor,
        EquivalentinBDT = lcar.LCAmount * clr.ConvertFactor,
        ShipmentDate = lcar.ShipmentDate,
        ExpiryDate = lcar.ExpiryDate,
        Tolerance = CASE WHEN LCAR.ToleranceNegative > 0 THEN LCAR.ToleranceNegative * -1 ELSE lcar.TolerancePositive END,
        LiabRevDate = NULL,
        ClosingDate = LCAR.ClosingDate,
        Commodity = Commodity.CommodityName,
        IssueBank = issueBank.Name,
        IssueBranch = issueBranch.Name,
        CustomerNonCustomer = CASE WHEN lcar.IsCustomerLC = 1 THEN 'Customer' ELSE 'Non-Customer' END,
        Benificiary = Beni.Name,
        CustomerID = CPM.CIF,
        CustomerType = COALESCE(
            NULLIF(Seg.DisplayCode, ''), 
            NULLIF(Seg.Description, ''), 
            NULLIF(CPM.BusinessUnit, ''), 
            CusType.Description, 
            CASE WHEN lcar.IsCustomerLC = 1 THEN 'Customer' ELSE 'Non-Customer' END
        ),
        Applicant = Applicant.Name,
        ApplicantsCountry = ApplicantCountry.CountryName,
        JobNumber = NULL,
        R06Reference = NULL,
        InputterName = ISNULL(lcar.AddedBy, lcar.MakeBy),
        InputTime = ISNULL(lcar.DateAdded, lcar.MakeDate),
        AuthorisedBy = lcar.CheckBy,
        AuthTime = lcar.CheckDate,
        ChargeRealizationStatus = NULL, 
        ChargeAmt = NULL,
        ChargeDebAcc = NULL,
        IssuingBanksBIC = NULL,
        AdvisingBanksBIC = NULL,
        MessageType = MSGTYPE.DisplayCode,
        IssuingBankBranchAddress = issueBranch.Officeaddress, 
        IssuingBankBranchEmail = issueBank.EmailNo,
        IssuingBankAddress = issueBank.Officeaddress,
        -----------NEW----------
        WaiverCharge = lcar.WaiverCharge,
        CMTAmount = lcar.CMTAmount,
        CMTPercent = lcar.CMTPercent,
        ClosingDate1 = lcar.ClosingDate,
        ChargeDebitAccount = lcar.ChargeDebitAccount,
        ChargeStatus = lcar.ChargeStatus,
        BICodAdvisingBank = lcar.BICodAdvisingBank,
        RReference = lcar.RReference,
        LCExpiryPlace = lcar.LCExpiryPlace,
        AvailablewithBankID = lcar.AvailablewithBankID,
        AvailableWithBank1 = lcar.AvailableWithBank1,
        AdviseThruBank1 = lcar.AdviseThruBank1,
        ModeofTransport = lcar.ModeofTransport,
        UnitPrice1 = lcar.UnitPrice1,
        LiabilityReversalDate = lcar.LiabilityReversalDate,
        PortOfLoading = lcar.PortOfLoading,
        PortOfDestination = lcar.PortOfDestination,
        PartShipment = lcar.Partshipment,
        Transhipment = lcar.Transhipment,

        PresentationDescription = lcar.PresentationDescription,
        DraweeBankID = lcar.DraweeBankID,
        DraweeName = lcar.DraweeName,
        AvailableWithBank = lcar.AvailableWithBank,
        AvailableBy = lcar.AvailableBy,
        AdviseThroughBankID = lcar.AdviseThroughBankID,
        ReimbursingBankID = lcar.ReimbursingBankID,
        ReimbursingBankName = lcar.ReimbursingBankName,
        ReqConfirmationParty = lcar.ReqConfirmationParty,
        ReqConfirmPartyName = lcar.ReqConfirmPartyName,
        Operation = lcar.Operation,
        LCAmountLCY = lcar.LCAmountLCY,
        UltimateBuyer = lcar.UltimateBuyer,
        BenefeciaryAccount = lcar.BenefeciaryAccount,
        LCTypeBB = lcar.LCTypeBB,
        UploadBB = lcar.UploadBB,
        Chargesfrom = lcar.Chargesfrom,
        ChargeDefaultAcct = lcar.ChargeDefaultAcct,
        SequenceofTotal = lcar.SequenceofTotal,
        EApplicableRules = lcar.EApplicableRules,
        aAIssuingBank = lcar.aAIssuingBank,
        ADIssuingBank = lcar.ADIssuingBank,
        ApplicantBank = lcar.ApplicantBank,
        CAddlAmountsCovered = lcar.CAddlAmountsCovered,
        MMixedPaymentDetails = lcar.MMixedPaymentDetails,
        PDeferredPaymentDetails = lcar.PDeferredPaymentDetails,
        APlaceofTakinginCharge = lcar.APlaceofTakinginCharge,
        BFinalDestination = lcar.BFinalDestination,
        DShipmentPeriod = lcar.DShipmentPeriod,
        ConfirmationInstructions = lcar.ConfirmationInstructions,
        InstructionstotheBank = lcar.InstructionstotheBank,
        aAAdviseThroughBank = lcar.aAAdviseThroughBank,
        aDAdviseThroughBank = lcar.aDAdviseThroughBank,
        ZSendertoReceiverInformatioin = lcar.ZSendertoReceiverInformatioin,
        RecordStatus = lcar.RecordStatus,
        DepartmentCode = lcar.DepartmentCode,
        AuditorCode = lcar.AuditorCode,
        AuditDateandTime = lcar.AuditDateandTime,
        CountryMakingPayment = lcar.CountryMakingPayment,
        DebitAmount = lcar.DebitAmount,
        DebitCurrency = lcar.DebitCurrency,
        ChargeCode = lcar.ChargeCode,
        PartyCharged = lcar.PartyCharged,
        TotalCharges = lcar.TotalCharges,
        TaxACCAmount = lcar.TaxACCAmount,
        DebitAccountNo = lcar.DebitAccountNo,
        ExportSection = lcar.ExportSection,
        ---------------END------------
        CASE WHEN LCAR.IsTransferable = 1 THEN 'Transferable' ELSE 'Not Transferable' END AS TransferableStatus,
        issueBranch.SwiftCode AS LCIssuingBankSWIFTCode,
        advisingBank.Name AS AdvisingBankName,
        issueBranch.AgentName AS ADCodeofIssuingBankBranch,
        issueBank.CountryID AS CountryOfLCIssuingBank,
        FBeni.Name AS FirstBeneficiaryName,
        FBeni.CountryID AS FirstBeneficiaryCountry,
        TransferringBank.Name AS TransferringFirstAdvisingBankName,
        TransferringBank.CountryID AS CountryOfTransferringBank,
        RM.EmployeeName AS RMName,
        '' AS TBRM,
        '' AS LCAdvisingStatus,
        CASE WHEN MD.LCReceiveID IS NOT NULL THEN 'Lined' ELSE '' END AS LienStatus,
        LCAR.Remarks AS Remarks,

        --For Mapping Non Mendatory Parameter
        CustomerId = LCAR.Customer,
        LCAR.ADBranchID,
        IssueingBankId = LCAR.BankID

    FROM 
        LCAdvisingRegister LCAR WITH(NOLOCK)
        LEFT JOIN LCScrutiny scu WITH(NOLOCK) ON scu.LCReceiveID = LCAR.LCReceiveID AND scu.IsDeleted = 0 AND scu.IsCancelled = 0
        LEFT JOIN MasterDoc MD WITH(NOLOCK) ON MD.LCReceiveID = LCAR.LCReceiveID AND md.IsDeleted = 0 AND md.IsCancelled = 0
        LEFT JOIN SystemManager..EntityFixedVariables MSGTYPE WITH(NOLOCK) ON MSGTYPE.EntityID = LCAR.MessageTypeID
        LEFT JOIN SystemManager..EntityFixedVariables TenorType WITH(NOLOCK) ON TenorType.EntityID = LCAR.TenorType
        LEFT JOIN SystemManager..EntityFixedVariables TenorDes WITH(NOLOCK) ON TenorDes.EntityID = LCAR.TenorDescription
        LEFT JOIN [SystemManager]..CommodityMaster Commodity WITH(NOLOCK) ON Commodity.CommodityMasterID = lcar.Commodity AND Commodity.IsDeleted = 0
        LEFT JOIN SystemManager..Contacts issueBank WITH(NOLOCK) ON issueBank.Code = LCAR.BankID
        LEFT JOIN SystemManager..CustomerProfileMaster CPM WITH(NOLOCK) ON CPM.CustomerID = LCAR.Customer
        LEFT JOIN SystemManager..Contacts Applicant WITH(NOLOCK) ON Applicant.Code = LCAR.Applicant
        LEFT JOIN SystemManager..Country ApplicantCountry WITH(NOLOCK) ON ApplicantCountry.CountryID = Applicant.CountryID
        LEFT JOIN SystemManager..Contacts Beni WITH(NOLOCK) ON RTRIM(LTRIM(Beni.Name)) = RTRIM(LTRIM(LCAR.Beneficiary))
        LEFT JOIN SystemManager..Contacts issueBranch WITH(NOLOCK) ON issueBranch.Code = LCAR.BankBranchID
        LEFT JOIN (
            SELECT B.BranchID, B.BranchName 
            FROM SystemManager..BankProfileBranch B
            INNER JOIN SystemManager..CustomerBranchMap C WITH(NOLOCK) ON B.BranchID = C.BranchID
        ) NonADbpb ON NonADbpb.BranchID = LCAR.BranchID
        LEFT JOIN (SELECT * FROM SystemManager..BankProfileBranch WHERE IsADCode = 1) ADbpb ON ADbpb.ADBranchID = LCAR.ADBranchID
        LEFT JOIN SystemManager..EntityFixedVariables LCTYPE WITH(NOLOCK) ON LCTYPE.EntityID = LCAR.LCTypeID
        LEFT JOIN SystemManager..EntityFixedVariables CusType WITH(NOLOCK) ON CusType.EntityID = LCAR.CustomerType
        LEFT JOIN SystemManager..EntityFixedVariables Seg WITH(NOLOCK) ON Seg.EntityID = CPM.SegmentID AND Seg.EntityTypeID = 'CSEG/17/1' AND Seg.IsDeleted = 0
        LEFT JOIN SystemManager..EntityFixedVariables SubLC WITH(NOLOCK) ON SubLC.EntityID = LCAR.LCSubTypeID
        LEFT JOIN [SystemManager]..CurrencyLatestRate clr WITH(NOLOCK) ON clr.CurrencyCode = lcar.Currency AND clr.RateFor = 'BC SELLING'
        LEFT JOIN SystemManager..t_Employee RM WITH(NOLOCK) ON RM.EmployeeCode = CPM.RMID
        LEFT JOIN SystemManager..Contacts TransferringBank WITH(NOLOCK) ON TransferringBank.Code = LCAR.TransferringBankID
        LEFT JOIN SystemManager..Contacts advisingBank WITH(NOLOCK) ON advisingBank.Code = LCAR.AdvisingBankID
        LEFT JOIN SystemManager..Contacts FBeni WITH(NOLOCK) ON FBeni.Code = LCAR.FirstBeneficiaryID
    WHERE
        CONVERT(DATE, LCAR.LCReceiveDate) BETWEEN @FromDate AND @ToDate  
        AND LCAR.IsDeleted = 0 
    ORDER BY AdviceNo DESC
END
GO
