using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using TFAWebApplication.Models.Reports;
using TFAWebApplication.Services;

namespace TFAWebApplication.Controllers
{
    public class ReportsController : Controller
    {
        private readonly IReportService _reportService;
        private readonly ILcAdvisingDataService _dataService;
        private readonly IConfiguration _configuration;

        public ReportsController(
            IReportService reportService,
            ILcAdvisingDataService dataService,
            IConfiguration configuration)
        {
            _reportService = reportService;
            _dataService = dataService;
            _configuration = configuration;
        }

        public async Task<IActionResult> Index(
            DateTime? fromDate = null,
            DateTime? toDate = null,
            string? branch = "All",
            string? currency = "All",
            string? status = "All")
        {
            var effectiveFromDate = fromDate ?? DateTime.Today;
            var effectiveToDate = toDate ?? DateTime.Today;

            var efaConnStr = _configuration.GetConnectionString("EfaConnection") ?? string.Empty;
            string serverName = "192.168.1.3\\PBLTEST";
            string databaseName = "EFA";

            try
            {
                if (!string.IsNullOrWhiteSpace(efaConnStr))
                {
                    var builder = new SqlConnectionStringBuilder(efaConnStr);
                    serverName = string.IsNullOrWhiteSpace(builder.DataSource) ? "192.168.1.3\\PBLTEST" : builder.DataSource;
                    databaseName = string.IsNullOrWhiteSpace(builder.InitialCatalog) ? "EFA" : builder.InitialCatalog;
                }
            }
            catch
            {
                // Fall back to defaults if parsing fails
            }

            var (items, isSuccess, errorMessage) = await _dataService.GetAdvisingRegisterDataAsync(
                effectiveFromDate, effectiveToDate, branch, currency, status);

            var model = new LcAdvisingFilterViewModel
            {
                FromDate = effectiveFromDate,
                ToDate = effectiveToDate,
                BranchFilter = branch ?? "All",
                CurrencyFilter = currency ?? "All",
                StatusFilter = status ?? "All",
                IsSuccess = isSuccess,
                ErrorMessage = errorMessage,
                ServerName = serverName,
                DatabaseName = databaseName,
                TotalRecords = items.Count,
                TotalAmountUSD = items.Sum(x => x.EquivalentinUSD),
                TotalAmountBDT = items.Sum(x => x.EquivalentinBDT),
                ActiveBranchesCount = items.Select(x => x.ADBranchName).Where(x => !string.IsNullOrEmpty(x)).Distinct().Count(),
                Items = items
            };

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> PreviewPdf(
            DateTime? fromDate = null,
            DateTime? toDate = null,
            string? branch = "All",
            string? currency = "All",
            string? status = "All")
        {
            try
            {
                var effectiveFromDate = fromDate ?? DateTime.Today;
                var effectiveToDate = toDate ?? DateTime.Today;

                var pdfBytes = await _reportService.RenderLcAdvisingReportAsync("PDF", effectiveFromDate, effectiveToDate, branch, currency, status);
                Response.Headers.Append("Content-Disposition", "inline; filename=\"LC_Advising_Register_PBL.pdf\"");
                return File(pdfBytes, "application/pdf");
            }
            catch (Exception ex)
            {
                var detail = ex.InnerException != null ? $"{ex.Message} -> {ex.InnerException.Message}" : ex.Message;
                return StatusCode(500, $"Error rendering LC Advising Register PDF from Live Database: {detail}");
            }
        }

        [HttpGet]
        public async Task<IActionResult> PreviewImage(
            DateTime? fromDate = null,
            DateTime? toDate = null,
            string? branch = "All",
            string? currency = "All",
            string? status = "All")
        {
            try
            {
                var effectiveFromDate = fromDate ?? DateTime.Today;
                var effectiveToDate = toDate ?? DateTime.Today;

                var pngBytes = await _reportService.RenderLcAdvisingReportAsync("PNG", effectiveFromDate, effectiveToDate, branch, currency, status);
                Response.Headers.Append("Content-Disposition", "inline; filename=\"LC_Advising_Register_PBL.png\"");
                return File(pngBytes, "image/png");
            }
            catch (Exception ex)
            {
                var detail = ex.InnerException != null ? $"{ex.Message} -> {ex.InnerException.Message}" : ex.Message;
                return StatusCode(500, $"Error rendering LC Advising Register Image from Live Database: {detail}");
            }
        }

        [HttpGet]
        public async Task<IActionResult> Export(
            string format = "EXCEL",
            DateTime? fromDate = null,
            DateTime? toDate = null,
            string? branch = "All",
            string? currency = "All",
            string? status = "All")
        {
            try
            {
                var effectiveFromDate = fromDate ?? DateTime.Today;
                var effectiveToDate = toDate ?? DateTime.Today;

                var bytes = await _reportService.RenderLcAdvisingReportAsync(format, effectiveFromDate, effectiveToDate, branch, currency, status);
                var contentType = _reportService.GetContentType(format);
                var ext = _reportService.GetFileExtension(format);
                var fileName = $"LC_Advising_Register_PBL_{effectiveFromDate:yyyyMMdd}_{effectiveToDate:yyyyMMdd}.{ext}";

                return File(bytes, contentType, fileName);
            }
            catch (Exception ex)
            {
                var detail = ex.InnerException != null ? $"{ex.Message} -> {ex.InnerException.Message}" : ex.Message;
                return StatusCode(500, $"Error exporting report from Live Database: {detail}");
            }
        }
    }
}
