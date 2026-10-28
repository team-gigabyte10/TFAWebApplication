namespace TFAWebApplication.Services
{
    public interface IReportService
    {
        Task<byte[]> RenderLcAdvisingReportAsync(
            string format,
            DateTime fromDate,
            DateTime toDate,
            string? branch = null,
            string? currency = null,
            string? status = null);

        string GetContentType(string format);
        string GetFileExtension(string format);
    }
}
