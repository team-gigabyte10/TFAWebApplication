using Microsoft.AspNetCore.Mvc;
using TFAWebApplication.Models.Reports;
using TFAWebApplication.Services;

namespace TFAWebApplication.Controllers
{
    public class PcRegisterController : Controller
    {
        private readonly IPcRegisterService _service;
        private readonly IReportService _reportService;

        public PcRegisterController(IPcRegisterService service, IReportService reportService)
        {
            _service = service;
            _reportService = reportService;
        }

        public async Task<IActionResult> Index(
            DateTime? fromDate = null,
            DateTime? toDate = null,
            string? branch = "All",
            string? customer = "All")
        {
            var from = fromDate ?? DateTime.Today;
            var to = toDate ?? DateTime.Today;
            if (string.IsNullOrWhiteSpace(branch)) branch = "All";
            if (string.IsNullOrWhiteSpace(customer)) customer = "All";

            var (items, isSuccess, error) = await _service.GetDataAsync(from, to, branch, customer);
            return View(new PcRegisterFilterViewModel
            {
                FromDate = from,
                ToDate = to,
                Branch = branch,
                Customer = customer,
                IsSuccess = isSuccess,
                ErrorMessage = error,
                Items = items
            });
        }

        [HttpGet]
        public Task<IActionResult> PreviewPdf(DateTime? fromDate = null, DateTime? toDate = null, string? branch = "All", string? customer = "All")
            => RenderAsync("PDF", fromDate, toDate, branch, customer, inline: true);

        [HttpGet]
        public Task<IActionResult> Export(string format = "EXCEL", DateTime? fromDate = null, DateTime? toDate = null, string? branch = "All", string? customer = "All")
            => RenderAsync(format, fromDate, toDate, branch, customer, inline: false);

        private async Task<IActionResult> RenderAsync(string format, DateTime? fromDate, DateTime? toDate, string? branch, string? customer, bool inline)
        {
            try
            {
                var bytes = await _service.RenderAsync(format, fromDate ?? DateTime.Today, toDate ?? DateTime.Today, branch, customer);
                var fileName = $"PC_Register_PBL.{_reportService.GetFileExtension(format)}";
                if (inline)
                {
                    Response.Headers.Append("Content-Disposition", $"inline; filename=\"{fileName}\"");
                    return File(bytes, _reportService.GetContentType(format));
                }
                return File(bytes, _reportService.GetContentType(format), fileName);
            }
            catch (Exception ex)
            {
                var detail = ex.InnerException != null ? $"{ex.Message} -> {ex.InnerException.Message}" : ex.Message;
                return StatusCode(500, $"Error rendering PC Register: {detail}");
            }
        }
    }
}
