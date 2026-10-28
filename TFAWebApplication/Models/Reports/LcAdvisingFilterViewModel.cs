namespace TFAWebApplication.Models.Reports
{
    public class LcAdvisingFilterViewModel
    {
        public DateTime FromDate { get; set; } = DateTime.Today;
        public DateTime ToDate { get; set; } = DateTime.Today;
        public string BranchFilter { get; set; } = "All";
        public string CurrencyFilter { get; set; } = "All";
        public string StatusFilter { get; set; } = "All";

        // KPI and Aggregate Stats
        public int TotalRecords { get; set; }
        public decimal TotalAmountUSD { get; set; }
        public decimal TotalAmountBDT { get; set; }
        public int ActiveBranchesCount { get; set; }

        // Live Database Connection Diagnostics
        public bool IsSuccess { get; set; }
        public string? ErrorMessage { get; set; }
        public string ServerName { get; set; } = "192.168.1.3\\PBLTEST";
        public string DatabaseName { get; set; } = "EFA";

        // Preview items for tabular grid
        public List<LcAdvisingRegisterItem> Items { get; set; } = new();
    }
}
