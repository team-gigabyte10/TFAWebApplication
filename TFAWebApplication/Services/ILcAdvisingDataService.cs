using TFAWebApplication.Models.Reports;

namespace TFAWebApplication.Services
{
    public interface ILcAdvisingDataService
    {
        Task<(List<LcAdvisingRegisterItem> Items, bool IsSuccess, string? ErrorMessage)> GetAdvisingRegisterDataAsync(
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? currency = null,
            string? status = null);

        Task<List<CompanyInfoItem>> GetCompanyInfoAsync();
    }
}
