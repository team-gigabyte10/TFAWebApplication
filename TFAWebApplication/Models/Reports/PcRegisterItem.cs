namespace TFAWebApplication.Models.Reports
{
    public class PcRegisterItem
    {
        public string? BranchName { get; set; }
        public string? CustomerName { get; set; }
        public DateTime? DisburseDate { get; set; }
        public string? PCNumber { get; set; }
        public string? GroupRefNo { get; set; }
        public string? LoanCurrency { get; set; }
        public decimal? InterestRate { get; set; }
        public decimal? ExchangeRate { get; set; }
        public string? PCCondition { get; set; }
        public decimal? PctOfPCDisbursement { get; set; }
        public decimal? LoanAmount { get; set; }
        public DateTime? MaturityDate { get; set; }
        public decimal? LoanOutAmt { get; set; }
        public decimal? AdjustedAmount { get; set; }
        public DateTime? AdjustedDate { get; set; }
        public string? LastModifiedBy { get; set; }
    }

    public class PcRegisterFilterViewModel
    {
        public DateTime FromDate { get; set; }
        public DateTime ToDate { get; set; }
        public string Branch { get; set; } = "All";
        public string Customer { get; set; } = "All";
        public bool IsSuccess { get; set; } = true;
        public string? ErrorMessage { get; set; }
        public List<PcRegisterItem> Items { get; set; } = new();
    }
}
