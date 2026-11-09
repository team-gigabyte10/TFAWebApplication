USE [EFA]
GO
/****** Object:  StoredProcedure [dbo].[spStatementofOverdueAcceptedBillsLocalReceivablesPBL] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[spStatementofOverdueAcceptedBillsLocalReceivablesPBL] 
	@AsOnDate date
AS
	
	BEGIN  
	SET NOCOUNT ON;

	Select 
		Appli.Name ApplicantName,
		MD.LCNo LCNumber,
		MD.DateOfLien LCDate,
		MD.Currency Currency,
		LEB.ExportLocalBillAmount BillAmount,
		EBM.MaturityDate MaturityDate,
		DATEDIFF(DAY, EBM.MaturityDate, @AsOnDate) OverdueDays,
		Issue.Name IssuingBank,
		IssueBranch.Name IssuingBranch,
		LEB.ExportLocalBillNo OurBillReference,
		CPM.CustomerName BeneficiaryName,
		LEB.Remarks
	FROM LocalExportBillInitiationMaster LEB with(nolock)
		LEFT JOIN SystemManager..CustomerProfileMaster CPM with(nolock) ON CPM.CustomerID = LEB.CustomerCode
		LEFT JOIN MasterDoc MD with(nolock) ON MD.MasterDocID = LEB.MasterDocID
		LEFT JOIN LCAdvisingRegister Advi with(nolock) ON Advi.LCReceiveID = MD.LCReceiveID
		LEFT JOIN SystemManager..Contacts Issue with(nolock) ON Issue.Code = Advi.BankID
		LEFT JOIN SystemManager..Contacts IssueBranch with(nolock) ON IssueBranch.Code = Advi.BankBranchID
		LEFT JOIN ExportBillMonitoring EBM with(nolock) ON EBM.EBIID = LEB.EBIID
		LEFT JOIN SystemManager..Contacts Appli with(nolock) ON Appli.Code = MD.Applicant
	WHERE LEB.IsDeleted = 0 
		AND ISNULL(LEB.IsCancelled, 0) = 0 
		AND LEB.ExportLocalBillNo IS NOT NULL
		AND DATEDIFF(DAY, EBM.MaturityDate, @AsOnDate) > 30 
END
GO
