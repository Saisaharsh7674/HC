@IsTest
private class healthCheckEmailControllerTest {

    @TestSetup
    static void setupData() {

        // Create master record
        KPMG_Daily_Health_Check__c master = new KPMG_Daily_Health_Check__c(
            KPMG_Check_Date__c = Date.today()
        );
        insert master;

        // Summary log (non-detail)
        insert new KPMG_Health_Check_Log__c(
            KPMG_Daily_Health_Check__c = master.Id,
            KPMG_Section__c = 'Sales Cloud Integrations',
            KPMG_Sub_Section__c = 'Integration A',
            KPMG_Status__c = 'Green',
            KPMG_Total__c = 100,
            KPMG_Used__c = 50,
            KPMG_Details__c = 'All good',
            KPMG_Comments__c = 'No issues',
            KPMG_Next_Steps__c = 'None',
            KPMG_Is_Recurring__c = true,
            KPMG_Is_Detail__c = false,
            KPMG_Display_Order__c = 1
        );

        // Detail log
        insert new KPMG_Health_Check_Log__c(
            KPMG_Daily_Health_Check__c = master.Id,
            KPMG_Section__c = 'Sales Cloud Integrations',
            KPMG_Sub_Section__c = 'Detail Item',
            KPMG_Status__c = 'Red',
            KPMG_Is_Detail__c = true,
            KPMG_Parent_Item__c = 'Integration A',
            KPMG_Comments__c = 'Failure occurred',
            KPMG_Display_Order__c = 2
        );

        // Another summary log
        insert new KPMG_Health_Check_Log__c(
            KPMG_Daily_Health_Check__c = master.Id,
            KPMG_Section__c = 'Process',
            KPMG_Sub_Section__c = 'Flow Check',
            KPMG_Status__c = 'Amber',
            KPMG_Is_Detail__c = false,
            KPMG_Display_Order__c = 3
        );
    }

    @IsTest
    static void testControllerBuildAndGetters() {

        Id masterId = [SELECT Id FROM KPMG_Daily_Health_Check__c LIMIT 1].Id;

        Test.startTest();

        healthCheckEmailController ctrl = new healthCheckEmailController();
        ctrl.dailyCheckId = masterId;

        KPMG_Daily_Health_Check__c m = ctrl.getMaster();
        List<healthCheckEmailController.SectionWrap> sections = ctrl.getSections();
        List<healthCheckEmailController.DetailWrap> details = ctrl.getDetailGroups();
        String dateStr = ctrl.getCheckDate();
        String generated = ctrl.getGeneratedLabel();

        Test.stopTest();

        System.assertNotEquals(null, m);
        System.assert(sections.size() > 0);
        System.assert(details.size() > 0);
        System.assertNotEquals(null, dateStr);
        System.assertNotEquals(null, generated);
    }

    @IsTest
    static void testRowWrapMethods() {

        KPMG_Health_Check_Log__c log = [
            SELECT Id,
                   KPMG_Sub_Section__c,
                   KPMG_Status__c,
                   KPMG_Details__c,
                   KPMG_Comments__c,
                   KPMG_Next_Steps__c,
                   KPMG_Is_Recurring__c,
                   KPMG_Total__c,
                   KPMG_Used__c,
                   KPMG_Remaining__c,
                   KPMG_Image__c
            FROM KPMG_Health_Check_Log__c
            WHERE KPMG_Is_Detail__c = false
            LIMIT 1
        ];

        Test.startTest();

        healthCheckEmailController.RowWrap row =
            new healthCheckEmailController.RowWrap(log);

        Test.stopTest();

        System.assertNotEquals(null, row.getLabel());
        System.assertNotEquals(null, row.getStatus());
        System.assertNotEquals(null, row.getComments());
        System.assertNotEquals(null, row.getNextSteps());
        System.assertEquals('Yes', row.getRecurring());
        System.assertNotEquals(null, row.getTotal());
        System.assertNotEquals(null, row.getUsed());
        System.assertNotEquals(null, row.getRemaining());
        System.assertEquals('Healthy', row.getStatusLabel());
        System.assertNotEquals(null, row.getStatusIcon());
        System.assertNotEquals(null, row.getBadgeStyle());
    }

    @IsTest
    static void testStatusVariants() {

        Id masterId = [SELECT Id FROM KPMG_Daily_Health_Check__c LIMIT 1].Id;

        List<String> statuses = new List<String>{'Green', 'Amber', 'Red', 'Pending', 'N/A'};

        for (String s : statuses) {

            KPMG_Health_Check_Log__c log = new KPMG_Health_Check_Log__c(
                KPMG_Daily_Health_Check__c = masterId,
                KPMG_Section__c = 'Test',
                KPMG_Sub_Section__c = 'Test',
                KPMG_Status__c = s,
                KPMG_Is_Detail__c = false
            );
            insert log;

            healthCheckEmailController.RowWrap row =
                new healthCheckEmailController.RowWrap(log);

            System.assertNotEquals(null, row.getStatusLabel());
            System.assertNotEquals(null, row.getBadgeStyle());
        }
    }

    @IsTest
    static void testNoDataScenario() {

        healthCheckEmailController ctrl = new healthCheckEmailController();
        ctrl.dailyCheckId = null;

        Test.startTest();
        List<healthCheckEmailController.SectionWrap> sections = ctrl.getSections();
        List<healthCheckEmailController.DetailWrap> details = ctrl.getDetailGroups();
        Test.stopTest();

        System.assertEquals(0, sections.size());
        System.assertEquals(0, details.size());
    }
}