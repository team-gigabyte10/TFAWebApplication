using System.Data;
using Microsoft.Data.SqlClient;
using TFAWebApplication.Models.Reports;

namespace TFAWebApplication.Services
{
    public class LcAdvisingDataService : ILcAdvisingDataService
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<LcAdvisingDataService> _logger;

        public LcAdvisingDataService(IConfiguration configuration, ILogger<LcAdvisingDataService> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public async Task<(List<LcAdvisingRegisterItem> Items, bool IsSuccess, string? ErrorMessage)> GetAdvisingRegisterDataAsync(
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? currency = null,
            string? status = null)
        {
            var connectionString = _configuration.GetConnectionString("EfaConnection")
                ?? "Server=192.168.1.3\\PBLTEST;Database=EFA;User Id=sa;Password=sa;TrustServerCertificate=True;Connect Timeout=15;";

            try
            {
                using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync();

                using var command = new SqlCommand("LCAdvisingRegisterPBL", connection)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 180
                };

                command.Parameters.Add(new SqlParameter("@FromDate", SqlDbType.Date) { Value = fromDate.Date });
                command.Parameters.Add(new SqlParameter("@ToDate", SqlDbType.Date) { Value = toDate.Date });

                var items = new List<LcAdvisingRegisterItem>();

                using var reader = await command.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    items.Add(MapReaderToItem(reader));
                }

                // Apply in-memory secondary filters if requested
                var filtered = items.AsEnumerable();
                if (!string.IsNullOrWhiteSpace(branch) && branch != "All")
                {
                    filtered = filtered.Where(x => string.Equals(x.ADBranchName, branch, StringComparison.OrdinalIgnoreCase));
                }
                if (!string.IsNullOrWhiteSpace(currency) && currency != "All")
                {
                    filtered = filtered.Where(x => string.Equals(x.Currency, currency, StringComparison.OrdinalIgnoreCase));
                }
                if (!string.IsNullOrWhiteSpace(status) && status != "All")
                {
                    filtered = filtered.Where(x => string.Equals(x.LCAdvisingStatus, status, StringComparison.OrdinalIgnoreCase));
                }

                return (filtered.ToList(), true, null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Live SQL Server query to [EFA].[LCAdvisingRegisterPBL] failed: {Message}", ex.Message);
                return (new List<LcAdvisingRegisterItem>(), false, ex.Message);
            }
        }

        public async Task<List<CompanyInfoItem>> GetCompanyInfoAsync()
        {
            var connectionString = _configuration.GetConnectionString("SystemManagerConnection")
                ?? _configuration.GetConnectionString("EfaConnection")
                ?? "Server=192.168.1.3\\PBLTEST;Database=SystemManager;User Id=sa;Password=sa;TrustServerCertificate=True;Connect Timeout=15;";

            try
            {
                using var connection = new SqlConnection(connectionString);
                await connection.OpenAsync();

                using var command = new SqlCommand("SELECT TOP 1 GroupCompanyID, GroupCompanyName, ContactPerson, Address FROM [SystemManager]..Company", connection)
                {
                    CommandType = CommandType.Text,
                    CommandTimeout = 15
                };

                using var reader = await command.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return new List<CompanyInfoItem>
                    {
                        new CompanyInfoItem
                        {
                            GroupCompanyID = reader["GroupCompanyID"]?.ToString() ?? string.Empty,
                            GroupCompanyName = reader["GroupCompanyName"]?.ToString() ?? string.Empty,
                            ContactPerson = reader["ContactPerson"]?.ToString() ?? string.Empty,
                            Address = reader["Address"]?.ToString() ?? string.Empty
                        }
                    };
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning("Live SQL query to [SystemManager]..Company failed: {Message}", ex.Message);
            }

            return new List<CompanyInfoItem>();
        }

        private static LcAdvisingRegisterItem MapReaderToItem(SqlDataReader reader)
        {
            var item = new LcAdvisingRegisterItem();
            var schema = reader.GetColumnSchema();
            var colNames = new HashSet<string>(schema.Select(s => s.ColumnName), StringComparer.OrdinalIgnoreCase);

            string? GetStr(string col) => colNames.Contains(col) && !reader.IsDBNull(reader.GetOrdinal(col)) ? reader[col].ToString() : null;
            DateTime? GetDate(string col) => colNames.Contains(col) && !reader.IsDBNull(reader.GetOrdinal(col)) ? Convert.ToDateTime(reader[col]) : null;
            decimal GetDec(string col) => colNames.Contains(col) && !reader.IsDBNull(reader.GetOrdinal(col)) ? Convert.ToDecimal(reader[col]) : 0m;
            decimal? GetNullDec(string col) => colNames.Contains(col) && !reader.IsDBNull(reader.GetOrdinal(col)) ? Convert.ToDecimal(reader[col]) : null;
            int? GetInt(string col) => colNames.Contains(col) && !reader.IsDBNull(reader.GetOrdinal(col)) ? Convert.ToInt32(reader[col]) : null;

            item.ADBranchName = GetStr("ADBranchName");
            item.NonADBranchName = GetStr("NonADBranchName");
            item.AdvisingNumber = GetStr("AdvisingNumber");
            item.AdvisingDate = GetDate("AdvisingDate");
            item.TransactionRef = GetStr("TransactionRef");
            item.ExportLCNo = GetStr("ExportLCNo");
            item.LCType = GetStr("LCType");
            item.BBLCSCNumber = GetStr("BBLCSCNumber");
            item.LCSubType = GetStr("LCSubType");
            item.LCSubTypeDescription = GetStr("LCSubTypeDescription");
            item.TenorType = GetStr("TenorType");
            item.Tenor = GetStr("Tenor");
            item.TenorDescription = GetStr("TenorDescription");
            item.IssueDate = GetDate("IssueDate");
            item.Currency = GetStr("Currency");
            item.Amount = GetDec("Amount");
            item.EquivalentinUSD = GetDec("EquivalentinUSD");
            item.ExchangeRate = GetDec("ExchangeRate");
            item.EquivalentinBDT = GetDec("EquivalentinBDT");
            item.ShipmentDate = GetDate("ShipmentDate");
            item.ExpiryDate = GetDate("ExpiryDate");
            item.Tolerance = GetNullDec("Tolerance");
            item.LiabRevDate = GetInt("LiabRevDate");
            item.ClosingDate = GetDate("ClosingDate");
            item.Commodity = GetStr("Commodity");
            item.IssueBank = GetStr("IssueBank");
            item.IssueBranch = GetStr("IssueBranch");
            item.CustomerNonCustomer = GetStr("CustomerNonCustomer");
            item.Benificiary = GetStr("Benificiary");
            item.CustomerID = GetStr("CustomerID");
            item.CustomerType = GetStr("CustomerType");
            item.Applicant = GetStr("Applicant");
            item.ApplicantsCountry = GetStr("ApplicantsCountry");
            item.JobNumber = GetInt("JobNumber");
            item.R06Reference = GetInt("R06Reference");
            item.InputterName = GetStr("InputterName");
            item.InputTime = GetDate("InputTime");
            item.AuthorisedBy = GetStr("AuthorisedBy");
            item.AuthTime = GetDate("AuthTime");
            item.ChargeRealizationStatus = GetInt("ChargeRealizationStatus");
            item.ChargeAmt = GetInt("ChargeAmt");
            item.ChargeDebAcc = GetInt("ChargeDebAcc");
            item.IssuingBanksBIC = GetInt("IssuingBanksBIC");
            item.AdvisingBanksBIC = GetInt("AdvisingBanksBIC");
            item.MessageType = GetStr("MessageType");
            item.IssuingBankBranchAddress = GetStr("IssuingBankBranchAddress");
            item.IssuingBankBranchEmail = GetStr("IssuingBankBranchEmail");
            item.IssuingBankAddress = GetStr("IssuingBankAddress");
            item.CustomerId = GetStr("CustomerId");
            item.WaiverCharge = GetNullDec("WaiverCharge");
            item.TransferableStatus = GetStr("TransferableStatus");
            item.CMTAmount = GetNullDec("CMTAmount");
            item.CMTPercent = GetNullDec("CMTPercent");
            item.ADBranchID = GetStr("ADBranchID");
            item.LCIssuingBankSWIFTCode = GetStr("LCIssuingBankSWIFTCode");
            item.ClosingDate1 = GetDate("ClosingDate1");
            item.IssueingBankId = GetStr("IssueingBankId");
            item.ChargeDebitAccount = GetNullDec("ChargeDebitAccount");
            item.AdvisingBankName = GetStr("AdvisingBankName");
            item.ChargeStatus = GetStr("ChargeStatus");
            item.BICodAdvisingBank = GetStr("BICodAdvisingBank");
            item.ADCodeofIssuingBankBranch = GetStr("ADCodeofIssuingBankBranch");
            item.CountryOfLCIssuingBank = GetStr("CountryOfLCIssuingBank");
            item.RReference = GetStr("RReference");
            item.LCExpiryPlace = GetStr("LCExpiryPlace");
            item.FirstBeneficiaryName = GetStr("FirstBeneficiaryName");
            item.AvailablewithBankID = GetStr("AvailablewithBankID");
            item.FirstBeneficiaryCountry = GetStr("FirstBeneficiaryCountry");
            item.TransferringFirstAdvisingBankName = GetStr("TransferringFirstAdvisingBankName");
            item.AvailableWithBank1 = GetStr("AvailableWithBank1");
            item.CountryOfTransferringBank = GetStr("CountryOfTransferringBank");
            item.AdviseThruBank1 = GetStr("AdviseThruBank1");
            item.RMName = GetStr("RMName");
            item.ModeofTransport = GetStr("ModeofTransport");
            item.UnitPrice1 = GetNullDec("UnitPrice1");
            item.TBRM = GetStr("TBRM");
            item.LiabilityReversalDate = GetDate("LiabilityReversalDate");
            item.LCAdvisingStatus = GetStr("LCAdvisingStatus");
            item.PortOfLoading = GetStr("PortOfLoading");
            item.LienStatus = GetStr("LienStatus");
            item.PortOfDestination = GetStr("PortOfDestination");
            item.Remarks = GetStr("Remarks");
            item.PartShipment = GetStr("PartShipment");
            item.Transhipment = GetStr("Transhipment");
            item.PresentationDescription = GetStr("PresentationDescription");
            item.DraweeBankID = GetStr("DraweeBankID");
            item.DraweeName = GetStr("DraweeName");

            return item;
        }
    }
}
