using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Reporting.NETCore;
using TFAWebApplication.Models.Reports;

namespace TFAWebApplication.Services
{
    public class PcRegisterService : IPcRegisterService
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<PcRegisterService> _logger;
        private readonly IWebHostEnvironment _environment;
        private readonly ILcAdvisingDataService _companyService;

        public PcRegisterService(
            IConfiguration configuration,
            ILogger<PcRegisterService> logger,
            IWebHostEnvironment environment,
            ILcAdvisingDataService companyService)
        {
            _configuration = configuration;
            _logger = logger;
            _environment = environment;
            _companyService = companyService;
        }

        public async Task<(List<PcRegisterItem> Items, bool IsSuccess, string? ErrorMessage)> GetDataAsync(
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? customer = null)
        {
            var connectionString = _configuration.GetConnectionString("EfaConnection")
                ?? "Server=192.168.1.3\\PBLTEST;Database=EFA;User Id=sa;Password=sa;TrustServerCertificate=True;Connect Timeout=15;";

            try
            {
                using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync();

                using var command = new SqlCommand("spRPT_PCRegisterPBL", connection)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 180
                };
                command.Parameters.Add(new SqlParameter("@FromDate", SqlDbType.Date) { Value = fromDate.Date });
                command.Parameters.Add(new SqlParameter("@ToDate", SqlDbType.Date) { Value = toDate.Date });

                var items = new List<PcRegisterItem>();
                using var reader = await command.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    items.Add(new PcRegisterItem
                    {
                        BranchName = Str(reader, "BranchName"),
                        CustomerName = Str(reader, "CustomerName"),
                        DisburseDate = Date(reader, "DisburseDate"),
                        PCNumber = Str(reader, "PCNumber"),
                        GroupRefNo = Str(reader, "GroupRefNo"),
                        LoanCurrency = Str(reader, "LoanCurrency"),
                        InterestRate = Dec(reader, "InterestRate"),
                        ExchangeRate = Dec(reader, "ExchangeRate"),
                        PCCondition = Str(reader, "PCCondition"),
                        PctOfPCDisbursement = Dec(reader, "PctOfPCDisbursement"),
                        LoanAmount = Dec(reader, "LoanAmount"),
                        MaturityDate = Date(reader, "MaturityDate"),
                        LoanOutAmt = Dec(reader, "LoanOutAmt"),
                        AdjustedAmount = Dec(reader, "AdjustedAmount"),
                        AdjustedDate = Date(reader, "AdjustedDate"),
                        LastModifiedBy = Str(reader, "LastModifiedBy")
                    });
                }

                var filtered = items.AsEnumerable();
                if (!string.IsNullOrWhiteSpace(branch) && branch != "All")
                {
                    filtered = filtered.Where(x => string.Equals(x.BranchName, branch, StringComparison.OrdinalIgnoreCase));
                }
                if (!string.IsNullOrWhiteSpace(customer) && customer != "All")
                {
                    filtered = filtered.Where(x => string.Equals(x.CustomerName, customer, StringComparison.OrdinalIgnoreCase));
                }

                return (filtered.ToList(), true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Query to [EFA].[spRPT_PCRegisterPBL] failed: {Message}", ex.Message);
                return (new List<PcRegisterItem>(), false, ex.Message);
            }
        }

        public async Task<byte[]> RenderAsync(
            string format,
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? customer = null)
        {
            var rdlPath = Path.Combine(_environment.ContentRootPath, "Reports", "PCRegisterPBL.rdl");
            if (!File.Exists(rdlPath))
            {
                rdlPath = Path.Combine(AppContext.BaseDirectory, "Reports", "PCRegisterPBL.rdl");
            }
            if (!File.Exists(rdlPath))
            {
                throw new FileNotFoundException($"RDL Report template not found at {rdlPath}");
            }

            using var localReport = new LocalReport();
            using (var stream = File.OpenRead(rdlPath))
            {
                localReport.LoadReportDefinition(stream);
            }

            var (items, isSuccess, error) = await GetDataAsync(fromDate, toDate, branch, customer);
            if (!isSuccess)
            {
                throw new InvalidOperationException(error);
            }
            var companyItems = await _companyService.GetCompanyInfoAsync();

            localReport.DataSources.Add(new ReportDataSource("DsCompanyInfo", CreateCompanyTable(companyItems)));
            localReport.DataSources.Add(new ReportDataSource("DataSet1", CreateDataTable(items)));
            localReport.SetParameters(new List<ReportParameter>
            {
                new ReportParameter("FromDate", fromDate.ToString("yyyy-MM-dd")),
                new ReportParameter("ToDate", toDate.ToString("yyyy-MM-dd"))
            });

            var upper = format.ToUpperInvariant();
            if (upper is "PNG" or "IMAGE")
            {
                return localReport.Render("IMAGE", "<DeviceInfo><OutputFormat>PNG</OutputFormat><DpiX>150</DpiX><DpiY>150</DpiY></DeviceInfo>");
            }

            var renderFormat = upper switch
            {
                "EXCEL" or "XLSX" or "EXCELOPENXML" => "EXCELOPENXML",
                "WORD" or "DOCX" or "WORDOPENXML" => "WORDOPENXML",
                _ => "PDF"
            };
            return localReport.Render(renderFormat);
        }

        private static DataTable CreateCompanyTable(IEnumerable<CompanyInfoItem> items)
        {
            var dt = new DataTable("DsCompanyInfo");
            dt.Columns.Add("GroupCompanyID", typeof(string));
            dt.Columns.Add("GroupCompanyName", typeof(string));
            dt.Columns.Add("ContactPerson", typeof(string));
            dt.Columns.Add("Address", typeof(string));
            foreach (var i in items)
            {
                dt.Rows.Add(i.GroupCompanyID, i.GroupCompanyName, i.ContactPerson, i.Address);
            }
            return dt;
        }

        private static DataTable CreateDataTable(IEnumerable<PcRegisterItem> items)
        {
            var dt = new DataTable("DataSet1");
            dt.Columns.Add("BranchName", typeof(string));
            dt.Columns.Add("CustomerName", typeof(string));
            dt.Columns.Add("DisburseDate", typeof(DateTime));
            dt.Columns.Add("PCNumber", typeof(string));
            dt.Columns.Add("GroupRefNo", typeof(string));
            dt.Columns.Add("LoanCurrency", typeof(string));
            dt.Columns.Add("InterestRate", typeof(decimal));
            dt.Columns.Add("ExchangeRate", typeof(decimal));
            dt.Columns.Add("PCCondition", typeof(string));
            dt.Columns.Add("PctOfPCDisbursement", typeof(decimal));
            dt.Columns.Add("LoanAmount", typeof(decimal));
            dt.Columns.Add("MaturityDate", typeof(DateTime));
            dt.Columns.Add("LoanOutAmt", typeof(decimal));
            dt.Columns.Add("AdjustedAmount", typeof(decimal));
            dt.Columns.Add("AdjustedDate", typeof(DateTime));
            dt.Columns.Add("LastModifiedBy", typeof(string));
            dt.Columns.Add("BranchID", typeof(string));
            dt.Columns.Add("CustomerID", typeof(string));

            foreach (var i in items)
            {
                dt.Rows.Add(
                    (object?)i.BranchName ?? DBNull.Value,
                    (object?)i.CustomerName ?? DBNull.Value,
                    (object?)i.DisburseDate ?? DBNull.Value,
                    (object?)i.PCNumber ?? DBNull.Value,
                    (object?)i.GroupRefNo ?? DBNull.Value,
                    (object?)i.LoanCurrency ?? DBNull.Value,
                    (object?)i.InterestRate ?? DBNull.Value,
                    (object?)i.ExchangeRate ?? DBNull.Value,
                    (object?)i.PCCondition ?? DBNull.Value,
                    (object?)i.PctOfPCDisbursement ?? DBNull.Value,
                    (object?)i.LoanAmount ?? DBNull.Value,
                    (object?)i.MaturityDate ?? DBNull.Value,
                    (object?)i.LoanOutAmt ?? DBNull.Value,
                    (object?)i.AdjustedAmount ?? DBNull.Value,
                    (object?)i.AdjustedDate ?? DBNull.Value,
                    (object?)i.LastModifiedBy ?? DBNull.Value,
                    DBNull.Value,
                    DBNull.Value);
            }
            return dt;
        }

        private static string? Str(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : r[col].ToString();
        private static DateTime? Date(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : Convert.ToDateTime(r[col]);
        private static decimal? Dec(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : Convert.ToDecimal(r[col]);
    }
}
