@IsTest
private class healthCheckManualInputControllerTest {

    @TestSetup
    static void setupData() {

        // Insert Custom Setting (Org Defaults)
        KPMG_Heath_Check_Email_Config__c cfg = new KPMG_Heath_Check_Email_Config__c();
        cfg.SetupOwnerId = UserInfo.getOrganizationId();
        cfg.KPMG_To_Recipients__c = 'test@example.com';
        cfg.KPMG_CC_Recipients__c = 'cc@example.com';
        insert cfg;

        // Create master record
        KPMG_Daily_Health_Check__c master = new KPMG_Daily_Health_Check__c(
            KPMG_Check_Date__c = Date.today(),
            KPMG_Email_Sent__c = false
        );
        insert master;

        // Automated log
        insert new KPMG_Health_Check_Log__c(
            KPMG_Daily_Health_Check__c = master.Id,
            KPMG_Section__c = 'System Health',
            KPMG_Sub_Section__c = 'Auto-1',
            KPMG_Status__c = 'Red',
            KPMG_Is_Manual__c = false,
            KPMG_Is_Pending__c = false
        );

        // Manual log
        insert new KPMG_Health_Check_Log__c(
            KPMG_Daily_Health_Check__c = master.Id,
            KPMG_Section__c = 'Manual Checks',
            KPMG_Sub_Section__c = 'Manual-1',
            KPMG_Status__c = 'Amber',
            KPMG_Is_Manual__c = true,
            KPMG_Is_Pending__c = true
        );
    }

    @IsTest
    static void testGetTodayCheck() {
        Test.startTest();
        healthCheckManualInputController.HealthCheckWrapper result =
            healthCheckManualInputController.getTodayCheck();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.master);
        System.assert(result.automatedLogs.size() > 0);
        System.assert(result.manualLogs.size() > 0);
        System.assertEquals('Red', result.overallStatus);
    }
}