@IsTest
private class healthCheckEmailComposerTest {

    @TestSetup
    static void setupData() {
        // Insert Hierarchy Custom Setting (Org Defaults)
        KPMG_Heath_Check_Email_Config__c cfg = new KPMG_Heath_Check_Email_Config__c();
        cfg.SetupOwnerId = UserInfo.getOrganizationId();
        cfg.KPMG_To_Recipients__c = 'test1@example.com; test2@example.com';
        cfg.KPMG_CC_Recipients__c = 'cc1@example.com, cc2@example.com';
        insert cfg;
    }

    @IsTest
    static void testSend_Success() {
        // Create test Daily Health Check record
        KPMG_Daily_Health_Check__c rec = new KPMG_Daily_Health_Check__c();
        insert rec;

        Test.startTest();
        healthCheckEmailComposer.send(rec.Id);
        Test.stopTest();

        // Verify Email Sent flag updated
        KPMG_Daily_Health_Check__c updatedRec = [
            SELECT KPMG_Email_Sent__c
            FROM KPMG_Daily_Health_Check__c
            WHERE Id = :rec.Id
        ];

        System.assertEquals(true, updatedRec.KPMG_Email_Sent__c, 
            'Email sent flag should be true');
    }

    @IsTest
    static void testSend_NoRecipients_Exception() {
        // Remove To recipients
        KPMG_Heath_Check_Email_Config__c cfg = 
            KPMG_Heath_Check_Email_Config__c.getOrgDefaults();

        cfg.KPMG_To_Recipients__c = null;
        update cfg;

        // Create record
        KPMG_Daily_Health_Check__c rec = new KPMG_Daily_Health_Check__c();
        insert rec;

        Test.startTest();

        try {
            healthCheckEmailComposer.send(rec.Id);
            System.assert(false, 'Expected exception was not thrown');
        } catch (healthCheckEmailComposer.EmailConfigException e) {
            System.assert(e.getMessage().contains('No "To" recipients'),
                'Exception message should mention missing recipients');
        }

        Test.stopTest();
    }

    @IsTest
    static void testSend_NullId_Exception() {
        Test.startTest();

        try {
            healthCheckEmailComposer.send(null);
            System.assert(false, 'Expected exception for null Id');
        } catch (healthCheckEmailComposer.EmailConfigException e) {
            System.assertEquals('dailyCheckId is required.', e.getMessage());
        }

        Test.stopTest();
    }

    @IsTest
    static void testSplitAddresses_IndirectCoverage() {
        // Update config with mixed separators and spaces
        KPMG_Heath_Check_Email_Config__c cfg = 
            KPMG_Heath_Check_Email_Config__c.getOrgDefaults();

        cfg.KPMG_To_Recipients__c = ' a@test.com , b@test.com ; c@test.com ';
        update cfg;

        KPMG_Daily_Health_Check__c rec = new KPMG_Daily_Health_Check__c();
        insert rec;

        Test.startTest();
        healthCheckEmailComposer.send(rec.Id);
        Test.stopTest();

        // Just verify no failure + flag updated
        rec = [SELECT KPMG_Email_Sent__c FROM KPMG_Daily_Health_Check__c WHERE Id = :rec.Id];
        System.assert(rec.KPMG_Email_Sent__c);
    }
}