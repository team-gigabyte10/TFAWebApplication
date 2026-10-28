using TFAWebApplication.Models.Reports;

namespace TFAWebApplication.Services
{
    public interface IPcRegisterService
    {
        Task<(List<PcRegisterItem> Items, bool IsSuccess, string? ErrorMessage)> GetDataAsync(
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? customer = null);

        Task<byte[]> RenderAsync(
            string format,
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? customer = null);
    }
}
