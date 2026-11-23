--1. BTB LC Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 224;

--2. LC Amendment Advising Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 386;

--3. Customer Profile

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 1213;

--4. Lien Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 503;



-- 23/11/2026

--1. Import Bill Lodgment Register
UPDATE SystemManager..ReportSuiteField
SET Label = CASE
    WHEN ReportFieldId = 1216457 THEN 'From Bill Generation Date'
    WHEN ReportFieldId = 1216458 THEN 'To Bill Generation Date'
END
WHERE ReportFieldId IN (1216457, 1216458);

--2. BTB Accepted Liability Coverage
Update SystemManager..ReportSuite Set IsVisible = 1 Where ReportId = 510;

--3. BTB Party Wise Accepted Liability
Update SystemManager..ReportSuite Set IsVisible = 1 Where ReportId = 514;



