--1. BTB LC Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 224;

--2. LC Amendment Advising Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 386;

--3. Customer Profile

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 1213;

--4. Lien Register

Update SystemManager..ReportSuite Set IsVisible = 0 Where ReportId = 503;

--5. Import Bill Lodgment Register

UPDATE SystemManager..ReportSuiteField
SET Label = CASE
    WHEN ReportFieldId = 1216457 THEN 'From Bill Generation Date'
    WHEN ReportFieldId = 1216458 THEN 'To Bill Generation Date'
END
WHERE ReportFieldId IN (1216457, 1216458);