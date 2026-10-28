using System.Data;
using Microsoft.Reporting.NETCore;
using TFAWebApplication.Models.Reports;

namespace TFAWebApplication.Services
{
    public class ReportService : IReportService
    {
        private readonly IWebHostEnvironment _environment;
        private readonly ILcAdvisingDataService _dataService;

        public ReportService(IWebHostEnvironment environment, ILcAdvisingDataService dataService)
        {
            _environment = environment;
            _dataService = dataService;
        }

        public async Task<byte[]> RenderLcAdvisingReportAsync(
            string format,
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? currency = null,
            string? status = null)
        {
            // Resolve LCAdvisingRegisterPBL.rdl template path
            var rdlPath = Path.Combine(_environment.ContentRootPath, "Reports", "LCAdvisingRegisterPBL.rdl");
            if (!File.Exists(rdlPath))
            {
                rdlPath = Path.Combine(AppContext.BaseDirectory, "Reports", "LCAdvisingRegisterPBL.rdl");
            }

            if (!File.Exists(rdlPath))
            {
                throw new FileNotFoundException($"RDL Report template not found at {rdlPath}");
            }

            using var localReport = new LocalReport();
            using (var reportDefinitionStream = File.OpenRead(rdlPath))
            {
                localReport.LoadReportDefinition(reportDefinitionStream);
            }

            // Fetch report data
            var (advisingItems, _, _) = await _dataService.GetAdvisingRegisterDataAsync(fromDate, toDate, branch, currency, status);
            var companyItems = await _dataService.GetCompanyInfoAsync();

            // Bind DsCompanyInfo
            var companyTable = CreateCompanyDataTable(companyItems);
            localReport.DataSources.Add(new ReportDataSource("DsCompanyInfo", companyTable));

            // Bind DataSet1
            var advisingTable = CreateAdvisingDataTable(advisingItems);
            localReport.DataSources.Add(new ReportDataSource("DataSet1", advisingTable));

            // Bind Parameters
            var parameters = new List<ReportParameter>
            {
                new ReportParameter("FromDate", fromDate.ToString("yyyy-MM-dd")),
                new ReportParameter("ToDate", toDate.ToString("yyyy-MM-dd"))
            };
            localReport.SetParameters(parameters);

            // Render format selection
            var upperFormat = format.ToUpperInvariant();
            if (upperFormat is "PNG" or "IMAGE")
            {
                var pngDeviceInfo = "<DeviceInfo><OutputFormat>PNG</OutputFormat><DpiX>150</DpiX><DpiY>150</DpiY></DeviceInfo>";
                return localReport.Render("IMAGE", pngDeviceInfo);
            }

            var renderFormat = upperFormat switch
            {
                "PDF" => "PDF",
                "EXCEL" or "XLSX" or "EXCELOPENXML" => "EXCELOPENXML",
                "WORD" or "DOCX" or "WORDOPENXML" => "WORDOPENXML",
                _ => "PDF"
            };

            return localReport.Render(renderFormat);
        }

        public string GetContentType(string format)
        {
            return format.ToUpperInvariant() switch
            {
                "PDF" => "application/pdf",
                "EXCEL" or "XLSX" or "EXCELOPENXML" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "WORD" or "DOCX" or "WORDOPENXML" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "IMAGE" or "PNG" => "image/png",
                _ => "application/pdf"
            };
        }

        public string GetFileExtension(string format)
        {
            return format.ToUpperInvariant() switch
            {
                "PDF" => "pdf",
                "EXCEL" or "XLSX" or "EXCELOPENXML" => "xlsx",
                "WORD" or "DOCX" or "WORDOPENXML" => "docx",
                "IMAGE" or "PNG" => "png",
                _ => "pdf"
            };
        }

        private static DataTable CreateCompanyDataTable(IEnumerable<CompanyInfoItem> items)
        {
            var dt = new DataTable("DsCompanyInfo");
            dt.Columns.Add("GroupCompanyID", typeof(string));
            dt.Columns.Add("GroupCompanyName", typeof(string));
            dt.Columns.Add("ContactPerson", typeof(string));
            dt.Columns.Add("Address", typeof(string));

            foreach (var item in items)
            {
                dt.Rows.Add(item.GroupCompanyID, item.GroupCompanyName, item.ContactPerson, item.Address);
            }

            return dt;
        }

        private static DataTable CreateAdvisingDataTable(IEnumerable<LcAdvisingRegisterItem> items)
        {
            var dt = new DataTable("DataSet1");

            dt.Columns.Add("ADBranchName", typeof(string));
            dt.Columns.Add("NonADBranchName", typeof(string));
            dt.Columns.Add("AdvisingNumber", typeof(string));
            dt.Columns.Add("AdvisingDate", typeof(DateTime));
            dt.Columns.Add("TransactionRef", typeof(string));
            dt.Columns.Add("ExportLCNo", typeof(string));
            dt.Columns.Add("LCType", typeof(string));
            dt.Columns.Add("BBLCSCNumber", typeof(string));
            dt.Columns.Add("LCSubType", typeof(string));
            dt.Columns.Add("LCSubTypeDescription", typeof(string));
            dt.Columns.Add("TenorType", typeof(string));
            dt.Columns.Add("Tenor", typeof(string));
            dt.Columns.Add("TenorDescription", typeof(string));
            dt.Columns.Add("IssueDate", typeof(DateTime));
            dt.Columns.Add("Currency", typeof(string));
            dt.Columns.Add("Amount", typeof(decimal));
            dt.Columns.Add("EquivalentinUSD", typeof(decimal));
            dt.Columns.Add("ExchangeRate", typeof(decimal));
            dt.Columns.Add("EquivalentinBDT", typeof(decimal));
            dt.Columns.Add("ShipmentDate", typeof(DateTime));
            dt.Columns.Add("ExpiryDate", typeof(DateTime));
            dt.Columns.Add("Tolerance", typeof(decimal));
            dt.Columns.Add("LiabRevDate", typeof(int));
            dt.Columns.Add("ClosingDate", typeof(DateTime));
            dt.Columns.Add("Commodity", typeof(string));
            dt.Columns.Add("IssueBank", typeof(string));
            dt.Columns.Add("IssueBranch", typeof(string));
            dt.Columns.Add("CustomerNonCustomer", typeof(string));
            dt.Columns.Add("Benificiary", typeof(string));
            dt.Columns.Add("CustomerID", typeof(string));
            dt.Columns.Add("CustomerType", typeof(string));
            dt.Columns.Add("Applicant", typeof(string));
            dt.Columns.Add("ApplicantsCountry", typeof(string));
            dt.Columns.Add("JobNumber", typeof(int));
            dt.Columns.Add("R06Reference", typeof(int));
            dt.Columns.Add("InputterName", typeof(string));
            dt.Columns.Add("InputTime", typeof(DateTime));
            dt.Columns.Add("AuthorisedBy", typeof(string));
            dt.Columns.Add("AuthTime", typeof(DateTime));
            dt.Columns.Add("ChargeRealizationStatus", typeof(int));
            dt.Columns.Add("ChargeAmt", typeof(int));
            dt.Columns.Add("ChargeDebAcc", typeof(int));
            dt.Columns.Add("IssuingBanksBIC", typeof(int));
            dt.Columns.Add("AdvisingBanksBIC", typeof(int));
            dt.Columns.Add("MessageType", typeof(string));
            dt.Columns.Add("IssuingBankBranchAddress", typeof(string));
            dt.Columns.Add("IssuingBankBranchEmail", typeof(string));
            dt.Columns.Add("IssuingBankAddress", typeof(string));
            dt.Columns.Add("CustomerId", typeof(string));
            dt.Columns.Add("WaiverCharge", typeof(decimal));
            dt.Columns.Add("TransferableStatus", typeof(string));
            dt.Columns.Add("CMTAmount", typeof(decimal));
            dt.Columns.Add("CMTPercent", typeof(decimal));
            dt.Columns.Add("ADBranchID", typeof(string));
            dt.Columns.Add("LCIssuingBankSWIFTCode", typeof(string));
            dt.Columns.Add("ClosingDate1", typeof(DateTime));
            dt.Columns.Add("IssueingBankId", typeof(string));
            dt.Columns.Add("ChargeDebitAccount", typeof(decimal));
            dt.Columns.Add("AdvisingBankName", typeof(string));
            dt.Columns.Add("ChargeStatus", typeof(string));
            dt.Columns.Add("BICodAdvisingBank", typeof(string));
            dt.Columns.Add("ADCodeofIssuingBankBranch", typeof(string));
            dt.Columns.Add("CountryOfLCIssuingBank", typeof(string));
            dt.Columns.Add("RReference", typeof(string));
            dt.Columns.Add("LCExpiryPlace", typeof(string));
            dt.Columns.Add("FirstBeneficiaryName", typeof(string));
            dt.Columns.Add("AvailablewithBankID", typeof(string));
            dt.Columns.Add("FirstBeneficiaryCountry", typeof(string));
            dt.Columns.Add("TransferringFirstAdvisingBankName", typeof(string));
            dt.Columns.Add("AvailableWithBank1", typeof(string));
            dt.Columns.Add("CountryOfTransferringBank", typeof(string));
            dt.Columns.Add("AdviseThruBank1", typeof(string));
            dt.Columns.Add("RMName", typeof(string));
            dt.Columns.Add("ModeofTransport", typeof(string));
            dt.Columns.Add("UnitPrice1", typeof(decimal));
            dt.Columns.Add("TBRM", typeof(string));
            dt.Columns.Add("LiabilityReversalDate", typeof(DateTime));
            dt.Columns.Add("LCAdvisingStatus", typeof(string));
            dt.Columns.Add("PortOfLoading", typeof(string));
            dt.Columns.Add("LienStatus", typeof(string));
            dt.Columns.Add("PortOfDestination", typeof(string));
            dt.Columns.Add("Remarks", typeof(string));
            dt.Columns.Add("PartShipment", typeof(string));
            dt.Columns.Add("Transhipment", typeof(string));
            dt.Columns.Add("PresentationDescription", typeof(string));
            dt.Columns.Add("DraweeBankID", typeof(string));
            dt.Columns.Add("DraweeName", typeof(string));

            foreach (var item in items)
            {
                dt.Rows.Add(
                    (object?)item.ADBranchName ?? DBNull.Value,
                    (object?)item.NonADBranchName ?? DBNull.Value,
                    (object?)item.AdvisingNumber ?? DBNull.Value,
                    (object?)item.AdvisingDate ?? DBNull.Value,
                    (object?)item.TransactionRef ?? DBNull.Value,
                    (object?)item.ExportLCNo ?? DBNull.Value,
                    (object?)item.LCType ?? DBNull.Value,
                    (object?)item.BBLCSCNumber ?? DBNull.Value,
                    (object?)item.LCSubType ?? DBNull.Value,
                    (object?)item.LCSubTypeDescription ?? DBNull.Value,
                    (object?)item.TenorType ?? DBNull.Value,
                    (object?)item.Tenor ?? DBNull.Value,
                    (object?)item.TenorDescription ?? DBNull.Value,
                    (object?)item.IssueDate ?? DBNull.Value,
                    (object?)item.Currency ?? DBNull.Value,
                    item.Amount,
                    item.EquivalentinUSD,
                    item.ExchangeRate,
                    item.EquivalentinBDT,
                    (object?)item.ShipmentDate ?? DBNull.Value,
                    (object?)item.ExpiryDate ?? DBNull.Value,
                    (object?)item.Tolerance ?? DBNull.Value,
                    (object?)item.LiabRevDate ?? DBNull.Value,
                    (object?)item.ClosingDate ?? DBNull.Value,
                    (object?)item.Commodity ?? DBNull.Value,
                    (object?)item.IssueBank ?? DBNull.Value,
                    (object?)item.IssueBranch ?? DBNull.Value,
                    (object?)item.CustomerNonCustomer ?? DBNull.Value,
                    (object?)item.Benificiary ?? DBNull.Value,
                    (object?)item.CustomerID ?? DBNull.Value,
                    (object?)item.CustomerType ?? DBNull.Value,
                    (object?)item.Applicant ?? DBNull.Value,
                    (object?)item.ApplicantsCountry ?? DBNull.Value,
                    (object?)item.JobNumber ?? DBNull.Value,
                    (object?)item.R06Reference ?? DBNull.Value,
                    (object?)item.InputterName ?? DBNull.Value,
                    (object?)item.InputTime ?? DBNull.Value,
                    (object?)item.AuthorisedBy ?? DBNull.Value,
                    (object?)item.AuthTime ?? DBNull.Value,
                    (object?)item.ChargeRealizationStatus ?? DBNull.Value,
                    (object?)item.ChargeAmt ?? DBNull.Value,
                    (object?)item.ChargeDebAcc ?? DBNull.Value,
                    (object?)item.IssuingBanksBIC ?? DBNull.Value,
                    (object?)item.AdvisingBanksBIC ?? DBNull.Value,
                    (object?)item.MessageType ?? DBNull.Value,
                    (object?)item.IssuingBankBranchAddress ?? DBNull.Value,
                    (object?)item.IssuingBankBranchEmail ?? DBNull.Value,
                    (object?)item.IssuingBankAddress ?? DBNull.Value,
                    (object?)item.CustomerId ?? DBNull.Value,
                    (object?)item.WaiverCharge ?? DBNull.Value,
                    (object?)item.TransferableStatus ?? DBNull.Value,
                    (object?)item.CMTAmount ?? DBNull.Value,
                    (object?)item.CMTPercent ?? DBNull.Value,
                    (object?)item.ADBranchID ?? DBNull.Value,
                    (object?)item.LCIssuingBankSWIFTCode ?? DBNull.Value,
                    (object?)item.ClosingDate1 ?? DBNull.Value,
                    (object?)item.IssueingBankId ?? DBNull.Value,
                    (object?)item.ChargeDebitAccount ?? DBNull.Value,
                    (object?)item.AdvisingBankName ?? DBNull.Value,
                    (object?)item.ChargeStatus ?? DBNull.Value,
                    (object?)item.BICodAdvisingBank ?? DBNull.Value,
                    (object?)item.ADCodeofIssuingBankBranch ?? DBNull.Value,
                    (object?)item.CountryOfLCIssuingBank ?? DBNull.Value,
                    (object?)item.RReference ?? DBNull.Value,
                    (object?)item.LCExpiryPlace ?? DBNull.Value,
                    (object?)item.FirstBeneficiaryName ?? DBNull.Value,
                    (object?)item.AvailablewithBankID ?? DBNull.Value,
                    (object?)item.FirstBeneficiaryCountry ?? DBNull.Value,
                    (object?)item.TransferringFirstAdvisingBankName ?? DBNull.Value,
                    (object?)item.AvailableWithBank1 ?? DBNull.Value,
                    (object?)item.CountryOfTransferringBank ?? DBNull.Value,
                    (object?)item.AdviseThruBank1 ?? DBNull.Value,
                    (object?)item.RMName ?? DBNull.Value,
                    (object?)item.ModeofTransport ?? DBNull.Value,
                    (object?)item.UnitPrice1 ?? DBNull.Value,
                    (object?)item.TBRM ?? DBNull.Value,
                    (object?)item.LiabilityReversalDate ?? DBNull.Value,
                    (object?)item.LCAdvisingStatus ?? DBNull.Value,
                    (object?)item.PortOfLoading ?? DBNull.Value,
                    (object?)item.LienStatus ?? DBNull.Value,
                    (object?)item.PortOfDestination ?? DBNull.Value,
                    (object?)item.Remarks ?? DBNull.Value,
                    (object?)item.PartShipment ?? DBNull.Value,
                    (object?)item.Transhipment ?? DBNull.Value,
                    (object?)item.PresentationDescription ?? DBNull.Value,
                    (object?)item.DraweeBankID ?? DBNull.Value,
                    (object?)item.DraweeName ?? DBNull.Value
                );
            }

            return dt;
        }
    }
}
