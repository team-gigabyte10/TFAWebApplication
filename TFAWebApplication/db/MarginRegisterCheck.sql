-- Check of Opening Balance and Present Balance with dummy data. No procedure, no real table.
-- Run the whole script in SSMS. It only creates temp tables.

Declare @FromDate Date = '2026-01-01'
Declare @ToDate   Date = '2026-10-11'

-- Dummy margin transactions (the real data comes from ViewTransactionLedgerOBL)
Create Table #Dummy (TransanctionDate Datetime, TransRefNo Varchar(50), AC_NO Varchar(50), Currency Varchar(10), CreditAmount Numeric(18, 2), DebitAmount Numeric(18, 2))

Insert Into #Dummy Values
	('2025-12-10', 'T01', 'cus ac 01', 'USD', 100,  0),		-- before From Date
	('2025-12-20', 'T02', 'cus ac 01', 'USD',   0, 30),		-- before From Date
	('2026-01-05', 'T03', 'cus ac 01', 'USD',  90,  0),
	('2026-02-10', 'T04', 'cus ac 01', 'USD',   0, 40),
	('2026-03-01', 'T05', 'cus ac 01', 'USD',  50,  0),
	('2026-11-01', 'T06', 'cus ac 01', 'USD', 999,  0),		-- after To Date, must not count
	('2026-01-15', 'T07', 'cus ac 02', 'USD', 200,  0),
	('2026-01-15', 'T08', 'cus ac 02', 'USD',   0, 50)

-- All rows up to To Date, with a row number (older rows are needed for the balance)
select ROW_NUMBER() Over (Order By TransanctionDate, TransRefNo) Seq, *
into #Ledger
from #Dummy
where CAST(TransanctionDate As Date) <= @ToDate


-- Option A: running balance on every row
;With Running As
(
	select T.*,
		SUM(CreditAmount - DebitAmount) Over (Partition By AC_NO, Currency Order By Seq Rows Between Unbounded Preceding And Current Row) PresentBalance
	from #Ledger T
)
select
	R.TransRefNo, R.TransanctionDate, R.AC_NO, R.Currency, R.CreditAmount [Margin Credit], R.DebitAmount [Margin Debit],
	R.PresentBalance - (R.CreditAmount - R.DebitAmount)	[Opening Balance],
	R.PresentBalance									[Present Balance]
from Running R
where CAST(R.TransanctionDate As Date) >= @FromDate
order by R.AC_NO, R.Seq

-- Expected result of Option A
--   T03  cus ac 01   credit  90  debit  0   Opening  70   Present 160
--   T04  cus ac 01   credit   0  debit 40   Opening 160   Present 120
--   T05  cus ac 01   credit  50  debit  0   Opening 120   Present 170
--   T07  cus ac 02   credit 200  debit  0   Opening   0   Present 200
--   T08  cus ac 02   credit   0  debit 50   Opening 200   Present 150


-- Option B: balance on From Date and on To Date, same on every row of the account
select T.AC_NO, T.Currency,
	SUM(Case When CAST(T.TransanctionDate As Date) < @FromDate Then T.CreditAmount - T.DebitAmount Else 0 End) OpeningBalance,
	SUM(T.CreditAmount - T.DebitAmount) PresentBalance
into #Balance
from #Ledger T
group by T.AC_NO, T.Currency

select
	T.TransRefNo, T.TransanctionDate, T.AC_NO, T.Currency, T.CreditAmount [Margin Credit], T.DebitAmount [Margin Debit],
	B.OpeningBalance [Opening Balance],
	B.PresentBalance [Present Balance]
from #Ledger T
	Left Join #Balance B ON B.AC_NO = T.AC_NO AND B.Currency = T.Currency
where CAST(T.TransanctionDate As Date) >= @FromDate
order by T.AC_NO, T.Seq

-- Expected result of Option B
--   T03, T04, T05   cus ac 01   Opening  70   Present 170
--   T07, T08        cus ac 02   Opening   0   Present 150

Drop Table #Dummy
Drop Table #Ledger
Drop Table #Balance
